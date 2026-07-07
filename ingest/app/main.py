"""FastAPI ingestion service for Ecowitt GW3000 Custom Server uploads.

The gateway POSTs application/x-www-form-urlencoded bodies to /data/report. We parse
the flat key-value map, convert Imperial -> metric, and insert into TimescaleDB. The full
original payload is stored in `raw` (JSONB) so nothing is ever lost.

Point the GW3000 Custom Server at:  http://<NAS_IP>:8000/data/report  (protocol: Ecowitt)
"""

import json
import os
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse

from .conversions import f_to_c, in_to_mm, inhg_to_hpa, mph_to_ms, to_float

DATABASE_URL = os.environ["DATABASE_URL"]

INSERT_SQL = """
    INSERT INTO weather_metrics (
        station_id, temp_c, humidity, pressure_hpa,
        wind_ms, gust_ms, wind_dir, rain_mm_hr, solar_wm2, uv, raw
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
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

    record = (
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
