# Target 2 — Indoor Climate Modeling (Grey-Box / PINN)

By adding cheap [WN31 multi-channel sensors](../hardware/expansion-sensors.md), each room
can be modeled as a **lumped-element thermal network** — the building envelope treated as an
RC circuit with thermal resistance (R) and thermal capacitance (C).

## Grey-box RC model

Each room is a node with capacitance C, coupled to outdoors (and adjacent rooms) through
resistances R. The state evolves by Newton's law of cooling plus HVAC forcing:

```
C · dT_in/dt = (T_out − T_in)/R + Q_hvac + Q_solar
```

The unknowns are the envelope parameters (the R's and C's) that describe the apartment's
thermal inertia.

## Physics-Informed Neural Network (PINN)

Constrain a lightweight LSTM or MLP by embedding the convective heat equation / Newton's law
of cooling directly into the loss:

```
L = L_data + λ · L_physics
```

- `L_data` — fit to measured indoor temperatures.
- `L_physics` — penalize violations of the heat-balance ODE above.
- The network optimizes for the **hidden envelope parameters** and predicts the structural
  **phase lag (thermal inertia)** during sharp winter temperature swings.

```
[ outdoor ambient (WS69) ]──┐
[ solar irradiance / lux  ]──┤
[ indoor WN31 per room    ]──┼──► [ grey-box PINN ] ──► room T(t+Δ), envelope R/C, phase lag
[ thermostat HVAC duty    ]──┘
```

## System inputs

| Input                          | Source |
|--------------------------------|--------|
| Outdoor ambient temp/humidity  | WS69 (outdoor array) |
| Solar irradiance (lux)         | WS69 light sensor |
| Per-room temp/humidity         | WN31 channels (indoor) |
| HVAC heating/cooling duty cycle| smart thermostat logs |

## Output & value

- Predict how each room lags outdoor swings (thermal hysteresis of the envelope).
- Recover interpretable R/C parameters for the apartment — useful for HVAC scheduling and
  understanding cold-snap response.

This target depends on first deploying WN31 sensors and capturing thermostat duty-cycle
logs; it can be prototyped against synthetic RC data before hardware arrives.
