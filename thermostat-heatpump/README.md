# thermostat-heatpump

## Description
A Python numerical-modeling task. The agent implements `simulate(...)` in
`/app/hvac_sim.py`: one day of a single-zone (1R1C) building heated by a
**deadband/hysteresis thermostat** driving an **air-source heat pump**, with three
interacting realism effects layered on top of the basic thermostat:

- **anti-short-cycle** minimum compressor run-time / off-time that overrides the
  bare deadband,
- periodic **defrost cycles** inside a defrost band (no useful heat delivered,
  degraded COP via `defrost_cop_factor`, backup fills the gap), and
- **part-load cycling degradation** `PLF = 1 - Cd*(1 - PLR)` applied to the
  effective COP.

A heat-pump **capacity limit** plus **backup resistance heat** (COP=1) cover any
shortfall, including the heat lost during defrost. It returns total electrical
energy (`energy_kwh`, including defrost + backup), comfort violations
(`comfort_degree_hours`, degree-hours outside the deadband), and the
indoor-temperature trajectory.

The hard part is assembling several **coupled** pieces correctly, because each one
interacts with the energy and comfort accounting:
- an exact analytic ODE update (forward Euler is unstable at the given `dt`),
- an ON/OFF hysteresis state machine **plus** a minimum run-time / off-time
  override that changes both energy and comfort versus an instantaneous thermostat,
- a defrost schedule driven by accumulated in-band compressor run-time, during
  which the heat pump delivers zero heat, draws electricity at a degraded COP, and
  forces backup heat to cover the gap,
- a part-load factor that lowers the effective COP whenever the load is below the
  heat-pump capacity,
- COP linear interpolation from a curve (with endpoint clamping), and
- a capacity-limit + backup-heat rule (deficit relative to the heat-pump heat
  *actually delivered*, COP=1, capped at `backup_capacity`),
- with careful unit handling (`dt`/`min_runtime`/`min_offtime` in seconds;
  `defrost_interval`/`defrost_duration` in minutes; energy in kWh; comfort in
  degree-hours).

A naive scaffold won't pass: an instantaneous deadband, a fixed/curve-only COP
(no `Cd`), or omitting defrost each produce wrong numbers on at least one scenario,
well past the tight tolerances.

## Grading
`tests/test_outputs.py` imports the agent's `/app/hvac_sim.py` by path and compares
its outputs against an **independent** reference re-implemented in the test, over
four scenarios:
- **mild in-band day** — heat pump cycles, part-load degradation applies, periodic
  defrost runs (backup only fills the defrost gaps);
- **cold day below the band** — outdoor temperature below the balance point and
  below the defrost band, heavy backup heat required, no defrost;
- **cold humid in-band day** — defrost cycles run, backup covers the defrost gap,
  and part-load degradation applies between defrosts, all at once;
- **variable day** — sinusoidal outdoor profile + per-step internal-gain list,
  crossing in and out of the defrost band, exercising COP interpolation,
  intermittent defrost, and partial backup.

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
(instantaneous deadband, curve-only COP with no part-load factor, no defrost, no
backup-during-defrost) yields `FINAL_REWARD=0`: it underestimates energy (it omits
both the defrost electricity and the part-load COP penalty) and understates comfort
violations (it misses the cooldowns during defrost and the overshoot/undershoot
forced by the minimum-cycle constraint).

## Anti-Cheating Analysis
- **Hardcoded outputs:** outputs depend on continuous physical inputs across four
  distinct scenarios (including a varying outdoor profile and internal-gain list)
  and a stateful control/defrost/part-load interaction; there is no small constant
  to memorize.
- **Overfitting to visible tests:** the grader runs out-of-process and is not in
  `/app`; the agent never sees it during the solve.
- **Modifying test files:** the agent only writes `/app/hvac_sim.py`; tests live in
  `/tests` and are not editable.
- **Bypassing the intended solution:** the reference is recomputed independently in
  the test, so matching requires implementing the full specified model (hysteresis
  + min-runtime/off-time override + defrost schedule + part-load factor + COP
  interpolation + capacity-limit/backup + exact integration + correct accounting);
  partial implementations fail at least one scenario.
- **Library shortcuts:** `scipy` / external ODE integrators are disallowed by the
  spec; the exact analytic update is mandatory, so the test reference uses it and
  numeric agreement requires the agent to do the same.
