# Hardware Overview

## The kit

The base hardware is the **Ecowitt GW3002BU kit**, which bundles:

- **WS69** — a 7-in-1 outdoor sensor array (solar, wind, rain, temp, humidity)
- **GW3000** — an indoor gateway hub with a dedicated RJ45 Ethernet port and a MicroSD slot

Ecowitt sells the same array standalone (~$64 USD / ~$88 CAD) and the WS69 + Ethernet
hub combination as the GW3002 kit (~$119 USD / ~$163 CAD). When ordering direct from the
Ecowitt store, **explicitly select the North America (915 MHz) frequency** before adding
to cart — the wrong band will not talk to a NA gateway.

## Why Ecowitt

The system is designed to be *local-first*, and Ecowitt is chosen for three reasons:

1. **Native local push.** The gateway firmware has a built-in "Custom Server" option: you
   type in the NAS's local IP and port and it HTTP-POSTs raw data strings with no vendor
   cloud in the loop and no subscription/API paywall.
2. **Extensible ecosystem.** One gateway reads dozens of multi-channel sensors at once, so
   the database can grow over time — add WN31 room sensors and WH51 soil probes later
   without re-architecting.
3. **Same OEM as Ambient Weather (Fine Offset).** The hardware is proven; Ambient sensors
   even speak the same RF language and can be read by an Ecowitt gateway.

## The 915 MHz advantage

The WS69 talks to the GW3000 over the unlicensed **915 MHz sub-GHz band**, not 2.4 GHz Wi-Fi:

- The ~33 cm wavelength diffracts around obstacles and passes through roofing membranes
  (asphalt, gravel, elastomeric), wooden joists, drywall, and even a poured concrete slab.
- With only ~10–15 ft of vertical separation between the rooftop array and the 3rd-floor
  apartment gateway, the link keeps a near-maximum signal-to-noise ratio.
- Low power draw: sub-GHz radios sip current, so sensors last years on a set of cells.

## Component roles at a glance

| Device | Role | Link | Power |
|--------|------|------|-------|
| WS69   | Outdoor 7-in-1 measurement | 915 MHz RF broadcast (out) | Solar + supercap + 2×AA backup |
| GW3000 | Edge cache + uplink | 915 MHz RF (in), Ethernet HTTP POST (out) | Mains (USB) |
| WN31   | Indoor room temp/humidity (up to 8 ch, arriving) | 915 MHz RF broadcast (out) | 2×AA |
| WH51   | Soil moisture probe (up to 16 ch, installed) | 915 MHz RF broadcast (out) | 1×AA |

See:
- [WS69 sensor array](ws69-sensor-array.md)
- [GW3000 gateway](gw3000-gateway.md)
- [Expansion sensors](expansion-sensors.md)
