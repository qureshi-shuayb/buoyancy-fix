# flash-separator-surface-v1

## Description
Implement Python isenthalpic flash separator model for geothermal surface brine using Antoine saturation pressure correlation log10(Psat)=A-B/(T+C), mass-energy balance, liquid carryover, and silica scaling risk. Returns steam flow, brine flow, quality, brine enthalpy, scaling risk boolean.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4 | _not yet run_ |
| Sonnet 4 | _not yet run_ |
| GPT-5 | _not yet run_ |

## Model Analysis

Oracle achieves 100% validating reference implementation across normal flash, subcooled no-flash, superheated limit, high silica scaling, low pressure high quality, and carryover sensitivity scenarios. Expected difficulty medium targeting 2-3/5 calibration. Successful solutions demonstrate correct Antoine inversion with clamp, quality clamp to [0,1], carryover linear correction, silica concentration factor, and exponential solubility correlation. Failures typically omit denominator clamp in Antoine inversion, forget quality clamp, mis-apply carryover to energy balance instead of mass flow only, or use wrong solubility formula.

## Anti-Cheating Analysis

Contamination risk LOW: bespoke simulate() signature with pinned Antoine coefficients and exponential silica solubility not matching public benchmarks. Novelty risk MEDIUM due to geothermal flash domain being documented but specific pinned formulas novel.

- **Hardcoded outputs**: Tests use continuous physical parameters across six scenarios with tight 1e-6 tolerance; precomputed table cannot match without implementing model.
- **Overfitting**: Parameter sweep covers subcooled, superheated, scaling risk true/false, low pressure, high carryover.
- **Modifying test files**: Tests mounted read-only at /tests/; chmod 700 defense during pytest.
- **Bypassing**: Tests verify 5 outputs including boolean; stdlib-only check detects dynamic imports.
- **Spec alignment**: Instruction pins exact Antoine inversion, h_l, h_v, quality clamp, carryover, solubility formulas.
