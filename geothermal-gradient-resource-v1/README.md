# geothermal-gradient-resource-v1

## Description
You will implement a Python simulation of a geothermal reservoir resource using a linear geothermal gradient and Darcy radial flow productivity index. The model computes bottomhole temperature from surface temperature plus gradient times depth, and steady-state flow rate via PI times drawdown using radial Darcy law with skin factor.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | _not yet run_ |
| Avocado | _not yet run_ |
| GPT-5.5 | TBD |
| Codex | TBD |
| Sonnet 4.6 | TBD |


## Model Analysis

Oracle achieves 100% pass rate validating reference implementation correctness across five scenarios: baseline constant drawdown, drawdown ramp list, high skin damage, deep high-gradient, and low permeability tight reservoir. Expected difficulty medium targeting 2-3/5 calibration band. Successful solutions demonstrate correct linear geothermal gradient T_bh = T_surface + gradient*depth/1000 with meters-to-km conversion, Darcy PI = 2*pi*k*h/(mu*(ln(re/rw)+skin)) using natural log not log10, flow = PI*drawdown per step handling scalar or list drawdown, and correct output keys T_bottomhole list length n_steps+1, PI float, flow_vs_drawdown list, peak_T float. Failures typically omit ln term, mis-scale depth by 1000, use log10 instead of natural log, ignore skin in denominator, mishandle list vs scalar drawdown, or return wrong list lengths.

## Anti-Cheating Analysis

Contamination risk assessed as LOW-MEDIUM; geothermal gradient formula and Darcy PI are textbook but specific simulate() interface with pinned constants and trajectory API shape is novel composition. No public benchmark matches bespoke interface.

- **Hardcoded outputs**: Tests use continuous physical parameters across five scenarios with tight 5% rel tolerance 0.5 abs; precomputed answers cannot match without implementing full model.
- **Overfitting to visible tests**: Test inputs parameterized across baseline, ramp, high-skin, deep, low-perm covering edge cases of list drawdown, skin factor, depth scaling, permeability extremes.
- **Modifying test files**: Tests mounted read-only at /tests/; test.sh applies chmod 700 defense during pytest to mitigate in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories not just final values; stdlib-only check enhanced to detect dynamic imports via __import__ to prevent numpy bypass. Test returns failure if agent file not found rather than passing vacuously.
- **Spec alignment**: Instruction explicitly pins T_bh formula, PI formula with natural log, flow linear model, Index-0 convention, output keys exact set, stdlib only math, deterministic.

<!-- v1.0 passing validation with oracle 3/3 as of 2026-07-05 -->
