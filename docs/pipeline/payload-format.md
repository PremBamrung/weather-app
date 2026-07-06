# Payload Format & Parsing

The GW3000 fires an **unencrypted HTTP POST** with
`Content-Type: application/x-www-form-urlencoded`. The body is a **flat key-value map** —
one string, no nesting.

## Example body

```http
POST /data/report HTTP/1.1
Content-Type: application/x-www-form-urlencoded

PASSKEY=0123456789ABCDEF&stationtype=GW3000&runtime=3420&tempf=72.5&humidity=45&baromrelin=29.92&windspeedmph=4.2&windgustmph=6.1&winddir=180&rainratein=0.00&freq=915M
```

With expansion sensors attached, additional pairs appear in the same body, e.g.
`wh31batt1=1`, `temp1f=68.2`, `humidity1=48`, `wh51batt1=1.42`.

## Field reference

| Key            | Meaning                          | Native unit | Convert to |
|----------------|----------------------------------|-------------|------------|
| `PASSKEY`      | Unique hub identifier (station MAC-derived) | — | use as `station_id`, don't store raw |
| `stationtype`  | Model string (e.g. `GW3000`)     | —           | metadata |
| `model`        | Model (when present)             | —           | metadata |
| `runtime`      | Gateway uptime                   | seconds     | — |
| `freq`         | RF band (e.g. `915M`)            | —           | metadata |
| `tempf`        | Outdoor temperature              | °F          | °C |
| `humidity`     | Outdoor relative humidity        | %           | — |
| `baromrelin`   | Relative (sea-level) pressure    | inHg        | hPa |
| `baromabsin`   | Absolute (station) pressure      | inHg        | hPa |
| `windspeedmph` | Wind speed                       | mph         | m/s (or km/h) |
| `windgustmph`  | Wind gust                        | mph         | m/s (or km/h) |
| `winddir`      | Wind direction                   | degrees     | — |
| `rainratein`   | Rain rate                        | in/hr       | mm/hr |
| `solarradiation` / lux | Solar irradiance         | W/m² or lux | keep + derive |
| `uv`           | UV index                         | index       | — |
| `temp<ch>f`    | WN31 channel temperature         | °F          | °C |
| `humidity<ch>` | WN31 channel humidity            | %           | — |
| `wh31batt<ch>` | WN31 battery flag                | 0/1         | boolean (0 = normal, 1 = low) |
| `wh51batt<ch>` | WH51 battery voltage             | V           | float |

> Values arrive in **Imperial units**. The FastAPI layer performs the explicit physical
> conversions to metric **before** writing to the database. This is the single most common
> data-engineering trap in the pipeline.

## Unit conversions

```
°C      = (°F − 32) × 5/9
hPa     = inHg × 33.8639
m/s     = mph × 0.44704
km/h    = mph × 1.609344
mm      = in × 25.4
```

## FastAPI ingestion sketch

```python
from fastapi import FastAPI, Request

app = FastAPI()

def f_to_c(f: float) -> float:      return (f - 32) * 5 / 9
def inhg_to_hpa(v: float) -> float: return v * 33.8639
def mph_to_ms(v: float) -> float:   return v * 0.44704
def in_to_mm(v: float) -> float:    return v * 25.4

@app.post("/data/report")
async def ingest(request: Request):
    form = await request.form()               # x-www-form-urlencoded
    data = dict(form)

    station_id = data.get("PASSKEY")          # unique hub id
    record = {
        "station_id":  station_id,
        "temp_c":      f_to_c(float(data["tempf"]))       if "tempf" in data       else None,
        "humidity":    float(data["humidity"])            if "humidity" in data    else None,
        "pressure_hpa":inhg_to_hpa(float(data["baromrelin"])) if "baromrelin" in data else None,
        "wind_ms":     mph_to_ms(float(data["windspeedmph"])) if "windspeedmph" in data else None,
        "gust_ms":     mph_to_ms(float(data["windgustmph"]))  if "windgustmph" in data else None,
        "wind_dir":    float(data["winddir"])             if "winddir" in data     else None,
        "rain_mm_hr":  in_to_mm(float(data["rainratein"]))if "rainratein" in data  else None,
    }
    # write to TimescaleDB here ...

    return "success"   # Ecowitt only needs an HTTP 200
```

## Parsing rules

- **Return HTTP 200** with a simple body — the gateway just needs a success code.
- **Every field is optional.** Not all sensors report on every POST; use Pydantic with
  optional fields and `None` defaults rather than hard `KeyError`s.
- **Convert before persistence**, never store Imperial and metric in the same column.
- **Don't trust the timestamp from the device** for ordering — stamp on ingest, and treat
  the gateway CSV timestamps as authoritative only during [backfill](fault-tolerance.md).
- **Sanity-filter phantom rain** — rooftop pole vibration can spike `rainratein`; see
  [deployment](../deployment/montreal-rooftop.md).
