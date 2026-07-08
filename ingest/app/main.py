"""FastAPI ingestion service for Ecowitt GW3000 Custom Server uploads.

The gateway POSTs application/x-www-form-urlencoded bodies to /data/report. We parse
the flat key-value map, convert Imperial -> metric, and insert into TimescaleDB. Fields
that already have a typed column are stripped from `raw`; only the *unpromoted* remainder
(unknown / new-sensor fields and low-cardinality metadata) is kept as JSONB — so a new
sensor's data is never lost, without bloating every row with a second copy of the promoted
measurements (~76% of each row before this). See docs/pipeline/jsonb-storage.md.

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

# Multi-channel expansion sensors land in the narrow sensor_channels companion table
# (see db/init/04-sensor-channels.sql and docs/hardware/expansion-sensors.md).
CHANNEL_INSERT_SQL = """
    INSERT INTO sensor_channels (
        time, station_id, sensor_type, channel,
        temp_c, humidity, soil_pct, soil_ad, batt
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
    ON CONFLICT (station_id, sensor_type, channel, time) DO NOTHING
"""

# Ecowitt caps WN31 at 8 channels and WH51 at 16 channels on a GW3000.
WN31_MAX_CH = 8
WH51_MAX_CH = 16

# Payload keys already persisted elsewhere and therefore dropped from `raw`: the promoted
# measurements (typed columns on weather_metrics), every per-channel expansion-sensor key
# (sensor_channels), and PASSKEY/dateutc (station_id/time — payload-format.md also says not to
# keep PASSKEY verbatim). What survives in `raw` is only unknown/new-sensor fields plus
# metadata (stationtype, model, freq, runtime). See docs/pipeline/jsonb-storage.md.
_CHANNEL_KEYS = frozenset(
    [f"temp{ch}f" for ch in range(1, WN31_MAX_CH + 1)]
    + [f"humidity{ch}" for ch in range(1, WN31_MAX_CH + 1)]
    + [f"batt{ch}" for ch in range(1, WN31_MAX_CH + 1)]
    + [f"soilmoisture{ch}" for ch in range(1, WH51_MAX_CH + 1)]
    + [f"soilad{ch}" for ch in range(1, WH51_MAX_CH + 1)]
    + [f"soilbatt{ch}" for ch in range(1, WH51_MAX_CH + 1)]
)
_PROMOTED_KEYS = frozenset({
    "PASSKEY", "dateutc",
    "tempf", "humidity", "baromrelin", "windspeedmph", "windgustmph",
    "winddir", "rainratein", "solarradiation", "uv",
    "tempinf", "humidityin", "baromabsin", "winddir_avg10m", "maxdailygust",
    "eventrainin", "hourlyrainin", "dailyrainin", "weeklyrainin",
    "monthlyrainin", "yearlyrainin", "vpd", "wh65batt",
}) | _CHANNEL_KEYS


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
        json.dumps(_unpromoted(data)),
    )

    channel_rows = _channel_rows(data, obs_time, station_id)

    # One transaction: the main-array row and its per-channel rows commit together.
    async with app.state.pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(INSERT_SQL, *record)
            if channel_rows:
                await conn.executemany(CHANNEL_INSERT_SQL, channel_rows)

    # Ecowitt only needs a 200; body is ignored by the gateway.
    return PlainTextResponse("success")


def _channel_rows(data, obs_time, station_id):
    """Extract multi-channel expansion-sensor readings into sensor_channels rows.

    Field naming follows the Ecowitt Custom Server protocol (see docs/pipeline/payload-format.md):
      WN31 temp/humidity: temp<ch>f (°F), humidity<ch> (%), batt<ch> (0/1 low flag)
      WH51 soil:          soilmoisture<ch> (%), soilad<ch> (raw AD), soilbatt<ch> (volts)
    A channel is emitted only when its payload keys are present, so absent probes are skipped.
    Column order matches CHANNEL_INSERT_SQL:
      (time, station_id, sensor_type, channel, temp_c, humidity, soil_pct, soil_ad, batt)
    """
    rows = []
    for ch in range(1, WN31_MAX_CH + 1):
        tempf, humidity = data.get(f"temp{ch}f"), data.get(f"humidity{ch}")
        if tempf is None and humidity is None:
            continue
        rows.append((
            obs_time, station_id, "wn31", ch,
            _conv(tempf, f_to_c), to_float(humidity),
            None, None, to_float(data.get(f"batt{ch}")),
        ))
    for ch in range(1, WH51_MAX_CH + 1):
        moisture, soil_ad = data.get(f"soilmoisture{ch}"), data.get(f"soilad{ch}")
        if moisture is None and soil_ad is None:
            continue
        rows.append((
            obs_time, station_id, "wh51", ch,
            None, None,
            to_float(moisture), to_int(soil_ad), to_float(data.get(f"soilbatt{ch}")),
        ))
    return rows


def _conv(raw_value, fn):
    """Parse a raw string field and apply a conversion, or None if unparseable."""
    v = to_float(raw_value)
    return fn(v) if v is not None else None


def _unpromoted(data):
    """Payload keys not already stored in a typed column — the only part worth keeping in
    `raw`. Drops the promoted measurements, all per-channel keys, and PASSKEY/dateutc; keeps
    unknown/new-sensor fields and metadata (stationtype, model, freq, runtime).
    """
    return {k: v for k, v in data.items() if k not in _PROMOTED_KEYS}
