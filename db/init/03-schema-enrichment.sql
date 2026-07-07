-- Schema enrichment migration (see docs/schema-enrichment.md).
--
-- On a FRESH database this runs right after 02-schema.sql, where the columns already
-- exist, so every statement below is a harmless no-op (the ADDs are IF NOT EXISTS and
-- the backfill matches no rows). On an EXISTING deployment, run this file by hand once:
--
--     docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
--         < db/init/03-schema-enrichment.sql
--
-- It promotes fields already captured in `raw` to typed columns for easier querying.

ALTER TABLE weather_metrics
    ADD COLUMN IF NOT EXISTS temp_in_c         DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS humidity_in       DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS pressure_abs_hpa  DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS wind_dir_avg10m   DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS max_daily_gust_ms DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS rain_event_mm     DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS rain_hourly_mm    DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS rain_daily_mm     DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS rain_weekly_mm    DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS rain_monthly_mm   DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS rain_yearly_mm    DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS vpd_kpa           DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS wh65_batt         SMALLINT;

-- One-off backfill of the new columns from the JSONB payload of existing rows.
-- Imperial -> metric conversions mirror ingest/app/conversions.py exactly:
--   f_to_c:      (f - 32) * 5/9        inhg_to_hpa: v * 33.8639
--   mph_to_ms:   v * 0.44704           in_to_mm:    v * 25.4
-- NULLIF(...,'') guards against blank fields; only rows still missing the value are
-- touched, so re-running is safe. Note: rows in compressed chunks (older than the
-- compression policy's 7 days) cannot be updated in place — decompress them first if
-- you need historical backfill that far back. Fresh installs have no rows to touch.
UPDATE weather_metrics SET
    temp_in_c         = COALESCE(temp_in_c,         (NULLIF(raw->>'tempinf', '')::double precision - 32.0) * 5.0 / 9.0),
    humidity_in       = COALESCE(humidity_in,        NULLIF(raw->>'humidityin', '')::double precision),
    pressure_abs_hpa  = COALESCE(pressure_abs_hpa,   NULLIF(raw->>'baromabsin', '')::double precision * 33.8639),
    wind_dir_avg10m   = COALESCE(wind_dir_avg10m,    NULLIF(raw->>'winddir_avg10m', '')::double precision),
    max_daily_gust_ms = COALESCE(max_daily_gust_ms,  NULLIF(raw->>'maxdailygust', '')::double precision * 0.44704),
    rain_event_mm     = COALESCE(rain_event_mm,      NULLIF(raw->>'eventrainin', '')::double precision * 25.4),
    rain_hourly_mm    = COALESCE(rain_hourly_mm,     NULLIF(raw->>'hourlyrainin', '')::double precision * 25.4),
    rain_daily_mm     = COALESCE(rain_daily_mm,      NULLIF(raw->>'dailyrainin', '')::double precision * 25.4),
    rain_weekly_mm    = COALESCE(rain_weekly_mm,     NULLIF(raw->>'weeklyrainin', '')::double precision * 25.4),
    rain_monthly_mm   = COALESCE(rain_monthly_mm,    NULLIF(raw->>'monthlyrainin', '')::double precision * 25.4),
    rain_yearly_mm    = COALESCE(rain_yearly_mm,     NULLIF(raw->>'yearlyrainin', '')::double precision * 25.4),
    vpd_kpa           = COALESCE(vpd_kpa,            NULLIF(raw->>'vpd', '')::double precision),
    wh65_batt         = COALESCE(wh65_batt,          NULLIF(raw->>'wh65batt', '')::smallint)
WHERE raw IS NOT NULL
  AND (temp_in_c IS NULL OR humidity_in IS NULL OR pressure_abs_hpa IS NULL
       OR wind_dir_avg10m IS NULL OR max_daily_gust_ms IS NULL OR rain_daily_mm IS NULL
       OR vpd_kpa IS NULL OR wh65_batt IS NULL);
