# thermostat-heatpump

## Description
A Python numerical-modeling task. The agent implements `simulate(...)` in
`/app/hvac_sim.py`: one day of a single-zone (1R1C) building heated by a
**deadband/hysteresis thermostat** driving an **air-source heat pump** whose COP
varies with outdoor temperature, with a heat-pump **capacity limit** and **backup
resistance heat** below the balance point. It returns total electrical energy
(`energy_kwh`), comfort violations (`comfort_degree_hours`, degree-hours outside
the deadband), and the indoor-temperature trajectory.

The hard part is assembling several coupled pieces correctly:
- an exact analytic ODE update (forward Euler is unstable at the given `dt`),
- an ON/OFF hysteresis state machine that cycles without chattering,
- COP linear interpolation from a curve (with endpoint clamping),
- a capacity-limit + backup-heat rule (deficit below the balance point, COP=1,
  capped at `backup_capacity`), and
- correct energy (kWh) and comfort (degree-hours) accounting with unit handling.

A naive scaffold won't pass: dropping hysteresis, using a fixed COP, or ignoring
the backup-heat logic each produce wrong numbers on at least one scenario.

## Grading
`tests/test_outputs.py` imports the agent's `/app/hvac_sim.py` by path and compares
its outputs against an **independent** reference re-implemented in the test, over
three scenarios:
- **mild day** — heat pump only, thermostat cycles within the deadband;
- **cold day** — outdoor temperature below the balance point, backup heat required;
- **variable day** — sinusoidal outdoor profile + per-step internal-gain list,
  exercising COP interpolation and partial backup.

Plus a contract check (keys, `indoor_temp` length `n_steps+1`, `indoor_temp[0] ==
t_initial`) and a scalar-vs-list input-equivalence check. The verifier writes
`/logs/verifier/reward.txt` (`1` if all tests pass, else `0`).

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 1.0 (verified locally via the Docker oracle flow) |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

Oracle verified locally: the reference `solve.sh` + `tests/test.sh` flow in a
clean `python:3.12-slim` container yields `FINAL_REWARD=1`. A naive variant
(fixed COP, no backup heat) fails: on the cold day its comfort violation is ~92
degree-hours vs the reference ~1, and on the mild/variable days its energy is off
by >5%.

## Anti-Cheating Analysis
- **Hardcoded outputs:** outputs depend on continuous physical inputs across three
  distinct scenarios (including a varying outdoor profile and internal-gain list);
  there is no small constant to memorize.
- **Overfitting to visible tests:** the grader runs out-of-process and is not in
  `/app`; the agent never sees it during the solve.
- **Modifying test files:** the agent only writes `/app/hvac_sim.py`; tests live in
  `/tests` and are not editable.
- **Bypassing the intended solution:** the reference is recomputed independently in
  the test, so matching requires implementing the specified model (hysteresis +
  COP interpolation + capacity-limit/backup + exact integration + correct
  accounting); partial implementations fail.
