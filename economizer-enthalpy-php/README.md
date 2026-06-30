# economizer-enthalpy-php

## Description
Implement pure-PHP numerical model of air-side economizer with enthalpy-based switchover, sensor bias, integrated blending, low ambient lockout. Bin method evaluating at bin average; enthalpy calculation via psychrometrics requiring Hyland-Wexler saturation pressure two-branch no closed form; sensor fault bias applied to control decision but true enthalpy used for energy; integrated blending non-linear dependent on enthalpy differential; low ambient lockout. These couple so single-miss drifts past tight tolerances on net savings.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | 5/5 (100%) _prior version too easy_ |
| Avocado | 5/5 (100%) _prior version too easy_ |
| GPT-5.5 | 5/5 (100%) _prior version too easy_ |
| Sonnet 4.6 | _not yet run_ |

*Note: v9.0 shows 5/5 across models indicating too-easy calibration despite extreme hardening (60 scenarios, tight tolerance). v10 will further harden via explicit spec clarifications and maintained tight tolerance to target 2-3/5 band.*

## Model Analysis

Oracle achieves 100% pass rate validating reference implementation correctness. Prior versions show 5/5 across Opus, Avocado, GPT indicating task is currently too easy despite 60-scenario coverage and tight numeric tolerances. Successful solutions demonstrate correct Hyland-Wexler saturation pressure two-branch implementation with exact coefficients, humidity ratio wet-bulb formula, enthalpy calculation, bin method averaging, sensor bias applied to control decision only not energy calculation, integrated blending linear ratio, and low ambient lockout. Failures typically stem from incorrect ice/water branch boundary at exactly t=0, missing CSV BOM handling, extra helper functions beyond allowed API surface, or floating-point summation order drift.

## Anti-Cheating Analysis

Outputs depend on continuous physical inputs across 60 distinct configuration scenarios with stateful bin-method coupling; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently; matching requires full specified model.

- **Hardcoded outputs**: Tests use continuous physical parameters across 60 scenarios generated at runtime with tight 1e-9 tolerance; pre-computed answers cannot match without implementing full psychrometric model.
- **Overfitting to visible tests**: Test inputs parameterized across temperature bins, sensor biases, changeover enthalpies, differential thresholds, low ambient lockouts covering edge cases of ice branch, BOM handling, blending ratio, and lockout logic; no single constant passes.
- **Modifying test files**: Tests mounted read-only by Codimango at `/tests/`; test.sh applies chmod 700 defense during phpunit to mitigate C18 in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories of fan extra, compressor saved, net savings, and mode hours across 60 scenarios, not just final output, so shortcutting psychrometric formulas or bin averaging is detected by numeric drift. Extra-function ban enforced via test and now explicitly stated in spec to align spec-test contract.
