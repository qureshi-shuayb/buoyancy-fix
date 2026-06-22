# vav-airhandler-control

## Description
A Python numerical-modeling task. The agent implements `simulate(...)` in
`/app/vav_sim.py`: one day of a multi-zone **variable-air-volume (VAV)** air
handler whose energy and ventilation outcome depends on **four coupled controls**:

- an **airside economizer** — up to 100% outdoor air for free cooling when the
  outdoor dry-bulb is below a changeover high-limit, otherwise minimum outdoor
  air;
- a **supply-air-temperature (SAT) reset** — the coil-leaving setpoint resets
  linearly against outdoor temperature, changing both the coil load and every
  box's airflow;
- **VAV-box reheat with a minimum-airflow floor** — a box throttled down to its
  minimum airflow must reheat to avoid overcooling (simultaneous cooling +
  reheat); and
- **CO2 demand-controlled ventilation (DCV)** — the minimum outdoor-air fraction
  rises with occupancy and must keep zone CO2 under a limit.

Zones are held at setpoint (quasi-steady airside); the only dynamic state is a
well-mixed zone CO2 mass balance, advanced with the exact analytic update. The
function returns `fan_energy_kwh`, `cooling_coil_energy_kwh`, `reheat_energy_kwh`,
`total_energy_kwh`, the peak zone CO2 `co2_ppm_max` (ventilation adequacy), a
`co2_within_limit` flag, and the `supply_airflow_kgps` trajectory.

The hard part is composing the **couplings** correctly, because each control
feeds the energy/ventilation accounting through the others:
- the economizer ⇄ mechanical-cooling handoff (free cooling drives the coil load
  to zero, otherwise the coil runs on minimum outdoor air);
- the minimum-airflow floor forcing **simultaneous cooling + reheat**;
- **DCV raising the minimum outdoor-air fraction**, which changes the economizer
  math, the mixed-air temperature, and the coil load (and can exceed the
  economizer's free-cooling target on a cold, densely-occupied day);
- the **SAT reset changing box airflow** — and therefore fan power through the
  cube affinity law and reheat through the minimum-airflow floor.

A naive scaffold won't pass: fixed minimum outdoor air (no economizer, no DCV), a
fixed SAT, or no minimum-airflow reheat each produce wrong airflow and energy on
at least one scenario, well past the tight tolerances.

## Grading
`tests/test_outputs.py` imports the agent's `/app/vav_sim.py` by path and compares
its outputs against an **independent** reference re-implemented in the test, over
four scenarios:
- **mild shoulder day** — outdoor temp below the economizer high-limit all day, so
  the economizer runs, DCV sets the outdoor-air floor, and low-load zones sit at
  minimum airflow and reheat (economizer + DCV + min-airflow reheat together);
- **hot day** — outdoor temp above the high-limit, economizer locked out, coil on
  minimum (DCV) outdoor air, with one low-load zone reheating while the coil cools
  (simultaneous mechanical cooling + reheat);
- **cold densely-occupied day** — the economizer wants partial outdoor air for
  free cooling, but high occupancy makes the DCV minimum outdoor-air fraction
  larger than the economizer target, so DCV governs (coil off, heavy reheat);
- **variable day** — sinusoidal outdoor profile + office occupancy schedule +
  occupancy/temperature-tracking loads, crossing the economizer high-limit and
  exercising the full SAT-reset range.

Plus a contract check (keys, `supply_airflow_kgps` length `n_steps`), a
scalar-vs-list input-equivalence check, and a source scan that bans `scipy` /
black-box ODE solvers (the analytic CO2 update is mandatory). The verifier
installs `pytest` with the image's `pip` (the `python:3.12-slim` image has no
`curl`/`uv`) and writes `/logs/verifier/reward.txt` (`1` if all tests pass, else
`0`).

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | TBD (Docker-validated locally: 6/6, FINAL_REWARD=1) |
| Sonnet 4.6 | TBD (not run) |
| Opus 4.6 (agent) | TBD (not run) |
| Avocado (metacode) | TBD (not run) |

Local validation status: oracle **FINAL_REWARD=1** (6/6) and an explicit naive
implementation (fixed minimum OA, no economizer, fixed SAT, no min-airflow
reheat) **FINAL_REWARD=0** (4/6 scenarios fail).

## Model Analysis
This is the "compose several interacting concerns" difficulty: each control
(economizer, SAT reset, min-airflow reheat, DCV) is individually tractable, but
getting the couplings right against tight tolerances is where models slip. The
validated naive implementation shows the intended trap directly — on the mild
shoulder day it returned `cooling_coil_energy_kwh ≈ 41.0` vs the reference `1.38`
(~30×) because it skipped the economizer (no free cooling) and used a fixed cold
SAT, and `reheat_energy_kwh = 0` vs `16.8` because it never applied minimum-airflow
reheat; the `supply_airflow_kgps` trajectory also diverges because the fixed SAT
changes every box's required airflow. The oracle passes all scenarios, isolating
the failure to model reasoning, not task setup.

## Anti-Cheating Analysis
- **Hardcoded outputs:** outputs depend on continuous physical inputs across four
  distinct scenarios (including varying outdoor, occupancy, and load profiles) and
  a stateful, coupled control + CO2 interaction; there is no small constant to
  memorize.
- **Overfitting to visible tests:** the grader runs out-of-process and is not in
  `/app`; the agent never sees it during the solve.
- **Modifying test files:** the agent only writes `/app/vav_sim.py`; tests live in
  `/tests` and are mounted read-only.
- **Bypassing the intended solution:** the reference is recomputed independently in
  the test, so matching requires implementing the full specified model (economizer
  free-cooling modulation + SAT reset + minimum-airflow reheat + DCV minimum
  outdoor air + mixed-air/coil accounting + fan affinity law + exact analytic CO2
  integration); partial implementations fail at least one scenario.
- **Library shortcuts:** `scipy` / external ODE integrators are disallowed by the
  spec and blocked by a source scan; the exact analytic CO2 update is mandatory,
  so numeric agreement requires the agent to implement it directly.
