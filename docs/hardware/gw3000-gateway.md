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

> **This network:** the GW3000's embedded web interface is at **http://192.168.0.14/**. Give
> the gateway a DHCP reservation so that address stays put across reboots.

Key settings:

| Field                | Value                                   | Notes |
|----------------------|-----------------------------------------|-------|
| Protocol Type        | **Ecowitt**                             | Not Wunderground — Ecowitt sends a clean HTTP POST body, Wunderground sends an obfuscated GET string. |
| Server / IP          | NAS local IP (e.g. `192.168.1.145`)     | Use a **DHCP reservation** for the NAS *and* the gateway. |
| Port                 | FastAPI container port                  | |
| Path                 | e.g. `/data/report`                     | Whatever your FastAPI route is. |
| Upload Interval      | **16 s** (this deployment)              | Matches the WS69 RF cadence 1:1 — see the trade-off below. |

> Assign a **static DHCP reservation** to the gateway in your router so a power blip or
> router reboot doesn't change its IP and break your logging pipeline.

## Upload interval trade-off

- **16 s** — real-time, zero-loss 1:1 mirror of the WS69 RF output, capturing every gust
  frame with no aliasing. **The interval chosen here:** wind is volatile and the WS69 is a
  16 s instrument, so this is the only rate that resolves it cleanly. ~5,400 rows/day, but
  rows are small (trimmed `raw`) and the slow fields compress to almost nothing. See
  [telemetry](../pipeline/telemetry.md).
- **30–60 s** — lighter write load, fine if you don't care about sub-minute wind. 30 s drops
  ~half the gust frames, 60 s ~three-quarters; the daily peak still survives via
  `maxdailygust`. Intermediate rates (20/30 s) alias against the 16 s source for little gain.
- **< 16 s** — pointless: the edge sensor only broadcasts every 16 s, so you'd just re-post
  duplicate values.

At 16 s the WS69 generates ~5,400 rows/day — the driver behind the
[TimescaleDB storage design](../pipeline/database.md).
