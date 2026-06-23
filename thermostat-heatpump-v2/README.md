# thermostat-heatpump-v2

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
| Oracle | 3/3 (validated on Codimango) |
| Sonnet 4.6 | TBD (not run) |
| Opus 4.6 (agent) | TBD (run in progress) |
| Avocado (metacode) | 4/5 |

Codimango validation status: **passing** (commit `44d1df6`) — oracle 3/3 and the
metacode tester has the required pass/fail balance (4/5).

## Model Analysis
The metacode tester (`avocado_dvsc_tester`) passed 4/5; the single failure shows
the intended trap — the interacting concerns are not composed correctly:
- **Mild in-band day:** the failing attempt returned `energy_kwh = 36.0` vs the
  reference `14.92` (~2.4×) and `comfort_degree_hours = 80.9` vs `0.61`. The round
  `36.0` plus a *rising* trajectory (`indoor_temp[1] = 20.07` instead of the
  reference `19.85`) show the compressor was run at full output every step — the
  anti-short-cycle / hysteresis state machine and part-load cycling were never
  applied, so the unit neither modulated nor rested.
- **Cold day:** `energy_kwh = 72.0` vs `63.5` — energy overcounted because the
  part-load COP penalty and defrost accounting were missing.

This is the "compose several interacting concerns" difficulty: each piece
(hysteresis, min-runtime, defrost, part-load `Cd`, backup) is individually
tractable, but getting the couplings right against a tight tolerance is where the
model slips. The oracle passes 3/3, isolating the failure to model reasoning, not
task setup.

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

## v2 Clean Redo Note
This v2 scaffold replaces v1 due to policy violation in oracle development using third-party model. Task specification and difficulty calibration preserved from v1 to maintain model failure rates (Oracle 3/3, Avocado 4/5). All test tolerances, scenarios, and anti-cheating checks identical to v1. Oracle reimplemented clean using approved models only.
