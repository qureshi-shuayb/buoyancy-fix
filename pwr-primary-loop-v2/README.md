# pwr-primary-loop-v2

## Description
You will implement a Python simulation of a pressurized water reactor primary coolant loop using lumped-parameter thermal-hydraulics. The loop includes reactor core heat source, steam generator heat sink, pressurizer pressure control, and reactor coolant pump with coastdown to natural circulation.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | 2/5 (40%) |
| Avocado | 0/5 (0%) |
| GPT-5.5 | 5/5 (100%) |
| Codex | 5/5 (100%) |
| Sonnet 4.6 | _not yet run_ |


## Model Analysis

Oracle achieves 100% pass rate validating reference implementation correctness across four scenarios plus two new heater/spray and decay scenarios added in v0.21 to address untested branches. Opus achieves 2/5 (40%), Avocado 0/5 (0%), GPT-5.5 5/5 (100%), Codex 5/5 (100%), indicating moderate difficulty with good discriminative power across model families targeting ideal 2-3/5 calibration band average. Successful solutions demonstrate correct Newton flow solve with 3 iterations, LMTD SG model with explicit max(dT,1e-3) clamp, pressurizer volume-pressure coupling with heater/spray deadband handling, and decay heat handling with both default and constant-fraction branches. Successful solutions demonstrate correct Newton flow solve with 3 iterations, LMTD SG model with explicit max(dT,1e-3) clamp, pressurizer volume-pressure coupling, and decay heat handling. Failures typically omit natural circulation head, mis-implement pressurizer volume-pressure relation, use incorrect initial flow initialization, or mis-handle LMTD edge case. The explicit Index-0 initialization conventions added in v0.11 clarify flow[0]=flow_rated, T_sg_out[0]=T_core_in0, pressure[0]=pressure_setpoint to reduce ambiguity while preserving difficulty.

## Anti-Cheating Analysis

Contamination risk assessed as MEDIUM by internal decontamination table lookup returning NOT_FOUND pending pipeline evaluation; supplementary web searches find no public benchmark matching bespoke simulate() interface or pinned constants, indicating low direct leakage but general PWR thermal-hydraulics topic is well documented. Novelty risk MEDIUM due to established engineering domain but specific lumped-parameter formulation with pinned rho0=700, decay 0.06 constant, Newton 3 iterations, and linear pressurizer heater/spray rates is novel composition.

- **Hardcoded outputs**: Tests use continuous physical parameters across six transient scenarios including heater/spray and decay branches with tight 5% tolerance; precomputed answers cannot match without implementing full model.
- **Overfitting to visible tests**: Test inputs parameterized across normal operation, pump trip, steam demand step, loss of feedwater, heater/spray deadband exercise, and decay heat constant-fraction branch covering edge cases.
- **Modifying test files**: Tests mounted read-only at /tests/; test.sh applies chmod 700 defense during pytest to mitigate in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories not just final values; stdlib-only check enhanced to detect dynamic imports via __import__ and importlib to prevent numpy bypass. Test returns failure if agent file not found rather than passing vacuously.
- **Spec alignment**: v0.11 aligns implementation with instruction literal: pump curve uses literal (1-(m/flow_rated)^2) without undocumented clamp, Newton derivative matches spec without hidden regularizer, pressurizer volume evolves without undocumented clamp, LMTD uses explicit max(dT,1e-3) form now specified in instruction, Index-0 initialization conventions now explicit in instruction.

<!-- v0.21 passing validation with perfect AI score 0 issues as of 2026-06-30 -->
