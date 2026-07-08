# Expansion Sensors

One GW3000 gateway can read dozens of multi-channel Ecowitt sensors simultaneously, so the
database can grow over time without changing the base hardware. The two near-term additions
are the WN31 (indoor rooms) and WH51 (plants/soil). Both are **owned now**: the WH51 is
already installed and reporting (`CH1 Soil` on the gateway's Live Data page); the WN31 arrives
in a few days. Specs below are confirmed against the operation manuals — see
[references](../references.md) and the local PDFs in [`datasheets/`](datasheets/).

## WN31 (WH31) — Multi-channel Temp/Humidity (indoor)

- **Use:** per-room indoor climate — feeds the [indoor thermal model](../ml/indoor-thermal.md).
  Also useful in a server rack, garage, root cellar, or 3D-printer enclosure.
- **Channels:** up to **8**, each set by **DIP switches 1–3** inside the battery door (not by
  power-on order). Surfaced in telemetry as `temp1f`/`humidity1`, `temp2f`/`humidity2`, etc.
- **Range/accuracy:** −40 to 60 °C, ±1 °C (±0.2 °C on the STH35-probe variant); humidity
  10–99 %, ±5 %.
- **Broadcast interval:** ~every **60 seconds**.
- **Power:** 2×AA.
- **Battery flag:** reported as **`batt<ch>`** (binary 0 = normal / 1 = low) in the payload —
  *not* `wh31batt<ch>`.
- **Note:** multi-channel WN31 data uploads to ecowitt.net but is **not** accepted by Weather
  Underground.
- **Cost:** ~$11 USD / ~$15 CAD.

## WH51 — Soil Moisture Probe

- **Use:** plant/soil moisture. Capacitive (Frequency-Domain-Reflectometry) probe; IP66
  waterproof seal (survives sprinklers and rain). Working range −10 to 50 °C.
- **Channels:** up to **16** on a GW3000 (fw ≥ V1.0.2), recognized in **power-on order**.
- **Broadcast interval:** every **70 seconds** (drops to every 10 s on a significant change).
- **Power:** 1×AA, lasting **≥ 12 months**.
- **Payload fields:** `soilmoisture<ch>` (calibrated %), `soilad<ch>` (raw capacitance AD value),
  and battery **`soilbatt<ch>`** (voltage, e.g. `1.42`) — *not* `wh51batt<ch>`.
- **Calibration:** `soilmoisture = (soilad − 0%AD) × 100 / (100%AD − 0%AD)`; factory default
  `0%AD = 70`, `100%AD = 500`, tunable per soil type in the Ecowitt app. Storing raw `soilad`
  alongside the percentage lets us re-derive moisture if calibration changes later.

## Other ecosystem options

The Ecowitt/Fine-Offset ecosystem also offers soil, pool, leak, and lightning sensors, plus
the solid-state **WS90** outdoor array (haptic rain gauge, optional 12 V heater to melt ice
— no moving bucket to freeze). All route back to the same headless gateway.

## Ingestion impact

Every added sensor just adds more key-value pairs to the same HTTP POST body. Plan for it:

- Handle **unknown/absent fields gracefully** — not every POST carries every sensor.
- Model channels as columns or as a `(sensor_id, channel, metric, value)` layout depending
  on how many you expect. See [payload format](../pipeline/payload-format.md) and
  [database architecture](../pipeline/database.md).
- Wire battery flags into a low-battery alert: `batt<ch>` (WN31, 0/1 flag) and `soilbatt<ch>`
  (WH51, voltage — alert when it drops toward ~1.2 V). **Implemented:** provisioned Grafana
  alert rules in `grafana/provisioning/alerting/` cover the WS69, WN31, and WH51; set the
  `BATTERY_ALERT_WEBHOOK` env var to route them to Slack/Discord/ntfy/etc.
- Grafana surfaces the channels in a "Rooms & Soil" section on the Weather Overview dashboard
  (per-room temp/humidity + battery, soil moisture %/raw-AD + battery voltage).
