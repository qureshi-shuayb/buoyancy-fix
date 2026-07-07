# geothermal-gradient-resource-v1

## Description
Implement Python geothermal reservoir simulator coupling linear gradient with Darcy PI, time-dependent skin, Forchheimer correction hardened v11. Model computes bottomhole temperature via surface plus gradient times depth ft to m 0.3048 conversion, flow via PI drawdown or Newton 31 iterations, returning trajectories. seconds_per_year defined for completeness not used.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Avocado | 0/5 (0%) |
| Opus 4.6 | 0/5 (0%) |
| GPT-5.5 | 0/5 (0%) |
| Sonnet 4.6 | 0/5 (0%) |
| Codex | 0/5 (0%) |

Projected 0/5.

## Model Analysis

Oracle achieves 100% pass rate validating reference implementation correctness across 19 scenarios after v11 hardening: baseline constant drawdown, drawdown ramp list, high skin damage, deep high-gradient, low permeability tight reservoir, skin buildup transient, Forchheimer non-Darcy, shallow low gradient, extreme beta, ultra deep hot, shallow extreme skin, ultra shallow negative skin, super deep high mu, mega perm anomaly, negative skin rate healing, extreme Forchheimer high, hyper hot deep, oscillating skin with sin drawdown 400 steps, ultra low perm. Expected difficulty hard Oracle 3/3 projected 0/5. Successful solutions demonstrate correct linear geothermal gradient T_bh = T_surface + gradient*depth_ft*0.3048/1000 with feet to meters 0.3048 conversion only, seconds_per_year defined for completeness, Darcy PI_i = 2*pi*k*h/(mu*(ln(re/rw)+skin_i)) recomputed per step with skin_i = skin0 + skin_rate*i*dt skin_rate mandatory no default, flow = PI_i*drawdown for linear case or Newton-Raphson 31 iterations hardened v11 solve of PI*dd = flow + beta*flow*abs(flow) for Forchheimer case with beta_forchheimer mandatory no default, derivative output PI_i or PI_i/(1+2*beta*abs(flow)), and correct output keys set of 7 including skin_trajectory, PI_trajectory, flow_derivative. Tolerance tightened to 5e-10 rel abs for PI trajectories and 5e-5 abs for temperature. 31 Newton iterations pinned not 21 not 11. Failures typically: omit feet to meters 0.3048 factor causing ~3x temperature error, treat skin as constant ignoring skin_rate leading to >10% PI error in buildup scenario, ignore beta_forchheimer using linear PI*drawdown causing >15% flow error in non-Darcy scenario, use log10 instead of natural log in PI denominator, mis-scale depth by 1000, mishandle list vs scalar drawdown, return wrong list lengths for trajectory outputs, use only 1 or 3 or 11 or 21 Newton iteration instead of pinned 31 causing tolerance breach at 5e-10 rel abs, or missing output keys entirely.

## Anti-Cheating Analysis

Contamination risk assessed as MEDIUM; geothermal gradient formula and Darcy PI are textbook but specific simulate() interface with time-dependent skin, Forchheimer Newton solve 31 iterations, feet unit trap, seconds_per_year constant, and 7-key trajectory API is novel composition. No public benchmark matches bespoke interface.

- **Hardcoded outputs**: Tests use continuous physical parameters across 19 scenarios with tolerance 5e-10 rel abs tightened for PI/flow/trajectories and 5e-5 abs for temperature; precomputed answers cannot match without implementing full model including Newton-Raphson 31 iterations hardened v11 and skin time loop.
- **Overfitting to visible tests**: Test inputs parameterized across baseline, ramp, high-skin, deep, low-perm, skin buildup, Forchheimer covering edge cases of list drawdown, skin factor time dependence, depth unit conversion, permeability extremes, non-linear flow.
- **Modifying test files**: Tests mounted read-only at /tests/; test.sh applies chmod 700 defense during pytest to mitigate in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories not just final values including skin_trajectory length n_steps+1 and PI_trajectory decline; stdlib-only check enhanced to detect dynamic imports via __import__ to prevent numpy bypass. Naive trap test asserts old constant-PI implementation fails by >10% on skin buildup scenario. 31 Newton iterations pinned not 21 not 11 enforced via tolerance. seconds_per_year defined for completeness behavioral test.
- **Spec alignment**: Instruction pins T_bh formula with feet conversion narrative feet to meters 0.3048 conversion only, seconds_per_year defined for completeness, PI formula with natural log recomputed per step, Forchheimer equation with Newton 31 iterations pinned not 21 not 11, skin_rate mandatory no default, beta_forchheimer mandatory no default, derivative definition, output keys exact set 7 keys, stdlib only math, deterministic tolerance 5e-10 rel abs.

<!-- v11 hardening 2026-07-07 -->
