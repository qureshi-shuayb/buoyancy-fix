# Single-Zone RC Building Thermal Model with Nonlinear Radiative Loss

Implement a single-zone **lumped-capacitance (1R1C)** building thermal model
**with an additional nonlinear radiative loss term**, using a **hand-rolled
numerical integrator**, and write it to `/app/rc_model.py`.

## The physics

A single thermal zone is modeled as one capacitance `C` (the building's
thermal mass) connected through one resistance `R` to the outdoor air. In
addition to the linear conductive exchange, the zone loses (or gains) heat
radiatively, modeled with a Stefan–Boltzmann-style quartic term that depends
on **absolute** temperature. The indoor air temperature `T_in` evolves
according to the **nonlinear** first-order ODE:

```
C * dT_in/dt = (T_out - T_in) / R
               + Q_internal + Q_hvac
               - k_rad * ( (T_in + 273.15)^4 - (T_out + 273.15)^4 )
```

where

- `T_in`, `T_out` — indoor / outdoor temperature in **degrees Celsius**
- `R` — thermal resistance in **K/W**
- `C` — thermal capacitance in **J/K**
- `Q_internal` — internal heat gains (people, equipment) in **watts**
- `Q_hvac` — heat added (+) or removed (−) by the HVAC system in **watts**
- `k_rad` — lumped radiative coefficient (emissivity·σ·area) in **W/K⁴**
- time `t` in **seconds**

> **Kelvin matters.** The quartic radiative term uses **absolute** temperature.
> Convert Celsius to Kelvin by adding `273.15` *inside* the fourth powers, as
> written above. Using Celsius directly in the `^4` terms is wrong.

> **There is no closed form.** Because of the `T_in^4` term this ODE is
> nonlinear and has **no analytic / exponential solution**. You must integrate
> it numerically. (The familiar `T = Teq + (T0 - Teq)·exp(-dt/tau)` update from
> the purely linear model does **not** apply here and will be graded as wrong.)

## What to implement

Create `/app/rc_model.py` exposing exactly this function:

```python
def simulate(t_out, q_internal, q_hvac, R, C, t_initial, dt, n_steps, k_rad):
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
- `k_rad` — radiative coefficient (W/K⁴), a scalar.

Return value:

- A `list[float]` of length **`n_steps + 1`**.
- Index `0` must equal `t_initial`.
- Index `k` is the indoor temperature at the end of step `k` (i.e. at time
  `k * dt`).

## Accuracy requirements

Your trajectory is graded at every step against a high-accuracy independent
reference, with per-step tolerances of 0.05–0.2 °C. Some scenarios use a time
step `dt` that is **large relative to the system's effective time constant** (in
one case several times larger). Under those conditions a naive single-step
explicit (forward Euler) update overshoots, oscillates, and diverges. **You
must choose and implement an integration scheme that stays both stable and
accurate** at the supplied `dt`. How you achieve that — the scheme, any internal
sub-stepping, any iteration — is entirely up to you and is the core of the task;
no recipe is provided.

## Constraints

- **No black-box ODE solvers.** You may not import or use
  `scipy.integrate`, `solve_ivp`, or `odeint`. The integrator must be your
  own code. (Plain Python and the standard library are fine; `numpy` is also
  fine for array handling, but the time-stepping logic must be yours.)
- Put everything in `/app/rc_model.py`; do not require a network connection
  at import time.

## Difficulty

**Hard.** The combination of nonlinearity (no closed form) and stiffness
(large `dt` relative to the effective time constant) means a correct solution
requires a genuinely stable *and* accurate numerical integrator that you design
yourself.
