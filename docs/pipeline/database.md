# Database Architecture

A 60 s gateway upload interval produces **~1,440 rows/day**. Even at this modest cadence a
stock SQLite file or vanilla PostgreSQL instance suffers per-row metadata overhead and B-tree
index degradation over months/years. The store is therefore **TimescaleDB**.

## Image

```
timescale/timescaledb-ha:pg17
```

The HA image bundles pgvector / pgvectorscale / postgis alongside TimescaleDB, turning
PostgreSQL into a time-series database via **hypertables** while keeping full SQL.

## Hypertable partitioning

The metrics table is created as a hypertable partitioned into automatic time **chunks**
(e.g. weekly). Only the current chunk stays hot in RAM, so write performance stays fast and
roughly constant over years of accumulation.

```sql
CREATE TABLE weather_metrics (
    time         TIMESTAMPTZ      NOT NULL,
    station_id   TEXT             NOT NULL,
    temp_c       DOUBLE PRECISION,
    humidity     DOUBLE PRECISION,
    pressure_hpa DOUBLE PRECISION,
    wind_ms      DOUBLE PRECISION,
    gust_ms      DOUBLE PRECISION,
    wind_dir     DOUBLE PRECISION,
    rain_mm_hr   DOUBLE PRECISION
);

SELECT create_hypertable('weather_metrics', 'time',
                         chunk_time_interval => INTERVAL '1 week');
```

## Compression

Older chunks are switched from row-oriented to **column-oriented** blocks:

- **Delta-of-delta encoding** for timestamps (near-constant 60 s cadence compresses hard).
- **Gorilla compression** for floating-point sensor values.
- Achieves ~**1.37 bits per value** on average.

The numeric columns shrink dramatically (Gorilla reaches ~1–3 bytes/value). But the `raw`
JSONB column compresses far less and dominates the total — realistic annual footprint is
**~75–110 MB**, not the sub-50 MB the floats alone would suggest. See the [`raw` storage
note](jsonb-storage.md).

```sql
ALTER TABLE weather_metrics SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'station_id',
    timescaledb.compress_orderby   = 'time DESC'
);

-- compress chunks older than 7 days
SELECT add_compression_policy('weather_metrics', INTERVAL '7 days');
```

## Sizing reference

| Metric                       | Value |
|------------------------------|-------|
| Gateway upload interval      | 60 s (WS69 RF cadence is 16 s) |
| Rows / day                   | ~1,440 |
| Rows / year                  | ~526 k |
| Uncompressed / year          | ~500–650 MB (incl. `raw` JSONB) |
| Compressed / year (est.)     | ~75–110 MB — dominated by `raw`, see note |
| Avg bits / value (numeric)   | ~1.37 (floats only; `raw` compresses far worse) |

> Measured 2026-07-08 on the live NAS DB: the `raw` JSONB column is **~76 % of each
> uncompressed row**. Compression had not yet triggered (data < 7 days old → 0 compressed
> chunks), so the compressed figures remain estimates — re-check with
> `hypertable_compression_stats('weather_metrics')` after the first chunk ages past 7 days.

## Notes

- Query recent data from uncompressed chunks; historical analytics read compressed chunks
  transparently.
- Continuous aggregates (e.g. hourly/daily rollups) are a natural fit for dashboards and for
  aligning ground truth to hourly [NWP downscaling](../ml/outdoor-downscaling.md) features.
- Multi-channel expansion sensors land in a narrow companion hypertable rather than widening
  `weather_metrics` — see below and [expansion sensors](../hardware/expansion-sensors.md).

## Multi-channel companion table (`sensor_channels`)

The WN31 (up to 8 channels) and WH51 (up to 16 channels) each carry many independent probes in
one gateway POST. Widening `weather_metrics` with dozens of sparse per-channel columns ages
badly, so each `(sensor, channel)` reading is one narrow row in a companion hypertable
(`db/init/04-sensor-channels.sql`):

```sql
CREATE TABLE sensor_channels (
    time        TIMESTAMPTZ NOT NULL,
    station_id  TEXT        NOT NULL,
    sensor_type TEXT        NOT NULL,   -- 'wn31' | 'wh51'
    channel     SMALLINT    NOT NULL,   -- 1..8 (WN31) or 1..16 (WH51)
    temp_c      DOUBLE PRECISION,       -- WN31
    humidity    DOUBLE PRECISION,       -- WN31
    soil_pct    DOUBLE PRECISION,       -- WH51 calibrated %
    soil_ad     INTEGER,                -- WH51 raw capacitance AD
    batt        DOUBLE PRECISION,       -- WN31 0/1 flag; WH51 voltage
    PRIMARY KEY (station_id, sensor_type, channel, time)
);
```

- Same hypertable + 7-day compression policy as `weather_metrics`; `compress_segmentby`
  is `station_id, sensor_type, channel` so each probe's series compresses independently.
- The ingest service parses `temp<ch>f`/`humidity<ch>`/`batt<ch>` and
  `soilmoisture<ch>`/`soilad<ch>`/`soilbatt<ch>` into these rows in the same transaction as the
  main `weather_metrics` write.
- Current fleet (live as of 2026-07-08): **1× WH51** (soil, channel 1) reporting; the **WN31**
  room sensors are on the way and not yet present in `sensor_channels`. Adding more probes needs
  no schema change — new channels just appear as new rows.
- The migration backfills soil history already captured in `weather_metrics.raw` from before the
  table existed. Compressed chunks older than the policy window can't be updated in place; the
  backfill only reaches uncompressed rows unless you decompress first.
