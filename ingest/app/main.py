"""FastAPI ingestion service for Ecowitt GW3000 Custom Server uploads.

The gateway POSTs application/x-www-form-urlencoded bodies to /data/report. We parse
the flat key-value map, convert Imperial -> metric, and insert into TimescaleDB. The full
original payload is stored in `raw` (JSONB) so nothing is ever lost.

Point the GW3000 Custom Server at:  http://<NAS_IP>:8000/data/report  (protocol: Ecowitt)
"""

import json
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import asyncpg
from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse

from .conversions import (
    f_to_c,
    in_to_mm,
    inhg_to_hpa,
    mph_to_ms,
    parse_dateutc,
    to_float,
    to_int,
)

DATABASE_URL = os.environ["DATABASE_URL"]

INSERT_SQL = """
    INSERT INTO weather_metrics (
        time, station_id, temp_c, humidity, pressure_hpa,
        wind_ms, gust_ms, wind_dir, rain_mm_hr, solar_wm2, uv,
        temp_in_c, humidity_in, pressure_abs_hpa, wind_dir_avg10m, max_daily_gust_ms,
        rain_event_mm, rain_hourly_mm, rain_daily_mm, rain_weekly_mm,
        rain_monthly_mm, rain_yearly_mm, vpd_kpa, wh65_batt, raw
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,
              $17,$18,$19,$20,$21,$22,$23,$24,$25)
    ON CONFLICT (station_id, time) DO NOTHING
"""


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.pool = await asyncpg.create_pool(DATABASE_URL, min_size=1, max_size=5)
    yield
    await app.state.pool.close()


app = FastAPI(title="Weather ingest", lifespan=lifespan)


@app.get("/health")
async def health():
    async with app.state.pool.acquire() as conn:
        await conn.execute("SELECT 1")
    return {"status": "ok"}


@app.post("/data/report")
@app.post("/data/report/")  # gateway may send a trailing slash
async def ingest(request: Request):
    form = await request.form()
    data = {k: v for k, v in form.items()}

    station_id = data.get("PASSKEY") or data.get("stationtype") or "unknown"

    # Prefer the gateway's own UTC clock (dateutc); fall back to ingest time. This keeps
    # stored time aligned with the device and is required for correct SD-card backfill,
    # where ingest time != observation time. See docs/schema-enrichment.md.
    obs_time = parse_dateutc(data.get("dateutc")) or datetime.now(timezone.utc)

    record = (
        obs_time,
        station_id,
        _conv(data.get("tempf"), f_to_c),
        to_float(data.get("humidity")),
        _conv(data.get("baromrelin"), inhg_to_hpa),
        _conv(data.get("windspeedmph"), mph_to_ms),
        _conv(data.get("windgustmph"), mph_to_ms),
        to_float(data.get("winddir")),
        _conv(data.get("rainratein"), in_to_mm),
        to_float(data.get("solarradiation")),
        to_float(data.get("uv")),
        # Enriched fields (docs/schema-enrichment.md).
        _conv(data.get("tempinf"), f_to_c),
        to_float(data.get("humidityin")),
        _conv(data.get("baromabsin"), inhg_to_hpa),
        to_float(data.get("winddir_avg10m")),
        _conv(data.get("maxdailygust"), mph_to_ms),
        _conv(data.get("eventrainin"), in_to_mm),
        _conv(data.get("hourlyrainin"), in_to_mm),
        _conv(data.get("dailyrainin"), in_to_mm),
        _conv(data.get("weeklyrainin"), in_to_mm),
        _conv(data.get("monthlyrainin"), in_to_mm),
        _conv(data.get("yearlyrainin"), in_to_mm),
        to_float(data.get("vpd")),
        to_int(data.get("wh65batt")),
        json.dumps(data),
    )

    async with app.state.pool.acquire() as conn:
        await conn.execute(INSERT_SQL, *record)

    # Ecowitt only needs a 200; body is ignored by the gateway.
    return PlainTextResponse("success")


def _conv(raw_value, fn):
    """Parse a raw string field and apply a conversion, or None if unparseable."""
    v = to_float(raw_value)
    return fn(v) if v is not None else None
