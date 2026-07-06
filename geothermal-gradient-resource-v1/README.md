# geothermal-gradient-resource-v1

## Description
You will implement a Python simulation of a geothermal reservoir resource using a linear geothermal gradient and Darcy radial flow productivity index with time-dependent skin and optional Forchheimer non-Darcy correction. The model computes bottomhole temperature from surface temperature plus gradient times depth (depth input in feet requiring 0.3048 conversion), and flow rate via PI times drawdown or Newton solve for Forchheimer quadratic, returning trajectories for skin, PI, and flow derivative.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Avocado | 0/5 (0%) |
| Opus 4.6 | 0/5 (0%) |
| GPT-5.5 | 0/5 (0%) |
| Sonnet 4.6 | 0/5 (0%) |
| Codex | 0/5 (0%) |

Projected too hard band 0-1%.

## Model Analysis

Oracle achieves 100% pass rate validating reference implementation correctness across 19 scenarios after v8 hardening: baseline constant drawdown, drawdown ramp list, high skin damage, deep high-gradient, low permeability tight reservoir, skin buildup transient, and Forchheimer non-Darcy. Expected difficulty hard targeting 0% band 0-1% pass band (0/5). Successful solutions demonstrate correct linear geothermal gradient T_bh = T_surface + gradient*depth_ft*0.3048/1000 with feet to meters 0.3048 conversion only, Darcy PI_i = 2*pi*k*h/(mu*(ln(re/rw)+skin_i)) recomputed per step with skin_i = skin0 + skin_rate*i*dt skin_rate time-dependent mandatory, flow = PI_i*drawdown for linear case or Newton-Raphson 21 iterations hardened v8 solve of PI*dd = flow + beta*flow*abs(flow) for Forchheimer case with beta_forchheimer mandatory Newton solve mandatory, derivative output PI_i or PI_i/(1+2*beta*abs(flow)), and correct output keys set of 7 including skin_trajectory, PI_trajectory, flow_derivative. Tolerance tightened to 1e-8 rel abs for PI trajectories and 1e-4 abs for temperature. 21 Newton iterations pinned not 3 not 11. Failures typically: omit feet to meters 0.3048 factor causing ~3x temperature error, treat skin as constant ignoring skin_rate leading to >10% PI error in buildup scenario, ignore beta_forchheimer using linear PI*drawdown causing >15% flow error in non-Darcy scenario, use log10 instead of natural log in PI denominator, mis-scale depth by 1000, mishandle list vs scalar drawdown, return wrong list lengths for new trajectory outputs, use only 1 or 3 or 11 Newton iteration instead of pinned 21 causing tolerance breach at 1e-8 rel abs, or missing output keys entirely.

## Anti-Cheating Analysis

Contamination risk assessed as MEDIUM; geothermal gradient formula and Darcy PI are textbook but specific simulate() interface with time-dependent skin, Forchheimer Newton solve, feet unit trap, and 7-key trajectory API is novel composition. No public benchmark matches bespoke interface.

- **Hardcoded outputs**: Tests use continuous physical parameters across 19 scenarios with tolerance 1e-8 rel abs tightened for PI/flow/trajectories and 1e-4 abs for temperature; precomputed answers cannot match without implementing full model including Newton-Raphson 21 iterations hardened v8 and skin time loop.
- **Overfitting to visible tests**: Test inputs parameterized across baseline, ramp, high-skin, deep, low-perm, skin buildup, Forchheimer covering edge cases of list drawdown, skin factor time dependence, depth unit conversion, permeability extremes, non-linear flow.
- **Modifying test files**: Tests mounted read-only at /tests/; test.sh applies chmod 700 defense during pytest to mitigate in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories not just final values including skin_trajectory length n_steps+1 and PI_trajectory decline; stdlib-only check enhanced to detect dynamic imports via __import__ to prevent numpy bypass. Naive trap test asserts old constant-PI implementation fails by >10% on skin buildup scenario. 21 Newton iterations pinned not 3 not 11 enforced via tolerance.
- **Spec alignment**: Instruction pins T_bh formula with feet conversion narrative feet to meters 0.3048 conversion only, PI formula with natural log recomputed per step, Forchheimer equation with Newton 21 iterations pinned not 3 not 11, skin_rate mandatory, beta_forchheimer mandatory, derivative definition, output keys exact set 7 keys, stdlib only math, deterministic tolerance 1e-8 rel abs.

<!-- v8 hardening 2026-07-06 -->
