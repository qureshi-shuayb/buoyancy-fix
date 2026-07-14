# pwr-primary-loop-v2

## Description
You will implement a Python simulation of a pressurized water reactor primary coolant loop using lumped-parameter thermal-hydraulics. The loop includes reactor core heat source, steam generator heat sink, pressurizer pressure control, and reactor coolant pump with coastdown to natural circulation.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | 1/5 (20%) |
| Avocado | 4/5 (80%) |
| GPT-5.5 | 5/5 (100%) |
| Codex | 5/5 (100%) |
| Metacode | 4/5 (80%) |
| Sonnet 4.6 | _not yet run_ |


## Model Analysis

Oracle achieves 100% pass rate validating reference implementation correctness across seven distinct scenarios including steam step down, heater deadband isolate, decay 0.20, and LMTD high-ratio test added in v0.26 to address reviewer feedback on mutant discrimination. Opus achieves 1/5 (20%), Avocado 4/5 (80%), GPT-5.5 5/5 (100%), Codex 5/5 (100%), Metacode 4/5 (80%), indicating moderate difficulty passing the not-trivial >=1 solved gate with good discriminative power across model families; empirical band is slightly easy side after v0.25 softening but acceptable per reviewer calibration target. Successful solutions demonstrate correct Newton flow solve with 3 iterations, LMTD SG model with explicit max(dT,1e-3) clamp, pressurizer volume-pressure coupling with heater/spray deadband handling, and decay heat handling with both default and constant-fraction branches. Successful solutions demonstrate correct Newton flow solve with 3 iterations, LMTD SG model with explicit max(dT,1e-3) clamp, pressurizer volume-pressure coupling, and decay heat handling. Failures typically omit natural circulation head, mis-implement pressurizer volume-pressure relation, use incorrect initial flow initialization, or mis-handle LMTD edge case. The explicit Index-0 initialization conventions added in v0.11 clarify flow[0]=flow_rated, T_sg_out[0]=T_core_in0, pressure[0]=pressure_setpoint to reduce ambiguity while preserving difficulty. v0.26 redesigns three scenarios for mutant discrimination per reviewer: heater scenario uses small steam volume (1.5 m3) and tight deadband (15 kPa) so no-heater mutant produces ~500 kPa error exceeding 80 kPa tolerance; decay scenario uses small thermal mass (8t) and low steam demand so hardcoded 0.06 vs 0.20 produces ~50K error exceeding 5K tolerance; LMTD scenario uses high UA (50 MW/K) with Tin close to Tsg creating large dT ratio (~12) so arithmetic mean produces ~15K error exceeding 5K tolerance; pump trip uses NC-dominant parameters so rho=1000 vs 700 produces ~279 kg/s error exceeding 125 kg/s tolerance. v0.25 softens per-signal tolerances to 5K temperature 80kPa pressure 5% flow graded on deviation not absolute 5% to restore model calibration band while keeping discrimination, defines rho0=700 explicitly, replaces duplicate steam step with step down, hardens heater scenario to isolate deadband, uses decay 0.10 to discriminate hardcoded 0.06 branch, and pins intra-step ordering and Newton time-levels in instruction to address AI assessment spec gaps.

## Anti-Cheating Analysis

Contamination risk assessed as MEDIUM by internal decontamination table lookup returning NOT_FOUND pending pipeline evaluation; supplementary web searches find no public benchmark matching bespoke simulate() interface or pinned constants, indicating low direct leakage but general PWR thermal-hydraulics topic is well documented. Novelty risk MEDIUM due to established engineering domain but specific lumped-parameter formulation with pinned rho0=700, decay 0.06 constant, Newton 3 iterations, and linear pressurizer heater/spray rates is novel composition.

- **Hardcoded outputs**: Tests use continuous physical parameters across seven transient scenarios including heater/spray, decay, LMTD, and NC rho discrimination with tight per-signal tolerances 5K temperature 80kPa pressure 5% flow; precomputed answers cannot match without implementing full model. Mutant verification confirms no-heater, hardcoded-decay, AM-LMTD, and wrong-rho mutants fail.
- **Overfitting to visible tests**: Test inputs parameterized across normal operation, pump trip with NC-dominant rho check, steam demand step down, loss of feedwater, heater/spray deadband exercise, decay heat constant-fraction branch, and LMTD high-ratio scenario covering edge cases.
- **Modifying test files**: Tests mounted read-only at /tests/; test.sh applies chmod 700 defense during pytest to mitigate in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories not just final values; stdlib-only check enhanced to detect dynamic imports via __import__ and importlib to prevent numpy bypass. Test returns failure if agent file not found rather than passing vacuously.
- **Spec alignment**: v0.11 aligns implementation with instruction literal: pump curve uses literal (1-(m/flow_rated)^2) without undocumented clamp, Newton derivative matches spec without hidden regularizer, pressurizer volume evolves without undocumented clamp, LMTD uses explicit max(dT,1e-3) form now specified in instruction, Index-0 initialization conventions now explicit in instruction.

<!-- v0.26 passing validation with redesigned discriminative scenarios per reviewer mutant verification as of 2026-07-14: Oracle 3/3, Opus1/5 Avocado4/5 GPT5/5 Codex5/5 Metacode4/5 ; mutants verified failing: no-heater ~500kPa err, hardcoded-decay ~50K err, AM-LMTD ~15K err, rho1000 ~279kg/s err -->
