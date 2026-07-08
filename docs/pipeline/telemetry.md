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

- **This deployment:** upload interval set to **60 s** over wired Ethernet. The WS69 still
  broadcasts every 16 s over RF, so each POST carries only the *latest* cached frame and the
  ~3 intervening frames are dropped — a deliberate ~4:1 decimation.
- **Why 60 s, not 16 s:** the ML targets downscale to *hourly* HRDPS/METAR, so sub-minute
  outdoor data is averaged straight back to the hour — 16 s would just store rows the target
  throws away. 60 s keeps ~1,440 rows/day and still resolves every real weather trend.
- **What 60 s costs:** only sub-minute **wind-gust** resolution. `windgustmph` reflects the
  latest RF frame, and the gateway does *not* roll up a max across the upload interval, so
  intra-minute gust peaks between POSTs are not captured in `gust_ms`. The **daily peak gust
  is still lossless** via `maxdailygust` → `max_daily_gust_ms`, which the gateway accumulates
  continuously. Cumulative rain counters are likewise unaffected. Revisit 60 s only if you
  add a gust-specific model.

Wired Ethernet (RJ45) is used instead of Wi-Fi to eliminate handshake latency and jitter.

## Volume implication

At a 60 s interval the WS69 produces **~1,440 rows/day** (~526 k rows/year). Even this modest
rate is why storage uses TimescaleDB hypertables and columnar compression rather than stock
PostgreSQL or SQLite — see [database architecture](database.md).
