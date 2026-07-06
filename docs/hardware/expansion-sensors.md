# Expansion Sensors

One GW3000 gateway can read dozens of multi-channel Ecowitt sensors simultaneously, so the
database can grow over time without changing the base hardware. The two near-term additions
are the WN31 (indoor rooms) and WH51 (plants/soil).

## WN31 — Multi-channel Temp/Humidity (indoor)

- **Use:** per-room indoor climate — feeds the [indoor thermal model](../ml/indoor-thermal.md).
  Also useful in a server rack, garage, root cellar, or 3D-printer enclosure.
- **Channels:** multi-channel — each sensor is assigned a channel (1..8), surfaced in
  telemetry as `temp1f`/`humidity1`, `temp2f`/`humidity2`, etc.
- **Broadcast interval:** every **61 seconds** (deep-sleeps 60 of every 61 s).
- **Power:** 2×AA, lasting **1.5–2 years** thanks to the deep-sleep duty cycle.
- **Battery flag:** reported as `wh31batt<ch>` (binary normal/low) in the payload.
- **Cost:** ~$11 USD / ~$15 CAD.

## WH51 — Soil Moisture Probe

- **Use:** plant/soil moisture. IP66 waterproof seal (survives sprinklers and rain).
- **Broadcast interval:** every **70 seconds**.
- **Power:** 1×AA, lasting **~1–1.5 years**.
- **Battery flag:** reported as `wh51batt<ch>` (voltage, e.g. `1.42`) in the payload.

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
- Wire battery flags (`wh31batt*`, `wh51batt*`) into a low-battery alert.
