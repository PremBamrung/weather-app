# Target 1 — Outdoor Hyper-Local Statistical Downscaling

The objective is **not** to train a global climate model. It is **statistical downscaling
and bias correction** of an existing mesoscale Numerical Weather Prediction (NWP) model:
learn the residual error between a coarse forecast and this rooftop's true measurements.

## Modeling strategy

Train a regressor to predict the **residual error delta (ε)** between the macro NWP model's
projection and the station's ground-truth labels (y):

```
ε = y_station − ŷ_HRDPS
```

- **Models:** LightGBM regressor (strong tabular baseline) or a Temporal Fusion Transformer
  (TFT) when sequence structure and quantile forecasts matter.
- **Target horizon:** hyper-local forecast at y(t+3h) (nowcasting to short-range).
- **Label:** the WS69 ground-truth stream in TimescaleDB (hourly-aggregated to match NWP).

```
        ┌──► [ HRDPS 2.5 km GRIB2 grid ] ──┐
        ├──► [ Synoptic-ring METARs ]     ─┼──► [ downscaling model ] ──► ŷ(t+3h)
        │                                  │     (LightGBM / TFT on ε)
[ NAS ] ├──► [ Static spatial layers ]   ─┘
        └──► ground truth y (WS69) ──────────► labels
```

## Exogenous NWP features — HRDPS

A cron job on the NAS pulls raw **GRIB2** files from Environment Canada's **HRDPS**
(High-Resolution Deterministic Prediction System):

- 2.5 km spatial grid over Quebec, updated **four times daily**.
- Provides the boundary atmospheric physics the downscaler corrects toward local reality.

## Static spatial features

Pull high-resolution geospatial rasters from *Données ouvertes de la Ville de Montréal* to
characterize the exact rooftop coordinate:

1. **Aerodynamic roughness length (z₀)** — from the 75 cm/pixel Canopy Digital Model (LiDAR).
   Compute obstacle frontal indices within a 1 km radius to model how macro-scale wind
   fields collapse or swirl on hitting the local rooftop grid.
2. **Sky View Factor (SVF)** — from the 1 m Digital Surface Model (MNS). Captures longwave
   radiative cooling vs. localized Urban Heat Island (UHI) retention:

   ```
   SVF = (1 / 2π) ∫₀²π ∫₀^{π/2} sin(2θ) dθ dφ
   ```

3. **Thermal-sink proximity** — Euclidean distance vectors to the St. Lawrence River, to map
   seasonal lake-breeze thermal advection cells.

## Spatiotemporal context — synoptic METAR ring

Ingest a regional ring of public aviation **METAR** data:

- **YUL** (Trudeau), **YHU** (St-Hubert), **YMX** (Mirabel).
- **48-hour lookback window** — captures regional advection travel delays up the St.
  Lawrence valley and the local terrain's thermal hysteresis.

## Feature summary

| Group          | Source                              | Role |
|----------------|-------------------------------------|------|
| NWP (X_nwp)    | HRDPS 2.5 km GRIB2                   | coarse forecast to bias-correct |
| Synoptic       | METAR ring (YUL/YHU/YMX), 48 h lag  | regional advection / hysteresis |
| Static spatial | z₀ (LiDAR), SVF (MNS), river dist.  | fixed site geometry |
| Ground truth   | WS69 → TimescaleDB                  | label y |

See [prototyping & data volume](prototyping-data-volume.md) for how to build and validate
this before the physical station has collected data.
