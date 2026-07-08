# WS69 — 7-in-1 Outdoor Sensor Array

The WS69 is the outdoor ground-truth instrument. It is a **mechanical** all-in-one array
(distinct from the solid-state WS90 "Wittboy"), broadcasting its full state vector over
915 MHz RF.

## The seven measurements

The "7-in-1" combines these sensing channels into a single molded unit:

1. **Temperature** — ambient air temperature
2. **Relative humidity**
3. **Wind speed** — cup anemometer
4. **Wind direction** — wind vane
5. **Rainfall** — mechanical tipping-bucket rain gauge
6. **Solar radiation / light** — measured in lux (feeds the ML solar-irradiance features)
7. **UV index**

Barometric pressure is measured by the **gateway** (indoors, GW3000 has a built-in
barometer), not the outdoor array — see [GW3000](gw3000-gateway.md).

> Confirmed against the [WS69 manual](../references.md#ws69-7-in-1-outdoor-sensor-array):
> temp −40 °C to 60 °C (±1 °C), humidity 1–99 %RH (±5 %), rainfall 0–9999 mm (±10 %,
> 0.3 mm resolution), RF range up to 100 m / 330 ft, reports every 16 s.

## RF broadcast interval

The WS69 samples and broadcasts its payload **every 16 seconds**, fixed in firmware. This
interval balances battery preservation against tracking volatile wind gusts. There is **no
confirmation loop** — the sensor screams its telemetry into the air and goes back to sleep.

> By contrast: the solid-state WS90 broadcasts every ~4.75–8.8 s; a WN31 room sensor every
> 61 s; a WH51 soil probe every 70 s. Broadcast cadence is per-sensor and hardcoded.

Because the RF interval is 16 s, setting the gateway's upload interval below 16 s is
redundant — it would just re-post identical edge data. This build actually uploads at **60 s**
(above the RF rate), decimating ~4:1; the only casualty is sub-minute gust detail. See
[telemetry](../pipeline/telemetry.md) and the
[gateway upload trade-off](gw3000-gateway.md#upload-interval-trade-off).

## Power topology

The WS69 uses a hybrid **Solar panel + Supercapacitor + Battery backup** design:

- **Primary:** an integrated solar panel runs the array during the day and charges an
  internal supercapacitor, which powers the unit overnight.
- **Backup:** 2×AA cells act as a failover for consecutive sunless/snow-covered days.
- **Lifespan:** 2–3+ years, since the backup cells are rarely drawn down.

### Montreal winter factor (critical)

Use **1.5 V lithium cells** (e.g. Energizer Ultimate Lithium) in the backup compartment,
**not alkaline**. Alkaline cells freeze, suffer severe voltage drop, and leak at Montreal
January temperatures (down to −25 °C). Lithium cells sustain rated output to roughly −40 °C
and keep the radio transmitting through prolonged blizzards when the solar panel is buried
in snow.

## Battery status in telemetry

The gateway forwards each sensor's battery state inside the HTTP POST payload (e.g. a
`wh31batt1` / `wh51batt1` flag or voltage). This makes low-battery alerting a simple
threshold check on an ingested field. See [payload format](../pipeline/payload-format.md).

## Installation notes

Correct data depends on correct physical setup — leveling, true-north orientation, rigid
mounting, and biological-obstruction mitigation. All of this is covered in
[Montreal rooftop deployment](../deployment/montreal-rooftop.md).
