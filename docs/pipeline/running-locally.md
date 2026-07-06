# Running the Ingestion Stack

Track A pipeline: **TimescaleDB (with pgvector) + FastAPI ingestion + Grafana**, all in one
Docker Compose stack. One PostgreSQL container serves both time-series and vector-search
needs — no separate databases.

## Layout

```
docker-compose.yml
.env.example              # copy to .env
db/init/                  # SQL run once on first DB init
  01-extensions.sql       # timescaledb + vector (+ optional vectorscale/postgis)
  02-schema.sql           # weather_metrics hypertable + compression policy
ingest/                   # FastAPI service
  app/main.py             # POST /data/report  (Ecowitt Custom Server target)
  app/conversions.py      # Imperial -> metric
grafana/provisioning/     # auto-configured TimescaleDB datasource
```

## First run

```bash
cp .env.example .env        # then edit the passwords
docker compose up -d --build
docker compose ps           # db should be (healthy)
```

Services:
- Ingestion API — `http://<NAS_IP>:8000`  (health: `GET /health`)
- Grafana — `http://<NAS_IP>:3000`  (login from .env)
- Postgres — `<NAS_IP>:5432`

## Smoke-test without hardware

Send a synthetic Ecowitt payload:

```bash
curl -X POST http://localhost:8000/data/report \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "PASSKEY=TESTSTATION&stationtype=GW3000&tempf=72.5&humidity=45&baromrelin=29.92&windspeedmph=4.2&windgustmph=6.1&winddir=180&rainratein=0.00&solarradiation=350&uv=3&freq=915M"
```

Verify the row landed (converted to metric):

```bash
docker compose exec db psql -U weather -d weather \
  -c "SELECT time, station_id, temp_c, pressure_hpa, wind_ms FROM weather_metrics ORDER BY time DESC LIMIT 5;"
```

`tempf=72.5` should appear as `temp_c ≈ 22.5`, `baromrelin=29.92` as `pressure_hpa ≈ 1013`.

## Point the GW3000 at it

In the gateway web UI → **Custom Server**:

| Field    | Value |
|----------|-------|
| Protocol | Ecowitt |
| Server   | `<NAS_IP>` |
| Port     | `8000` |
| Path     | `/data/report` |
| Interval | `60` (seconds) |

Give the gateway a **DHCP reservation** so its IP never changes. Details:
[GW3000 gateway](../hardware/gw3000-gateway.md).

## Notes

- `db/init/*.sql` runs **only** on first init (empty data dir). To re-run after schema
  changes: `docker compose down -v` (⚠️ wipes data) or apply migrations manually with `psql`.
- Inserts are idempotent on `(station_id, time)` — safe for the later
  [backfill pipeline](fault-tolerance.md).
- The `raw` JSONB column keeps every field, so expansion-sensor data (WN31, WH51) is captured
  even before we parse those fields into columns.
