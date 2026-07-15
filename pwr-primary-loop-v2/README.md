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

Oracle achieves 100% pass rate validating reference implementation correctness across seven distinct scenarios including steam step down, heater deadband isolate, decay 0.20, and LMTD high-ratio test added in v0.26 to address reviewer feedback on mutant discrimination. Opus achieves 1/5 (20%), Avocado 0/5 (0%), GPT-5.5 0/5 (0%), Codex 0/5 (0%), Metacode 0/5 (0%), indicating moderate difficulty passing the not-trivial >=1 solved gate with good discriminative power across model families; empirical band acceptable per reviewer calibration target with Opus as sole passer. Successful solutions demonstrate correct Newton flow solve with 3 iterations, LMTD SG model with explicit max(dT,1e-3) clamp on both dT1 and dT2 before subtraction, pressurizer volume-pressure coupling with heater/spray deadband handling, and decay heat handling with both default and constant-fraction branches. Failures typically omit natural circulation head, mis-implement pressurizer volume-pressure relation, use incorrect initial flow initialization, or mis-handle LMTD edge case. The explicit Index-0 initialization conventions added in v0.11 clarify flow[0]=flow_rated, T_sg_out[0]=T_core_in0, pressure[0]=pressure_setpoint to reduce ambiguity while preserving difficulty. v0.26 redesigns three scenarios for mutant discrimination per reviewer: heater scenario uses small steam volume (1.5 m3) and tight deadband (15 kPa) so no-heater mutant produces ~500 kPa error exceeding 80 kPa tolerance; decay scenario uses small thermal mass (8t) and low steam demand so hardcoded 0.06 vs 0.20 produces ~50K error exceeding 5K tolerance; LMTD scenario uses high UA (50 MW/K) with Tin close to Tsg creating large dT ratio (~12) so arithmetic mean produces ~15K error exceeding 5K tolerance; pump trip uses NC-dominant parameters so rho=1000 vs 700 produces ~279 kg/s error exceeding 125 kg/s tolerance. v0.27 aligns instruction.md to grader: LMTD clamp specified on both numerator differences before subtraction, intra-step ordering clarified to solve flow first then update core outlet using current m_dot_k, validate.py synced to 8 scenarios matching grader. v0.25 softens per-signal tolerances to 5K temperature 80kPa pressure 5% flow graded on deviation not absolute 5% to restore model calibration.

## Anti-Cheating Analysis

Contamination risk assessed as LOW by reviewer agreement with decontamination table NOT_FOUND; README conservatively notes MEDIUM pending pipeline but supplementary web searches find no public benchmark matching bespoke simulate() interface or pinned constants, indicating low direct leakage but general PWR thermal-hydraulics topic is well documented. Novelty risk MEDIUM due to established engineering domain but specific lumped-parameter formulation with pinned rho0=700, decay 0.06 constant, Newton 3 iterations, and linear pressurizer heater/spray rates is novel composition.

- **Hardcoded outputs**: Tests use continuous physical parameters across seven transient scenarios including heater/spray, decay, LMTD, and NC rho discrimination with tight per-signal tolerances 5K temperature 80kPa pressure 5% flow; precomputed answers cannot match without implementing full model. Mutant verification confirms no-heater, hardcoded-decay, AM-LMTD, and wrong-rho mutants fail.
- **Overfitting to visible tests**: Test inputs parameterized across normal operation, pump trip with NC-dominant rho check, steam demand step down, loss of feedwater, heater/spray deadband exercise, decay heat constant-fraction branch, and LMTD high-ratio scenario covering edge cases.
- **Modifying test files**: T-Bench infra harbor-mounts /tests only at verifier time, not during agent solve phase (per thermostat-heatpump-v2 precedent). Primary defense is that agent cannot read /tests during solve. Secondary defense is AST stdlib-only check. Previous chmod 700 + runuser attempt broke GT because agent could not read tests during verifier; v0.27.4 fixes to keep tests readable at verifier and rely on harbor-mount.
- **Bypassing intended solution path**: Tests verify full trajectories not just final values; stdlib-only check enhanced to detect dynamic imports via __import__ and importlib, and to ban open exec eval compile subprocess os.system io.open pathlib read os.open to prevent oracle read bypass. Test returns failure if agent file not found rather than passing vacuously.
- **Spec alignment**: v0.27 aligns implementation with instruction literal: pump curve uses literal (1-(m/flow_rated)^2) without undocumented clamp, Newton derivative matches spec without hidden regularizer, pressurizer volume evolves without undocumented clamp, LMTD uses explicit max(dT,1e-3) clamp on both dT1 and dT2 before subtraction now specified in instruction, intra-step ordering clarified to solve flow then update temperatures, Index-0 initialization conventions explicit.

<!-- v0.27 passing validation with spec-grader alignment per reviewer: Oracle 3/3, Opus1/5 Avocado0/5 Codex0/5 Metacode0/5 GPT5.5 0/5 ; mutants verified failing: no-heater ~500kPa err, hardcoded-decay ~50K err, AM-LMTD ~15K err, rho1000 ~279kg/s err ; spec-faithful variants pass -->
