# single-zone-rc-thermal

## Description
Implement a single-zone **lumped-capacitance (1R1C)** building thermal model
in `/app/rc_model.py`. Given an outdoor-temperature profile, internal heat
gains, and an HVAC input — each a scalar or a per-step array — the agent must
integrate the first-order ODE

```
C * dT_in/dt = (T_out - T_in) / R + Q_internal + Q_hvac
```

over `n_steps` of size `dt` and return the indoor-temperature trajectory
(`list[float]` of length `n_steps + 1`, index 0 = `t_initial`).

The intended trap is **numerical stability and correct ODE discretization**.
A naive explicit (forward) Euler integrator is only conditionally stable: when
`dt` is comparable to or larger than the system time constant `tau = R * C`
it overshoots, oscillates, and diverges. A correct solution must use a stable
*and accurate* scheme — the exact analytic exponential update for
piecewise-constant inputs (recommended; exact for any `dt`), or a
finite-difference method (implicit Euler / RK4) advanced with enough internal
sub-steps to meet the per-step tolerance. The verifier includes a stiff
large-`dt` scenario (`dt/tau = 2.5`) where a single forward-Euler step per
`dt` diverges while the oracle stays correct, so a naive implementation fails
at least one test.

## Verifier scenarios
The grader computes golden trajectories **independently** (exact analytic
update) and never imports the agent's code to produce expected values:

1. **Free-floating decay** — `Q = 0`, constant `T_out`, small `dt/tau`;
   match analytic within 0.05 °C every step.
2. **Constant heating equilibrium** — constant gains, approach `T_eq`; match
   analytic within 0.05 °C every step.
3. **Stiff / large-dt** — `dt/tau = 2.5`; forward Euler diverges, stable
   schemes track the decay; tolerance 0.1 °C plus a monotonic-decay check.
4. **Time-varying outdoor** — diurnal sinusoid supplied as per-step arrays;
   tolerance 0.2 °C (catches scalar-only implementations).

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 4/4 local (pending Codimango run) |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

Oracle validated locally: `uv run --with numpy --with pytest pytest
tests/test_outputs.py` → 4 passed. A naive forward-Euler implementation was
confirmed to **fail** the stiff large-`dt` scenario locally.

## Model Analysis
TBD — from Codimango model runs.

## Anti-Cheating Analysis
- **Black-box ODE solvers forbidden.** `test_no_scipy_ode_solver` reads
  `/app/rc_model.py` source and asserts it does not reference
  `scipy.integrate`, `solve_ivp`, `odeint`, or import scipy. The integrator
  must be hand-rolled.
- **Hardcoded outputs.** Expected values are computed independently in the
  test from the analytic solution across four different parameter sets
  (varying `R`, `C`, `dt`, `n_steps`, scalar vs. array inputs), so constants
  pinned to one scenario cannot satisfy the others.
- **Overfitting to visible tests.** The grader lives in `/tests` and is not
  present in `/app` during the solve; the agent never sees it.
- **Modifying test files.** The agent only writes its module under `/app`;
  tests live in `/tests` and are not editable.
- **Bypassing the intended solution.** Correctness requires a numerically
  stable discretization; the stiff `dt/tau = 2.5` scenario makes naive
  forward Euler diverge and fail, so a partial/naive solution does not pass.
