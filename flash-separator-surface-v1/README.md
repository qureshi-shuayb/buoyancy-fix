# flash-separator-surface-v1

## Description
Implement Python isenthalpic flash separator model for geothermal surface brine using Antoine saturation pressure correlation solved via Newton-Raphson 5 iterations, two-stage cascade mass balance, Souders-Brown carryover correlation, and silica kinetic precipitation ODE. Returns final steam/brine flows, quality, brine enthalpy, scaling risk, stage-separated flows, and silica concentration time series.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4 | TBD pending cloud re-run after v4 hardening |
| Sonnet 4 | TBD |
| GPT-5 | TBD |

## Model Analysis

Oracle achieves 100% validating reference implementation across ten scenarios after v4 hardening: normal flash, subcooled no-flash, superheated limit, high silica scaling, low pressure high quality, carryover sensitivity, two-stage cascade, kinetic silica. Expected difficulty medium targeting 2-8% pass band (2-3/5). Successful solutions demonstrate correct Newton-Raphson Antoine inversion starting at 100C 5 iterations pinned not closed-form, Souders-Brown carryover = C_sb*sqrt(rho_v/(rho_l-rho_v)) with rho_v temperature dependent, two-stage cascade where stage1 brine feeds stage2 at lower pressure, silica kinetic ODE explicit Euler 1 step dC/dt = -k*(C-C_eq) over residence_time, tightened 5e-10 tolerance for quality and flows, and correct output keys set of 10 including stage1/stage2 flows and silica series. Failures typically: use old closed-form Antoine inversion instead of Newton causing slight deviation beyond 5e-10, ignore C_sb correlation using old constant carryover_frac, treat single stage only missing cascade mass balance, use equilibrium silica only ignoring kinetic ODE leading to false negative in kinetic test, mis-handle list lengths, omit stage output keys, or clamp quality incorrectly.

## Anti-Cheating Analysis

Contamination risk MEDIUM: bespoke simulate() signature with Newton Antoine, two-stage cascade, Souders-Brown, kinetic silica not matching public benchmarks. Novelty risk MEDIUM due to geothermal flash domain documented but specific pinned iterative formulas novel.

- **Hardcoded outputs**: Tests use continuous physical parameters across ten scenarios with tightened 5e-10 tolerance; precomputed table cannot match without implementing Newton iteration and cascade loop.
- **Overfitting**: Parameter sweep covers subcooled, superheated, scaling risk true/false, low pressure, high carryover, two-stage pressure split, kinetic vs equilibrium divergence.
- **Modifying test files**: Tests mounted read-only at /tests/; chmod 700 defense during pytest.
- **Bypassing**: Tests verify 10 outputs including boolean and list series; stdlib-only check detects dynamic imports; naive trap for old single-stage equilibrium model fails kinetic scenario by design.
- **Spec alignment**: Instruction pins Newton 5 iterations, Souders-Brown formula, two-stage cascade description, kinetic ODE explicit Euler, output keys exact set, stdlib only math, deterministic.

<!-- v4 hardening to target 2-8% band with oracle 3/3 validated locally as of 2026-07-05 -->
