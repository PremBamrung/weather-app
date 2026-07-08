# Telemetry & Frequencies

The pipeline avoids constant network handshakes by splitting the workflow into two
asynchronous tiers. The vendor cloud is not involved at any step.

```
[ WS69 Outdoor Sensor ]
       │  Asynchronous RF, 915 MHz, fixed 16 s interval (no ACK loop)
       ▼
[ GW3000 Gateway Hub ] ──► Local backup buffer [ MicroSD (FAT32) ]
       │  LAN Ethernet, local unencrypted HTTP POST
       │  Content-Type: application/x-www-form-urlencoded
       ▼
[ NAS: FastAPI container ]
       │  Pydantic validation + Imperial→metric conversion
       ▼
[ NAS: TimescaleDB container ] ──► compressed columnar chunks
```

## Tier 1 — Edge layer (sensor → gateway, RF)

Each sensor has a hardcoded broadcast interval. It wakes, transmits its telemetry for a
fraction of a second over 915 MHz, and sleeps again. There is **no confirmation loop**.

| Sensor | RF broadcast interval |
|--------|-----------------------|
| WS90 (ultrasonic/solid-state) | every 4.75–8.8 s |
| **WS69 (mechanical 7-in-1)**  | **every 16 s** |
| WN31 (indoor temp/humidity)   | every ~60 s |
| WH51 (soil moisture)          | every 70 s (drops to 10 s on a significant change) |

## Tier 2 — Ingestion layer (gateway → NAS, HTTP)

The GW3000 acts as an edge cache: it holds the latest state vector for every sensor and
POSTs it to the NAS on the **Custom Server Upload Interval**.

- **This deployment:** upload interval set to **16 s** over wired Ethernet — a 1:1 mirror of
  the WS69's RF cadence, so every broadcast frame is captured with no aliasing.
- **Why 16 s:** wind is volatile and the WS69 *is* a 16 s instrument, so this is the only rate
  that captures every gust frame cleanly. Anything slower drops frames (30 s loses ~half the
  gusts, 60 s ~three-quarters), and intermediate rates like 20/30 s alias against the 16 s
  source for little row-count saving. Storage is cheap enough to make 16 s the default here:
  rows are small now that `raw` holds only unpromoted keys — see [database](database.md).
- **What 16 s costs:** the slow fields (temp, pressure, humidity) are oversampled ~4× versus
  60 s, but they Gorilla-compress to almost nothing. `maxdailygust` → `max_daily_gust_ms`
  records the absolute daily peak regardless of interval, and cumulative rain counters are
  unaffected — so nothing is lost by going fast.

Wired Ethernet (RJ45) is used instead of Wi-Fi to eliminate handshake latency and jitter.

## Volume implication

At a 16 s interval the WS69 produces **~5,400 rows/day** (~1.97 M rows/year). That row rate is
exactly why storage uses TimescaleDB hypertables and columnar compression rather than stock
PostgreSQL or SQLite — see [database architecture](database.md).
