# Montreal Rooftop Deployment

Deploying a mechanical sensor array on a Montreal rooftop imposes specific environmental
boundary conditions. Hardware placement and rigging must account for them or the data will
be wrong (or the unit will fail in winter).

## Radio propagation & placement

- **Band:** WS69 → GW3000 over 915 MHz sub-GHz (~33 cm wavelength). It diffracts around
  obstacles and passes through roofing membrane, joists, drywall, and a concrete slab.
- **Geometry:** the 3rd-floor apartment sits directly beneath the rooftop (~10–15 ft
  separation), so the link keeps near-maximum SNR.
- **Hub placement:** the GW3000 has an adjustable external antenna — mount the hub high
  (shelf near the ceiling) to optimize packet frame retention.

## Weatherproofing & rigging checklist

### Power for frozen horizons
Use **1.5 V lithium cells** (Energizer Ultimate Lithium) in the WS69 backup compartment.
Alkalines freeze, drop voltage, and leak at −25 °C; lithium keeps the transmitter firing
during multi-day blizzards when the solar panel is snow-covered.

### Non-penetrating mounting
Do **not** screw brackets into the roofing membrane (landlord rules + spring-thaw leaks).
Instead:
- U-bolt the 25–50 mm mounting pole to an existing cast-iron plumbing vent pipe, **or**
- use a non-penetrating metal sled weighted with concrete cinder blocks.

### Vibration / buffeting mitigation
The pole must be **entirely rigid**. Unobstructed rooftop gusts will wobble a loose pole,
and the internal mechanical tipping bucket will register the vibration as **"phantom rain"**
data spikes. (This is the mechanical WS69's key rooftop failure mode.)

### Leveling & orientation
- Use the built-in bubble level on top of the WS69 so it sits perfectly horizontal.
- Align the molded **N/S arrow** to true geographic North/South so the wind-direction
  vector mapping stays mathematically correct.

### Biological obstructions
- Coat the black plastic rain funnel with a thin layer of silicone spray so wet autumn
  leaves and snow don't stick.
- Fit generic anti-bird spikes around the rim to prevent nesting and debris clogging.

## Data-quality implications

| Physical issue        | Data symptom                    | Mitigation |
|-----------------------|---------------------------------|------------|
| Loose pole            | Phantom rain spikes             | Rigid mount, U-bolt / weighted sled |
| Misaligned N/S arrow  | Rotated wind-direction vectors  | Align to true north, verify with compass |
| Un-level array        | Biased rain / wind readings     | Bubble level |
| Clogged funnel        | Missed / delayed rain           | Silicone spray, bird spikes |
| Frozen alkalines      | Dropouts during blizzards       | Lithium backup cells |

Phantom-rain spikes are also a good candidate for a downstream ingestion sanity filter
(e.g. flag rain-rate jumps that don't correlate with humidity/pressure trends).
