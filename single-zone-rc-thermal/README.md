# single-zone-rc-thermal

## Description
Implement a single-zone **lumped-capacitance (1R1C)** building thermal model
**with a nonlinear radiative loss term** in `/app/rc_model.py`. Given an
outdoor-temperature profile, internal heat gains, an HVAC input — each a scalar
or a per-step array — and a radiative coefficient `k_rad`, the agent must
integrate the **nonlinear** first-order ODE

```
C * dT_in/dt = (T_out - T_in) / R
               + Q_internal + Q_hvac
               - k_rad * ( (T_in + 273.15)^4 - (T_out + 273.15)^4 )
```

over `n_steps` of size `dt` and return the indoor-temperature trajectory
(`list[float]` of length `n_steps + 1`, index 0 = `t_initial`). The function
signature is:

```python
simulate(t_out, q_internal, q_hvac, R, C, t_initial, dt, n_steps, k_rad)
```

The quartic radiative term uses **absolute (Kelvin)** temperature
(`degC + 273.15`), so the ODE is **nonlinear and has no closed-form
solution** — the linear model's exponential update
(`T = Teq + (T0-Teq)·exp(-dt/tau)`) no longer applies.

The intended trap is **twofold**:

1. **No analytic shortcut.** Because of the `T_in^4` term there is no exact
   exponential update; the agent must actually integrate the ODE numerically.
2. **Stiffness.** A naive single-step explicit (forward) Euler integrator is
   only conditionally stable: when `dt` is several times the system's effective
   time constant it overshoots, oscillates, and diverges. A correct solution
   must use a stable **and** accurate, self-designed scheme — e.g. classic RK4
   advanced with enough internal sub-steps, or implicit Euler with Newton
   iteration. No discretization recipe is prescribed; choosing one is the core
   of the task. The verifier includes a stiff large-`dt` scenario
   (`dt/tau = 2.5`, effective ratio larger still) where a single forward-Euler
   step per `dt` diverges while the oracle stays correct, so a naive
   implementation fails at least one test.

## Verifier scenarios
The grader computes golden trajectories **independently** with a high-accuracy,
pure-Python RK4 reference (very fine sub-steps) and never imports the agent's
code to produce expected values:

1. **Free-floating nonlinear decay** — `Q = 0`, constant `T_out`, small
   `dt/tau`; match the RK4 reference within 0.05 °C every step.
2. **Constant heating equilibrium** — constant gains; approach the *nonlinear*
   steady state (computed by Newton, strictly below the linear-only `Teq`);
   match the reference within 0.05 °C every step.
3. **Stiff / large-dt** — `dt/tau = 2.5`; forward Euler diverges, stable
   schemes track the decay; tolerance 0.1 °C plus a monotonic-decay check.
4. **Time-varying outdoor** — diurnal sinusoid supplied as per-step arrays;
   tolerance 0.2 °C (catches scalar-only implementations).

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 4/4 local + Docker oracle FINAL_REWARD=1 (pending Codimango run) |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

Oracle validated via the real Docker oracle flow (`solve.sh` + `test.sh` in
`python:3.12-slim`) → `FINAL_REWARD=1` (4 passed). A naive single-step
forward-Euler implementation was confirmed to **fail** (the stiff large-`dt`
scenario) → `FINAL_REWARD=0`, establishing the fail-signal.

## Model Analysis
TBD — from Codimango model runs.

## Anti-Cheating Analysis
- **Black-box ODE solvers forbidden.** `test_no_scipy_ode_solver` reads
  `/app/rc_model.py` source and asserts it does not reference
  `scipy.integrate`, `solve_ivp`, `odeint`, or import scipy. The integrator
  must be hand-rolled.
- **No analytic shortcut.** The nonlinear radiative term removes the
  closed-form exponential update, so a memorized linear solution produces wrong
  trajectories and fails the per-step tolerances.
- **Hardcoded outputs.** Expected values are computed independently in the test
  from a high-accuracy RK4 reference across four different parameter sets
  (varying `R`, `C`, `dt`, `n_steps`, `k_rad`, scalar vs. array inputs), so
  constants pinned to one scenario cannot satisfy the others.
- **Overfitting to visible tests.** The grader lives in `/tests` and is not
  present in `/app` during the solve; the agent never sees it.
- **Modifying test files.** The agent only writes its module under `/app`;
  tests live in `/tests` and are not editable.
- **Bypassing the intended solution.** Correctness requires a numerically
  stable *and* accurate discretization of a nonlinear ODE; the stiff
  `dt/tau = 2.5` scenario makes naive forward Euler diverge and fail, so a
  partial/naive solution does not pass.
