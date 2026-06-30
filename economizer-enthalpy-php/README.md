# economizer-enthalpy-php

## Description
Implement pure-PHP numerical model of air-side economizer with enthalpy-based switchover, sensor bias, integrated blending, low ambient lockout. Bin method evaluating at bin average; enthalpy calculation via psychrometrics requiring Hyland-Wexler saturation pressure two-branch no closed form; sensor fault bias applied to control decision but true enthalpy used for energy; integrated blending non-linear dependent on enthalpy differential; low ambient lockout. These couple so single-miss drifts past tight tolerances on net savings.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | 5/5 (100%) |
| Sonnet 4 | TBD |
| GPT-5 | TBD |
| Gemini 2.5 Pro | TBD |

*Note: v10 hardens specification with explicit six-function API ban, BOM handling, ice branch <=0 consistency, and 1e-9 tolerance to target 2-3/5 difficulty band. Prior v9 showed 5/5 indicating too easy; v10 calibration _not yet run_.*

## Model Analysis

Oracle achieves 100% pass rate validating reference implementation correctness. Task requires correct Hyland-Wexler saturation pressure two-branch implementation with exact coefficients and ice branch at t<=0, humidity ratio wet-bulb formula, enthalpy calculation, bin method averaging, sensor bias applied to control decision only not energy calculation, integrated blending linear ratio, and low ambient lockout. Failures typically stem from incorrect ice/water branch boundary at exactly t=0, missing CSV BOM handling, extra helper functions beyond allowed six-function API surface, or floating-point summation order drift beyond 1e-9 tolerance.

## Anti-Cheating Analysis

Outputs depend on continuous physical inputs across 60 distinct configuration scenarios with stateful bin-method coupling; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently; matching requires full specified model.

- **Hardcoded outputs**: Tests use continuous physical parameters across 60 scenarios generated at runtime with tight 1e-9 tolerance; pre-computed answers cannot match without implementing full psychrometric model.
- **Overfitting to visible tests**: Test inputs parameterized across temperature bins, sensor biases, changeover enthalpies, differential thresholds, low ambient lockouts covering edge cases of ice branch, BOM handling, blending ratio, and lockout logic; no single constant passes.
- **Modifying test files**: Tests mounted read-only by Codimango at `/tests/`; test.sh applies chmod 700 defense during execution to mitigate C18 in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories of fan extra, compressor saved, net savings, and mode hours across 60 scenarios, not just final output, so shortcutting psychrometric formulas or bin averaging is detected by numeric drift. Extra-function ban enforced via test and explicitly stated in spec to align spec-test contract.
