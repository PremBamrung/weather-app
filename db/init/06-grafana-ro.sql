-- Read-only role for Grafana (see docs/grafana-review.md, P3 "Read-only DB role").
--
-- Grafana connects as the owner role today, so anyone at the Explore tab can run DDL/DML
-- (DROP TABLE, DELETE, ...). This creates a login role with SELECT-only access and switches the
-- Grafana datasource to it (docker-compose.yml grafana env -> timescale.yml). Low urgency on a
-- LAN, but cheap and removes an easy foot-gun.
--
-- Deployment: run by the migrate service on every `up`, before Grafana starts. Idempotent — the
-- role is created only if absent, GRANTs are additive, and the password is (re)set from the
-- :grafana_ro_pw psql variable the migrate service passes (defaults to 'grafana_ro'; override via
-- GRAFANA_DB_PASSWORD in .env and keep it in sync with the datasource — same env var feeds both).

SELECT format('CREATE ROLE grafana_ro LOGIN PASSWORD %L', :'grafana_ro_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana_ro')
\gexec

-- Keep the password aligned with the env var on every run (harmless if unchanged).
ALTER ROLE grafana_ro WITH LOGIN PASSWORD :'grafana_ro_pw';

-- SELECT on everything that exists now, plus anything created later (future hypertables, the ML
-- feature table, etc.) via default privileges. USAGE on the schema is required to see the tables.
GRANT USAGE ON SCHEMA public TO grafana_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_ro;
