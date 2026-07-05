# geothermal-gradient-resource-v1

## Description
You will implement a Python simulation of a geothermal reservoir resource using a linear geothermal gradient and Darcy radial flow productivity index with time-dependent skin and optional Forchheimer non-Darcy correction. The model computes bottomhole temperature from surface temperature plus gradient times depth (depth input in feet requiring 0.3048 conversion), and flow rate via PI times drawdown or Newton solve for Forchheimer quadratic, returning trajectories for skin, PI, and flow derivative.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | TBD pending cloud re-run after v4 hardening |
| Avocado | TBD pending cloud re-run after v4 hardening |
| GPT-5.5 | TBD |
| Codex | TBD |
| Sonnet 4.6 | TBD |


## Model Analysis

Oracle achieves 100% pass rate validating reference implementation correctness across eleven scenarios after v4 hardening: baseline constant drawdown, drawdown ramp list, high skin damage, deep high-gradient, low permeability tight reservoir, skin buildup transient, and Forchheimer non-Darcy. Expected difficulty medium-hard targeting 2-8% pass band (2-3/5). Successful solutions demonstrate correct linear geothermal gradient T_bh = T_surface + gradient*depth_ft*0.3048/1000 with feet-to-meters-to-km conversion, Darcy PI_i = 2*pi*k*h/(mu*(ln(re/rw)+skin_i)) recomputed per step with skin_i = skin0 + skin_rate*i*dt, flow = PI_i*drawdown for linear case or Newton 3-iteration solve of PI*dd = flow + beta*flow*abs(flow) for Forchheimer case, derivative output PI_i or PI_i/(1+2*beta*abs(flow)), and correct output keys set of 7 including skin_trajectory, PI_trajectory, flow_derivative. Failures typically: omit feet to meters 0.3048 factor causing ~3x temperature error, treat skin as constant ignoring skin_rate leading to >10% PI error in buildup scenario, ignore beta_forchheimer using linear PI*drawdown causing >15% flow error in non-Darcy scenario, use log10 instead of natural log in PI denominator, mis-scale depth by 1000, mishandle list vs scalar drawdown, return wrong list lengths for new trajectory outputs, use only 1 Newton iteration instead of pinned 3 causing tolerance breach at 1e-3, or missing output keys entirely.

## Anti-Cheating Analysis

Contamination risk assessed as MEDIUM; geothermal gradient formula and Darcy PI are textbook but specific simulate() interface with time-dependent skin, Forchheimer Newton solve, feet unit trap, and 7-key trajectory API is novel composition. No public benchmark matches bespoke interface.

- **Hardcoded outputs**: Tests use continuous physical parameters across eleven scenarios with tightened 5e-4 rel tolerance 5e-4 abs for PI/flow/trajectories; precomputed answers cannot match without implementing full model including Newton iteration and skin time loop.
- **Overfitting to visible tests**: Test inputs parameterized across baseline, ramp, high-skin, deep, low-perm, skin buildup, Forchheimer covering edge cases of list drawdown, skin factor time dependence, depth unit conversion, permeability extremes, non-linear flow.
- **Modifying test files**: Tests mounted read-only at /tests/; test.sh applies chmod 700 defense during pytest to mitigate in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories not just final values including skin_trajectory length n_steps+1 and PI_trajectory decline; stdlib-only check enhanced to detect dynamic imports via __import__ to prevent numpy bypass. Naive trap test asserts old constant-PI implementation fails by >10% on skin buildup scenario.
- **Spec alignment**: Instruction pins T_bh formula with feet conversion narrative, PI formula with natural log recomputed per step, Forchheimer equation with Newton 3 iterations pinned, derivative definition, output keys exact set, stdlib only math, deterministic.

<!-- v4 hardening to target 2-8% band with oracle 3/3 validated locally as of 2026-07-05 -->
