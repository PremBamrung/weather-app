-- Weather metrics hypertable. Values are stored in METRIC units (converted at ingest).
-- The full original payload is kept in `raw` (JSONB) so no field is ever lost, even
-- from expansion sensors we don't yet parse explicitly.

CREATE TABLE IF NOT EXISTS weather_metrics (
    time              TIMESTAMPTZ  NOT NULL DEFAULT now(),  -- from dateutc when present, else ingest time
    station_id        TEXT         NOT NULL,   -- derived from PASSKEY
    temp_c            DOUBLE PRECISION,        -- from tempf
    humidity          DOUBLE PRECISION,        -- % RH
    pressure_hpa      DOUBLE PRECISION,        -- from baromrelin (relative / sea-level)
    wind_ms           DOUBLE PRECISION,        -- from windspeedmph
    gust_ms           DOUBLE PRECISION,        -- from windgustmph
    wind_dir          DOUBLE PRECISION,        -- degrees
    rain_mm_hr        DOUBLE PRECISION,        -- from rainratein (instantaneous rate)
    solar_wm2         DOUBLE PRECISION,        -- from solarradiation
    uv                DOUBLE PRECISION,        -- UV index
    -- Enriched columns (see docs/schema-enrichment.md). All nullable; historical
    -- values remain recoverable from `raw` even when a field is absent.
    temp_in_c         DOUBLE PRECISION,        -- from tempinf (indoor)
    humidity_in       DOUBLE PRECISION,        -- from humidityin (indoor % RH)
    pressure_abs_hpa  DOUBLE PRECISION,        -- from baromabsin (station pressure)
    wind_dir_avg10m   DOUBLE PRECISION,        -- from winddir_avg10m (smoothed direction)
    max_daily_gust_ms DOUBLE PRECISION,        -- from maxdailygust
    rain_event_mm     DOUBLE PRECISION,        -- from eventrainin  (accumulation)
    rain_hourly_mm    DOUBLE PRECISION,        -- from hourlyrainin
    rain_daily_mm     DOUBLE PRECISION,        -- from dailyrainin
    rain_weekly_mm    DOUBLE PRECISION,        -- from weeklyrainin
    rain_monthly_mm   DOUBLE PRECISION,        -- from monthlyrainin
    rain_yearly_mm    DOUBLE PRECISION,        -- from yearlyrainin
    vpd_kpa           DOUBLE PRECISION,        -- from vpd (vapor-pressure deficit, gateway-computed)
    wh65_batt         SMALLINT,                -- from wh65batt: WS69 array battery flag (0 = OK)
    raw               JSONB,                   -- unpromoted keys only (unknown/new-sensor fields + metadata); promoted fields live in typed columns — see docs/pipeline/jsonb-storage.md
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
