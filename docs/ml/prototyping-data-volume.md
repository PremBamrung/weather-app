# Prototyping & Data Volume

You do **not** need to wait for the physical station to collect data before validating the
modeling system. Build a programmatic **virtual sandbox** now using historical proxy data,
then swap in the real WS69 stream once it accumulates.

## Virtual sandbox

- **Target (y):** **McTavish Station — ID 7024745**, on the urban slope of Mount Royal.
  A good stand-in for the rooftop microclimate.
- **Data:** pull ~3 years of historical **hourly** records for McTavish and surrounding
  airports via the **Open-Meteo Historical API**.
- **Use it to** exercise the full [downscaling pipeline](outdoor-downscaling.md) — feature
  engineering, ε-residual targets, LightGBM/TFT training, backtesting — end to end before
  any hardware is mounted.

## Data-volume buckets

Slice the proxy data into structural buckets to observe model convergence and failure modes:

| Bucket | Regime | Behavior |
|--------|--------|----------|
| **N = 7–14 days** | Persistence phase | Model relies on atmospheric inertia + local pressure tendencies. Effective strictly for short-term nowcasting (+1 to +3 h). |
| **N = 30–90 days** | Seasonal bias phase | Cleanly maps diurnal soil-evaporation curves and urban heat retention for a *single* season. **Fails during transitions** — it has never seen a seasonal distribution shift (e.g. snow-albedo flipping the radiative balance). |
| **N = 365 days** | Seasonal convergence | **Minimum absolute data volume** for a robust year-round engine. Must observe a full cycle of solar angles, liquid↔solid precipitation phase transitions, and the envelope's reaction across the full +30 °C → −25 °C swing. |

## Takeaways

- Short windows only teach persistence — fine for the +1–3 h nowcast, useless across seasons.
- A single-season model looks great until the first transition, then breaks on
  distribution shift.
- Target **≥ 1 full year** of data (proxy now, real WS69 later) before trusting a
  year-round microclimate forecaster.

## Migration to live data

Once the WS69 stream in [TimescaleDB](../pipeline/database.md) covers enough span, replace
the McTavish/Open-Meteo target with the real ground truth. The feature side (HRDPS, METAR
ring, static spatial layers) stays identical — only the label source changes.
