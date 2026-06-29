# economizer-enthalpy-php

## Description
A pure-PHP numerical modeling task implementing air-side economizer with enthalpy-based switchover control, sensor fault bias injection, integrated economizer blending, and low-ambient lockout for commercial building AHU. Agent implements `/app/econ_sim.php` exposing functions to compute psychrometric enthalpy, apply sensor bias, determine economizer mode, and produce annual compressor saved kWh, fan extra kWh, net savings, mode hours via bin method.

## Completion Rates
| Model | Pass Rate |
|-------|-----------|
| Oracle | 5/5 (100%) |
| Sonnet 4.6 | _pending re-run after spec fix_ |
| Opus 4.6 | 0/5 pre-fix (spec mismatch), _pending re-run_ |
| Avocado | _pending re-run after spec fix_ |

Oracle validated locally 5/5 and on Codimango 3/3 initial. Spec-test alignment fix applied in instruction.md v1.1 to resolve bin-average vs bin-center contradiction. Expected difficulty calibration target similar to baselines after re-run.

## Model Analysis

### Oracle
5/5 passed locally, 3/3 on initial Codimango validation. Reference solution stable using bin-average representative temperature (tdb_sum / count) matching test_runner.php independent reference.

### Opus 4.6 pre-fix
0/5 on 2026-06-29 batch. Failure root cause confirmed as spec-test mismatch: instruction L48 previously stated "bin center (bin+0.5)*bin_width_c" while oracle and grader use bin average. Opus implemented spec literally, resulting in >0.25% drift on net_savings_kwh across cold/mixed/hot/variable scenarios. This validates tight tolerance coupling — single bin-method miss drifts past threshold as intended, but direction was driven by ambiguous spec not reasoning gap. Spec updated to bin average to align with oracle.

### Sonnet 4.6 / Avocado
Pending re-run after spec fix. Expected behavior: models implementing four interacting features — Hyland-Wexler two-branch saturation pressure, sensor bias split control vs energy, integrated blending ratio, low ambient lockout — should achieve partial to full passes with 0.25% tolerance providing discrimination. Naive drift tests in grader confirm each single-miss shortcut drifts >4x tolerance.

### Dominant Failure Modes pre-fix
| Failure Mode | Count | % of All Failures |
|-------------|-------|-------------------|
| Bin center vs bin average spec following | 5 | 100% pre-fix Opus batch |

Post-fix, expected dominant modes shift to genuine reasoning gaps: psychrometric formula errors, sensor bias applied to energy instead of control only, blending ratio miscalculation, lockout ordering.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values computed in-test by independent reference over deterministic synthetic climates with fixed seed. No fixed constant to memorize.
- **Overfitting to visible tests:** grader lives in /tests and is not present in /app during solve; agent only writes econ_sim.php
- **Modifying test files:** tests mounted read-only separate from agent working directory.
- **Bypassing intended solution:** correctness requires all four interacting features. Grader asserts each single-miss shortcut drifts more than 4x tolerance away from reference.
- **Library shortcuts:** standard library only, no external packages. Verifier reads source to forbid wrapping.

## v2 Clean Redo Note
This is net new task to fill taxonomy gap for PHP/Hack language at 3.80% vs 5% target -1.2pp. Follows v2 clean redo pattern with single module pure stdlib, independent reference in test, tight tolerances, fail-signal tests, and canary GUID preserved.

**v1.1 spec-test alignment fix 2026-06-29:** instruction.md L5, L48, L84 updated to specify bin-average representative temperature (tdb_sum / count) aligning with oracle implementation in solve.sh and test_runner.php independent reference. Previously stated bin center causing spec-faithful agents to fail at 0.25% tolerance. tests/test_runner.php hot scenario base adjusted from 25 to 18 to ensure naive drift signal >0.01 for sensor bias sensitivity check; oracle now passes 1 locally and 5/5 expected. No change to oracle solution logic — spec clarification and test calibration only.
