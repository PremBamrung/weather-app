# GW3000 — Gateway Hub

The GW3000 is the indoor hub: it listens on 915 MHz for every sensor it has learned,
holds the latest state vector for each, measures barometric pressure locally, buffers to a
MicroSD card, and uplinks over Ethernet to the NAS.

## Physical features

- **Dedicated external antenna** — adjustable; place the hub high (e.g. a shelf near the
  ceiling) to maximize packet frame retention from the rooftop array.
- **RJ45 Ethernet port** — wired uplink eliminates Wi-Fi handshake latency and jitter.
  Prefer this over Wi-Fi for a real-time, low-jitter stream.
- **MicroSD slot** — local `.csv` backup buffer (max **32 GB**, formatted **FAT32**). See
  [fault tolerance & backfill](../pipeline/fault-tolerance.md).
- **Onboard barometer** — the relative/absolute pressure fields (`baromrelin` /
  `baromabsin`) originate here, indoors, not from the WS69.

## Role in the pipeline: edge cache

The gateway continuously listens on 915 MHz, stores the newest reading for every sensor,
and packages it for upload. It is effectively a stateless-per-cycle edge cache — the last
known value per sensor is what gets POSTed each interval.

## Custom Server configuration

Bypass the Ecowitt cloud by pointing the gateway at the NAS. Configure via the **Embedded
Web Interface** (recommended for a software engineer — no app/cloud account needed) or the
Ecowitt mobile app.

Key settings:

| Field                | Value                                   | Notes |
|----------------------|-----------------------------------------|-------|
| Protocol Type        | **Ecowitt**                             | Not Wunderground — Ecowitt sends a clean HTTP POST body, Wunderground sends an obfuscated GET string. |
| Server / IP          | NAS local IP (e.g. `192.168.1.145`)     | Use a **DHCP reservation** for the NAS *and* the gateway. |
| Port                 | FastAPI container port                  | |
| Path                 | e.g. `/data/report`                     | Whatever your FastAPI route is. |
| Upload Interval      | **60 s** (this deployment)              | Minimum useful is 16 s (the WS69 RF cadence). This build uses 60 s — see the trade-off below. |

> Assign a **static DHCP reservation** to the gateway in your router so a power blip or
> router reboot doesn't change its IP and break your logging pipeline.

## Upload interval trade-off

- **16 s** — real-time, zero-loss 1:1 mirror of the WS69 RF output. Only worth it for a
  gust-specific model; otherwise it just stores rows the hourly ML target averages away.
- **60 s** — the general default and **the interval chosen here**: ~1,440 rows/day, lighter
  write load, resolves every real weather trend. Sole cost is sub-minute wind-gust detail
  (the daily peak is still captured via `maxdailygust`). See [telemetry](../pipeline/telemetry.md).
- **< 16 s** — pointless: the edge sensor only broadcasts every 16 s, so you'd just re-post
  duplicate values.

At 60 s the WS69 generates ~1,440 rows/day — the driver behind the
[TimescaleDB storage design](../pipeline/database.md).
