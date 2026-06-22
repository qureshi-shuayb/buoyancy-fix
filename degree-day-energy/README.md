# degree-day-energy

## Description
A pure-Python tool that estimates a building's annual heating and cooling
**electricity** use (kWh) from a year of hourly outdoor temperatures. The agent
implements `/app/degree_days.py` with functions to parse the hourly temperature CSV
(`read_temps`), derive the balance point (`balance_point`), compute heating/cooling
degree days (`heating_degree_days` / `cooling_degree_days`), interpolate the
temperature-dependent heating COP (`cop_at`), and produce the headline annual delivered
electricity (`annual_energy_kwh`).

The difficulty is in the physics/units rather than scaffolding:
- **Derived balance point.** The balance point is **not** the setpoint. Internal and
  solar gains offset it downward: `T_balance = T_setpoint - (Q_internal + Q_solar) / UA`.
  A solution that thresholds against the raw setpoint is materially wrong.
- **Per-hour, temperature-dependent COP.** The heating COP is given as a convex
  `(temp_c, cop)` curve and must be linearly interpolated at each hour's temperature.
  Heating electricity is the hourly integral of `UA*(T_balance - T_out) / COP(T_out)`.
  The classic `degree_days * UA * 24 / 1000 / COP_avg` shortcut drifts past tolerance
  because the COP curve is convex and heating load concentrates in cold, low-COP hours.
- **Per-hour vs per-day degree days.** Degree days are accumulated by thresholding each
  *hourly* sample, then converting degree-hours → degree-days (÷24).
- **Unit reconciliation.** Loads in W over one hour give W·h directly; convert to kWh.
- **Robust input.** 8760- and 8784-row (leap) files are both valid; malformed CSV rows
  are skipped gracefully.
- **Sign convention.** Heating only accrues below the balance point, cooling only above;
  neither is ever negative (all-heating and all-cooling climates are graded).

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 1.0 (verified locally in Docker; FINAL_REWARD=1) |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

The reference oracle passes the full grader in the `python:3.12-slim` container. Two
naive implementations — one that uses the raw setpoint as the balance point, and one
that uses the degree-day × UA ÷ average-COP shortcut — both fail the tight 0.5% energy
tolerance, confirming the intended fail-signal (verified locally: FINAL_REWARD=0). Model
rates to be populated from Codimango runs.

## Model Analysis
TBD - from Codimango model runs.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values are computed in-test by an independent reference
  over deterministic synthetic climates (fixed-seed seasonal + diurnal sinusoid + noise).
  There is no fixed constant to memorize; setpoint, gains, UA, COP curve, and cooling COP
  are parametrized across cases, and both a normal-year and a leap-year-length climate
  are graded.
- **Overfitting to visible tests:** the grader lives in `/tests` and is not present in
  `/app` during the solve; the agent only writes `degree_days.py`.
- **Modifying test files:** tests are mounted read-only and separate from the agent's
  working directory.
- **Bypassing the intended solution:** correctness requires the derived balance point,
  per-hour COP interpolation and integration, the hour→day and W→kW conversions, and the
  correct division by COP. The grader additionally asserts that the raw-setpoint and
  constant-average-COP shortcuts each drift more than 4× the 0.5% tolerance away from the
  reference, so neither shortcut can pass.
