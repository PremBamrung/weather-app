-- Weather metrics hypertable. Values are stored in METRIC units (converted at ingest).
-- The full original payload is kept in `raw` (JSONB) so no field is ever lost, even
-- from expansion sensors we don't yet parse explicitly.

CREATE TABLE IF NOT EXISTS weather_metrics (
    time          TIMESTAMPTZ      NOT NULL DEFAULT now(),
    station_id    TEXT             NOT NULL,   -- derived from PASSKEY
    temp_c        DOUBLE PRECISION,            -- from tempf
    humidity      DOUBLE PRECISION,            -- % RH
    pressure_hpa  DOUBLE PRECISION,            -- from baromrelin
    wind_ms       DOUBLE PRECISION,            -- from windspeedmph
    gust_ms       DOUBLE PRECISION,            -- from windgustmph
    wind_dir      DOUBLE PRECISION,            -- degrees
    rain_mm_hr    DOUBLE PRECISION,            -- from rainratein
    solar_wm2     DOUBLE PRECISION,            -- from solarradiation
    uv            DOUBLE PRECISION,            -- UV index
    raw           JSONB,                       -- full original key-value payload
    PRIMARY KEY (station_id, time)             -- includes `time` (hypertable requirement)
);

SELECT create_hypertable('weather_metrics', 'time',
                         chunk_time_interval => INTERVAL '1 week',
                         if_not_exists       => TRUE);

-- Optional: columnar compression for chunks older than 7 days.
ALTER TABLE weather_metrics SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'station_id',
    timescaledb.compress_orderby   = 'time DESC'
);
SELECT add_compression_policy('weather_metrics', INTERVAL '7 days', if_not_exists => TRUE);
