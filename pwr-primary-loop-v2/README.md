# pwr-primary-loop-v2

## Description
You will implement a Python simulation of a pressurized water reactor primary coolant loop using lumped-parameter thermal-hydraulics. The loop includes reactor core heat source, steam generator heat sink, pressurizer pressure control, and reactor coolant pump with coastdown to natural circulation.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | 1/5 (20%) |
| Avocado | 0/5 (0%) |
| GPT-5.5 | 0/5 (0%) |
| Codex | 0/5 (0%) |
| Metacode | 0/5 (0%) |
| Sonnet 4.6 | _not yet run_ |


## Model Analysis

Oracle achieves 100% pass rate validating reference implementation correctness across eight scenarios (normal, pump_trip NC-dominant, steam_step_down, loss_feed, heater deadband, decay 0.20, decay_default, LMTD high-ratio) added in v0.26 to address mutant discrimination. Opus 1/5 (20%), Avocado 0/5, GPT-5.5 0/5, Codex 0/5, Metacode 0/5 indicates moderate difficulty passing the >=1 solved gate with good discriminative power; empirical band acceptable per calibration target with Opus as sole passer. Successful solutions demonstrate correct Newton flow solve with 3 iterations using previous-step temps for NC head to obtain m_dot_k, LMTD SG model with explicit max(dT,1e-3) clamp on both dT1 and dT2 before subtraction and log, pressurizer volume-pressure coupling with heater/spray deadband, and decay heat handling with both default 0.06 and constant-fraction branch. Failures typically omit NC head, mis-implement pressurizer volume-pressure relation, use incorrect initial flow, or mis-handle LMTD edge case. Index-0 conventions clarify flow[0]=flow_rated, T_sg_out[0]=T_core_in0, pressure[0]=pressure_setpoint. v0.26 redesigns three scenarios for mutant discrimination: heater uses small steam volume (1.5 m3) and tight deadband (15 kPa) so no-heater produces ~500 kPa error >80 kPa; decay uses small thermal mass (8t) and low steam demand so hardcoded 0.06 vs 0.20 produces ~50K error >5K; LMTD uses high UA (50 MW/K) with Tin close to Tsg creating dT ratio ~12 so arithmetic mean produces ~15K error >5K; pump_trip uses NC-dominant params so rho=1000 vs 700 produces ~279 kg/s error >125 kg/s. v0.27 aligns instruction.md to grader: LMTD clamp specified on both numerator differences before subtraction and log, intra-step ordering pinned as flow (Newton 3) -> core outlet using m_dot_k -> SG LMTD using Tco_next, loop momentum derivative pinned df/dm = -2*C*m/flow_rated^2 -2*K_loop*abs(m), validate.py synced to 8 scenarios. v0.27.4 fixes GT gold-patch failure: previous chmod 700 + runuser made /tests unreadable to agent during verifier causing gt_resolved=0; now tests kept 755 readable and harbor-mount provides primary anti-cheat.

## Anti-Cheating Analysis

Contamination risk assessed as LOW by reviewer agreement with decontamination table NOT_FOUND; README conservatively notes MEDIUM pending pipeline but supplementary web searches find no public benchmark matching bespoke simulate() interface or pinned constants, indicating low direct leakage but general PWR thermal-hydraulics topic is well documented. Novelty risk MEDIUM due to established engineering domain but specific lumped-parameter formulation with pinned rho0=700, decay 0.06 constant, Newton 3 iterations, and linear pressurizer heater/spray rates is novel composition.

- **Hardcoded outputs**: Tests use continuous physical parameters across eight transient scenarios including heater/spray, decay, LMTD, and NC rho discrimination with tight per-signal tolerances 5K temperature 80kPa pressure 5% flow; precomputed answers cannot match without implementing full model. Mutant verification confirms no-heater, hardcoded-decay, AM-LMTD, and wrong-rho mutants fail.
- **Overfitting to visible tests**: Test inputs parameterized across normal operation, pump trip with NC-dominant rho check, steam demand step down, loss of feedwater, heater/spray deadband exercise, decay heat constant-fraction branch, and LMTD high-ratio scenario covering edge cases.
- **Modifying test files**: T-Bench infra harbor-mounts /tests only at verifier time, not during agent solve phase (per thermostat-heatpump-v2 precedent). Primary defense is that agent cannot read /tests during solve. Secondary defense is AST stdlib-only check. Previous chmod 700 + runuser attempt broke GT because agent could not read tests during verifier; v0.27.4 fixes to keep tests readable at verifier and rely on harbor-mount.
- **Bypassing intended solution path**: Tests verify full trajectories not just final values; stdlib-only check enhanced to detect dynamic imports via __import__ and importlib, and to ban open exec eval compile subprocess os.system io.open pathlib read os.open to prevent oracle read bypass. Test returns failure if agent file not found rather than passing vacuously.
- **Spec alignment**: v0.27 aligns implementation with instruction literal: pump curve uses literal (1-(m/flow_rated)^2) without undocumented clamp, Newton derivative matches spec without hidden regularizer, pressurizer volume evolves without undocumented clamp, LMTD uses explicit max(dT,1e-3) clamp on both dT1 and dT2 before subtraction and before log now specified in instruction, intra-step ordering clarified to solve flow then update temperatures, Index-0 initialization conventions explicit.

<!-- v0.27.4 passing validation with spec-grader alignment per reviewer: Oracle 3/3, Opus1/5 Avocado0/5 Codex0/5 Metacode0/5 GPT5.5 0/5 ; mutants verified failing: no-heater ~500kPa err, hardcoded-decay ~50K err, AM-LMTD ~15K err, rho1000 ~279kg/s err ; GT fixed: harbor-mount readable -->
