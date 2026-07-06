# Hyper-Local Microclimate Nowcasting — Documentation

Self-hosted weather station, telemetry pipeline, and thermodynamic ML sandbox for a
3rd-floor apartment + rooftop in Montreal, Quebec.

The system is fully local-first: the vendor cloud is bypassed entirely. An Ecowitt
sensor array broadcasts over sub-GHz RF to a local gateway, which POSTs raw telemetry
to a FastAPI service on a NAS, which validates/converts it and writes to TimescaleDB.
That ground-truth stream then feeds statistical-downscaling and grey-box thermal models.

```
[ WS69 Outdoor Array ] --915MHz RF--> [ GW3000 Gateway ] --HTTP POST--> [ FastAPI ] --> [ TimescaleDB ]
                                             |                                                  |
                                       [ MicroSD buffer ]                              [ ML sandbox ]
```

## Target stack

| Layer            | Choice                                               |
|------------------|------------------------------------------------------|
| Sensor array     | Ecowitt WS69 7-in-1 (part of the GW3002BU kit)       |
| Gateway          | Ecowitt GW3000 (Ethernet + MicroSD buffer)           |
| RF band          | 915 MHz (North America)                              |
| Ingestion        | Dockerized FastAPI + Pydantic                        |
| Storage          | TimescaleDB (`timescale/timescaledb:latest-pg16`)    |
| Compute          | Self-hosted NAS                                       |
| Location         | 3rd-floor apartment & rooftop, Montreal, QC          |

## Documentation map

### Hardware
- [Hardware overview](hardware/overview.md) — kit contents, band choice, ecosystem
- [WS69 outdoor sensor array](hardware/ws69-sensor-array.md) — the 7 measurements, power, RF
- [GW3000 gateway](hardware/gw3000-gateway.md) — receiver, custom-server config, SD buffer
- [Expansion sensors](hardware/expansion-sensors.md) — WN31 indoor, WH51 soil, roadmap

### Deployment
- [Montreal rooftop deployment](deployment/montreal-rooftop.md) — rigging, weatherproofing, winter

### Data & telemetry pipeline
- [Telemetry & frequencies](pipeline/telemetry.md) — the two transmission tiers
- [Payload format & parsing](pipeline/payload-format.md) — the Ecowitt POST body, field map, unit conversion
- [Database architecture](pipeline/database.md) — hypertables, compression, sizing
- [Fault tolerance & backfill](pipeline/fault-tolerance.md) — SD fail-safe, gap-filling cron

### Machine learning sandbox
- [Outdoor statistical downscaling](ml/outdoor-downscaling.md) — HRDPS bias correction, spatial features
- [Indoor thermal modeling](ml/indoor-thermal.md) — grey-box RC network / PINN
- [Prototyping & data volume](ml/prototyping-data-volume.md) — virtual sandbox, McTavish proxy, N-day buckets

### Reference
- [References & datasheets](references.md) — official Ecowitt manuals (PDF), HRDPS/Open-Meteo/METAR feeds, Montreal geospatial datasets
- [Design review](design-review.md) — risks, over-builds, and recommended build sequencing
