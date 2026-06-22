# degree-day-energy

## Description
A pure-Python tool that estimates a building's annual heating and cooling energy use
with the classic **degree-day** method. The agent implements `/app/degree_days.py` with
four functions: parse a year of hourly outdoor temperatures from CSV (`read_temps`),
compute heating and cooling degree days against a configurable balance-point temperature
(`heating_degree_days` / `cooling_degree_days`), and estimate annual delivered heating
and cooling energy in kWh from the building UA value and equipment efficiencies
(`annual_energy_kwh`).

The difficulty is in the physics/units rather than scaffolding:
- **Per-hour vs per-day accumulation.** Degree days must be accumulated by thresholding
  each *hourly* sample against the balance point. A naive implementation that averages
  each day to a daily mean first (the textbook ASHRAE daily-mean method) gives a
  materially different answer once temperatures cross the balance point within a day.
- **Degree-hours → degree-days conversion.** Hourly accumulation must be divided by 24
  to report °C·day.
- **UA thermal-energy formula.** Thermal energy = `UA[W/K] * DD[°C·day] * 24[h/day]`
  in Wh, then /1000 → kWh.
- **Efficiency division.** Delivered electricity = thermal load **divided by** the
  heating efficiency (AFUE/COP) or cooling COP — not multiplied.
- **Sign convention.** Heating only accrues below the balance point, cooling only above;
  neither is ever negative (all-heating and all-cooling climates are graded).

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 1.0 (verified locally in Docker; FINAL_REWARD=1) |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

The reference oracle passes the full grader in the `python:3.12-slim` container. A naive
per-day (daily-mean) degree-day implementation fails the degree-day and energy checks,
confirming the intended fail-signal. Model rates to be populated from Codimango runs.

## Model Analysis
TBD - from Codimango model runs.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values are computed in-test by an independent reference
  over deterministic synthetic climates (fixed-seed sinusoid + diurnal swing + noise);
  there is no fixed constant to memorize, and balance points / UA / efficiencies are
  parametrized.
- **Overfitting to visible tests:** the grader lives in `/tests` and is not present in
  `/app` during the solve; the agent only writes `degree_days.py`.
- **Modifying test files:** tests are mounted read-only and separate from the agent's
  working directory.
- **Bypassing the intended solution:** correctness requires per-hour accumulation, the
  hour→day and W→kW conversions, and dividing by efficiency. A per-day or
  multiply-by-efficiency implementation disagrees with the reference and fails.
