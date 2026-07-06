# flash-separator-surface-v1

## Description
Implement Python isenthalpic flash separator model for geothermal surface brine using Antoine saturation pressure correlation solved via Newton-Raphson 23 iterations, three-stage cascade mass balance, Souders-Brown carryover correlation, and silica kinetic precipitation ODE explicit Euler 10 substeps. Returns final steam/brine flows, quality, brine enthalpy, scaling risk, stage1/stage2/stage3 separated flows, silica concentration time series length 3, and T_sat trajectory length 3. Total 13 output keys with tightened 1e-15 tolerance.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Avocado | 0/5 (0% projected) |
| Opus | 0/5 (0% projected) |
| GPT | 0/5 (0% projected) |

## Model Analysis

Oracle achieves 100% validating reference implementation across twenty scenarios after v8 hardening: normal flash, subcooled no-flash, superheated limit, high silica scaling, low pressure high quality, carryover sensitivity, three-stage cascade, kinetic silica 10-step, extreme carryover, zero residence, extreme temperature, high silica kinetic, near-critical, supercritical edge, ultra low flow, ultra high temp, extreme silica high k, plus four ultra extreme v8 cases. Expected difficulty hard targeting 0% pass band (0/5 projected). Successful solutions demonstrate correct Newton-Raphson Antoine inversion starting at 100C with exactly 23 iterations pinned not closed-form, Souders-Brown carryover = C_sb*sqrt(rho_v/(rho_l-rho_v)) with rho_v temperature dependent and clamps 1e-12 and cap 0.999, three-stage cascade where stage1 brine feeds stage2 at lower pressure and stage2 brine feeds stage3 at lower pressure, silica kinetic ODE explicit Euler 10 substeps dC/dt = -k*(C-C_eq) over residence_time divided by 10, tightened 1e-15 tolerance for quality and flows, and correct output keys set of 13 including stage1/stage2/stage3 flows and silica series and T_sat_trajectory. Failures typically: use old closed-form Antoine inversion instead of Newton causing slight deviation beyond 1e-15, use 1 or 5 or 13 iterations instead of exactly 23, ignore C_sb correlation using old constant carryover_frac, treat single or two stage only missing cascade mass balance, use equilibrium silica only ignoring 10-step Euler leading to false negative in kinetic test, mis-handle list lengths not equal 3, omit stage3 output keys or T_sat_trajectory, wrong clamp values 1e-6 or 0.99 instead of 1e-12 and 0.999, or clamp quality incorrectly.

## Anti-Cheating Analysis

Contamination risk MEDIUM: bespoke simulate() signature with Newton Antoine 23 iterations, three-stage cascade, Souders-Brown with specific clamps, kinetic silica 10-step Euler, T_sat_trajectory not matching public benchmarks. Novelty risk MEDIUM due to geothermal flash domain documented but specific pinned iterative formulas and three-stage 10-step combination novel.

- **Hardcoded outputs**: Tests use continuous physical parameters across twenty scenarios with tightened 1e-15 tolerance; precomputed table cannot match without implementing Newton 23 iteration and 3-stage cascade loop and 10-step Euler.
- **Overfitting**: Parameter sweep covers subcooled, superheated, scaling risk true/false, low pressure, high carryover, three-stage pressure split, kinetic vs equilibrium divergence, extreme carryover, zero residence, extreme temperature, high silica kinetic, near-critical, supercritical edge, plus four ultra extreme v8 cases.
- **Modifying test files**: Tests mounted read-only at /tests/; chmod 700 defense during pytest.
- **Bypassing**: Tests verify 13 outputs including boolean and two list series length 3; stdlib-only check detects dynamic imports; naive trap for old single-stage equilibrium model fails kinetic scenario and missing stage3 keys and missing T_sat_trajectory by design.
- **Spec alignment**: Instruction pins Newton 23 iterations, Souders-Brown formula with 1e-12 clamps and 0.999 cap, three-stage cascade description, kinetic ODE explicit Euler 10 substeps, output keys exact set of 13, stdlib only math, deterministic.

<!-- v8 hardening to too-hard targeting 0% projected with oracle 3/3 validated locally as of 2026-07-06 -->
