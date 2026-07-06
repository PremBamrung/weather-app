# Database Architecture

High-frequency sampling (16 s) produces **~5,400 rows/day**. A stock SQLite file or vanilla
PostgreSQL instance suffers heavy per-row metadata overhead and B-tree index degradation at
this cadence over months/years. The store is therefore **TimescaleDB**.

## Image

```
timescale/timescaledb:latest-pg16
```

This turns PostgreSQL into a time-series database via **hypertables** while keeping full SQL.

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

- **Delta-of-delta encoding** for timestamps (near-constant 16 s cadence compresses hard).
- **Gorilla compression** for floating-point sensor values.
- Achieves ~**1.37 bits per value** on average.

Net effect: an annual footprint of ~1 GB uncompressed shrinks to **< 50 MB**.

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
| Sample interval              | 16 s |
| Rows / day                   | ~5,400 |
| Rows / year                  | ~1.97 M |
| Uncompressed / year          | ~1 GB |
| Compressed / year            | < 50 MB |
| Avg bits / value             | ~1.37 |

## Notes

- Query recent data from uncompressed chunks; historical analytics read compressed chunks
  transparently.
- Continuous aggregates (e.g. hourly/daily rollups) are a natural fit for dashboards and for
  aligning ground truth to hourly [NWP downscaling](../ml/outdoor-downscaling.md) features.
- Multi-channel expansion sensors can be added as columns or a narrow
  `(station_id, channel, metric, value)` table depending on channel count — see
  [expansion sensors](../hardware/expansion-sensors.md).
