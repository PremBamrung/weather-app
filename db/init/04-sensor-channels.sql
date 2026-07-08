-- Multi-channel expansion-sensor readings (see docs/hardware/expansion-sensors.md).
--
-- The WN31 (up to 8 channels) and WH51 (up to 16 channels) are multi-channel sensors: one
-- gateway POST can carry many independent probes. Rather than widen weather_metrics with
-- dozens of sparse per-channel columns, each (sensor, channel) reading is one narrow row
-- here. weather_metrics stays the single-station "main array" table; this is its companion.
--
-- Same deployment story as 03-schema-enrichment.sql: on a FRESH database this runs right
-- after 02-schema.sql (harmless — CREATE ... IF NOT EXISTS, backfill matches no rows). On an
-- EXISTING deployment the migrate service (docker-compose.yml) applies it on every `up`. The
-- backfill re-derives channel rows from the JSONB `raw` already captured on existing
-- weather_metrics rows, so soil history recorded before this table existed is not lost.

CREATE TABLE IF NOT EXISTS sensor_channels (
    time        TIMESTAMPTZ      NOT NULL,   -- mirrors weather_metrics.time (dateutc, else ingest)
    station_id  TEXT             NOT NULL,   -- derived from PASSKEY
    sensor_type TEXT             NOT NULL,   -- 'wn31' (temp/humidity) | 'wh51' (soil)
    channel     SMALLINT         NOT NULL,   -- 1..8 (WN31) or 1..16 (WH51)
    temp_c      DOUBLE PRECISION,            -- WN31: from temp<ch>f (°F -> °C)
    humidity    DOUBLE PRECISION,            -- WN31: from humidity<ch> (% RH)
    soil_pct    DOUBLE PRECISION,            -- WH51: from soilmoisture<ch> (calibrated %)
    soil_ad     INTEGER,                     -- WH51: from soilad<ch> (raw capacitance AD value)
    batt        DOUBLE PRECISION,            -- WN31: batt<ch> flag (0/1); WH51: soilbatt<ch> volts
    PRIMARY KEY (station_id, sensor_type, channel, time)  -- includes `time` (hypertable requirement)
);

SELECT create_hypertable('sensor_channels', 'time',
                         chunk_time_interval => INTERVAL '1 week',
                         if_not_exists       => TRUE);

-- Columnar compression for chunks older than 7 days, mirroring weather_metrics. Segment by
-- the per-probe identity so each channel's series compresses independently.
ALTER TABLE sensor_channels SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'station_id, sensor_type, channel',
    timescaledb.compress_orderby   = 'time DESC'
);
SELECT add_compression_policy('sensor_channels', INTERVAL '7 days', if_not_exists => TRUE);

-- One-off backfill from the JSONB payload of existing weather_metrics rows. The WH51 has been
-- reporting since before this table existed, so its soil history lives in `raw`. Conversions
-- mirror ingest/app/conversions.py:  f_to_c = (f - 32) * 5/9;  soil_ad via float-then-int.
-- generate_series enumerates the possible channels; the `raw ? key` guard keeps only channels
-- actually present in a given payload. ON CONFLICT DO NOTHING makes re-runs safe.
INSERT INTO sensor_channels (time, station_id, sensor_type, channel, soil_pct, soil_ad, batt)
SELECT wm.time, wm.station_id, 'wh51', ch,
       NULLIF(wm.raw->>('soilmoisture'||ch), '')::double precision,
       (NULLIF(wm.raw->>('soilad'||ch), '')::double precision)::integer,
       NULLIF(wm.raw->>('soilbatt'||ch), '')::double precision
FROM weather_metrics wm
CROSS JOIN generate_series(1, 16) AS ch
WHERE wm.raw IS NOT NULL
  AND wm.raw ? ('soilmoisture'||ch)
ON CONFLICT (station_id, sensor_type, channel, time) DO NOTHING;

INSERT INTO sensor_channels (time, station_id, sensor_type, channel, temp_c, humidity, batt)
SELECT wm.time, wm.station_id, 'wn31', ch,
       (NULLIF(wm.raw->>('temp'||ch||'f'), '')::double precision - 32.0) * 5.0 / 9.0,
       NULLIF(wm.raw->>('humidity'||ch), '')::double precision,
       NULLIF(wm.raw->>('batt'||ch), '')::double precision
FROM weather_metrics wm
CROSS JOIN generate_series(1, 8) AS ch
WHERE wm.raw IS NOT NULL
  AND wm.raw ? ('temp'||ch||'f')
ON CONFLICT (station_id, sensor_type, channel, time) DO NOTHING;
