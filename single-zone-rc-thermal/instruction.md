# Single-Zone RC Building Thermal Model

Implement a single-zone **lumped-capacitance (1R1C)** building thermal model
with a **hand-rolled numerical integrator**, and write it to
`/app/rc_model.py`.

## The physics

A single thermal zone is modeled as one capacitance `C` (the building's
thermal mass) connected through one resistance `R` to the outdoor air. The
indoor air temperature `T_in` evolves according to the first-order ODE:

```
C * dT_in/dt = (T_out - T_in) / R + Q_internal + Q_hvac
```

where

- `T_in`, `T_out` — indoor / outdoor temperature in **degrees Celsius**
- `R` — thermal resistance in **K/W**
- `C` — thermal capacitance in **J/K**
- `Q_internal` — internal heat gains (people, equipment) in **watts**
- `Q_hvac` — heat added (+) or removed (−) by the HVAC system in **watts**
- time `t` in **seconds**

The system time constant is `tau = R * C` (seconds).

## What to implement

Create `/app/rc_model.py` exposing exactly this function:

```python
def simulate(t_out, q_internal, q_hvac, R, C, t_initial, dt, n_steps):
    ...
```

Arguments:

- `t_out`, `q_internal`, `q_hvac` — each is **either** a scalar (the value is
  constant over the whole horizon) **or** a sequence of length `n_steps`
  giving the value held constant during step `n` (the interval from `t_n` to
  `t_{n+1}`).
- `R`, `C` — scalars as defined above.
- `t_initial` — initial indoor temperature (degC) at `t = 0`.
- `dt` — time-step size in seconds.
- `n_steps` — number of integration steps (a non-negative integer).

Return value:

- A `list[float]` of length **`n_steps + 1`**.
- Index `0` must equal `t_initial`.
- Index `k` is the indoor temperature at the end of step `k` (i.e. at time
  `k * dt`).

## Accuracy requirements

Your trajectory is graded at every step against a high-accuracy independent
reference, with per-step tolerances of 0.05–0.2 °C. Some scenarios use a time
step `dt` that is large relative to the system time constant `tau = R * C` (in
one case several times larger). Choose an integration scheme that stays
**stable and accurate** under those conditions; a scheme that is accurate only
for small `dt` will not pass.

## Constraints

- **No black-box ODE solvers.** You may not import or use
  `scipy.integrate`, `solve_ivp`, or `odeint`. The integrator must be your
  own code. (Plain Python and the standard library are fine; `numpy` is also
  fine for array handling, but the time-stepping logic must be yours.)
- Put everything in `/app/rc_model.py`; do not require a network connection
  at import time.
