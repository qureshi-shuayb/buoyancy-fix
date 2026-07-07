# flash-separator-surface-v1

## Description
Implement Python isenthalpic flash separator model for geothermal surface brine using Antoine saturation pressure correlation solved via Newton-Raphson 31 iterations, four-stage cascade mass balance, Souders-Brown carryover correlation, and silica kinetic precipitation ODE explicit Euler 10 substeps. Returns final steam/brine flows, quality, brine enthalpy, scaling risk, stage1/stage2/stage3/stage4 separated flows, silica concentration time series length 4, and T_sat trajectory length 4. Total 16 output keys with tightened 5e-16 tolerance.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Avocado | 0/5 (0% projected) |
| Opus | 0/5 (0% projected) |
| GPT | 0/5 (0% projected) |

## Model Analysis

Oracle achieves 100% validating reference implementation across twenty scenarios after v11 hardening: normal flash, subcooled no-flash, superheated limit, high silica scaling, low pressure high quality, carryover sensitivity, four-stage cascade, kinetic silica 10-step, extreme carryover, zero residence, extreme temperature, high silica kinetic, near-critical, supercritical edge, ultra low flow, ultra high temp, extreme silica high k, plus four ultra extreme v9 cases carried to v11. Expected difficulty hard targeting 0% pass band (0/5 projected) with v11 hardening to hard Oracle 3/3 projected 0/5. Successful solutions demonstrate correct Newton-Raphson Antoine inversion starting at 100C with exactly 31 iterations pinned not closed-form, Souders-Brown carryover = C_sb*sqrt(rho_v/(rho_l-rho_v)) with rho_v temperature dependent and clamps 1e-12 and cap 0.999, four-stage cascade where stage1 brine feeds stage2 at lower pressure and stage2 brine feeds stage3 and stage3 brine feeds stage4 at default 0.2 bar, silica kinetic ODE explicit Euler 10 substeps dC/dt = -k*(C-C_eq) over residence_time divided by 10 with per-stage re-concentration cf re-applied each stage, tightened 5e-16 tolerance for quality and flows, dh guard threshold 1e-15 explicitly, and correct output keys set of 16 including stage1/stage2/stage3/stage4 flows and silica series length 4 and T_sat_trajectory length 4. Failures typically: use old closed-form Antoine inversion instead of Newton causing slight deviation beyond 5e-16, use 1 or 5 or 13 or 23 iterations instead of exactly 31, ignore C_sb correlation using old constant carryover_frac, treat single or two or three stage only missing cascade mass balance, use equilibrium silica only ignoring 10-step Euler leading to false negative in kinetic test, mis-handle list lengths not equal 4, omit stage4 output keys or T_sat_trajectory, wrong clamp values 1e-6 or 0.99 instead of 1e-12 and 0.999, wrong dh guard not 1e-15, or clamp quality incorrectly.

## Anti-Cheating Analysis

Contamination risk MEDIUM: bespoke simulate() signature with Newton Antoine 31 iterations, four-stage cascade, Souders-Brown with specific clamps, kinetic silica 10-step Euler per-stage reapplied, T_sat_trajectory not matching public benchmarks. Novelty risk MEDIUM due to geothermal flash domain documented but specific pinned iterative formulas and four-stage 10-step combination novel.

- **Hardcoded outputs**: Tests use continuous physical parameters across twenty scenarios with tightened 5e-16 tolerance; precomputed table cannot match without implementing Newton 31 iteration and 4-stage cascade loop and 10-step Euler per stage.
- **Overfitting**: Parameter sweep covers subcooled, superheated, scaling risk true/false, low pressure, high carryover, four-stage pressure split, kinetic vs equilibrium divergence, extreme carryover, zero residence, extreme temperature, high silica kinetic, near-critical, supercritical edge, plus four ultra extreme v9 cases carried to v11.
- **Modifying test files**: Tests mounted read-only at /tests/; chmod 700 defense during pytest. Reference oracle moved to tests/ref_oracle.py to address C18 oracle leak; test file imports only, no inline reference source beyond import.
- **Bypassing**: Tests verify 16 outputs including boolean and two list series length 4; stdlib-only check detects dynamic imports; naive trap tests invoke agent.simulate and assert agent matches reference within 5e-16, proving not naive single-stage or 1-step Euler or closed-form Antoine; old single-stage equilibrium model fails kinetic scenario and missing stage4 keys and missing T_sat_trajectory by design.
- **Spec alignment**: Instruction pins Newton 31 iterations for Antoine convergence to machine epsilon, Souders-Brown, Souders-Brown formula with 1e-12 clamps and 0.999 cap, four-stage cascade description with explicit inter-stage enthalpy carry inlet_h equals previous brine_enthalpy, per-stage silica re-concentration and 10-step Euler for kinetic stability, dh guard 1e-15, output keys exact set of 16, stdlib only math, deterministic.

<!-- v11 hardening 2026-07-07 to hard 0/5 target with oracle 3/3, C18 oracle leak fix moving ref to ref_oracle.py, naive tests invoke agent, spec clarified per-stage silica and dh 1e-15 guard -->

