-- Rain-totals enrichment migration (see docs/schema-enrichment.md).
--
-- Promotes two rain fields the gateway sends that the original enrichment (03) missed:
-- totalrainin (all-time accumulator) and last24hrainin (rolling 24 h). Same deployment story
-- as 03/04: on a FRESH database the columns already exist from 02-schema.sql, so every
-- statement below is a harmless no-op; on an EXISTING deployment the migrate service
-- (docker-compose.yml) applies it on every `up`. Safe to re-run — the ADDs are IF NOT EXISTS
-- and the backfill only touches rows still missing the value.

ALTER TABLE weather_metrics
    ADD COLUMN IF NOT EXISTS rain_total_mm    DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS rain_last24h_mm  DOUBLE PRECISION;

-- One-off backfill from the JSONB payload. The conversion mirrors ingest/app/conversions.py
-- exactly: in_to_mm = v * 25.4. NULLIF(...,'') guards against blank fields; only rows still
-- missing the value are touched, so re-running is safe. These two keys were never promoted,
-- so they survive in `raw` on every historical row (including rows written after the raw-trim,
-- where they remained unpromoted) — the backfill reaches them all. Rows in compressed chunks
-- (older than the 7-day policy) cannot be updated in place — decompress first if you need
-- backfill that far back. Fresh installs have no rows to touch.
UPDATE weather_metrics SET
    rain_total_mm   = COALESCE(rain_total_mm,   NULLIF(raw->>'totalrainin', '')::double precision * 25.4),
    rain_last24h_mm = COALESCE(rain_last24h_mm, NULLIF(raw->>'last24hrainin', '')::double precision * 25.4)
WHERE raw IS NOT NULL
  AND (rain_total_mm IS NULL OR rain_last24h_mm IS NULL)
  AND (raw ? 'totalrainin' OR raw ? 'last24hrainin');
