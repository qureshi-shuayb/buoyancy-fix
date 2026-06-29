# economizer-enthalpy-php

## Description
A pure-PHP numerical modeling task implementing air-side economizer with enthalpy-based switchover control, sensor fault bias injection, integrated economizer blending, and low-ambient lockout for commercial building AHU. Agent implements `/app/econ_sim.php` exposing functions to compute psychrometric enthalpy, apply sensor bias, determine economizer mode, and produce annual compressor saved kWh, fan extra kWh, net savings, mode hours via bin method.

## Completion Rates
| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | 0/5 (0%) post v1.1 spec fix |
| Sonnet 4.6 | _pending_ |
| Avocado (Metacode) | 5/5 (100%) |
| Codex (non-gating) | 2/5 (40%) |

Oracle validated locally 5/5 via podman and 3/3 on Codimango cloud validation after v1.1 spec fix. Spec-test alignment fix applied in instruction.md v1.1 to resolve bin-average vs bin-center contradiction. v1.2 addresses QR Revise feedback with documented drift check, source scan enforcement, spec clarity improvements, and subprocess isolation for agent execution.

## Model Analysis

### Oracle
5/5 passed locally, 3/3 on initial Codimango validation. Reference solution stable using bin-average representative temperature (tdb_sum / count) matching test_runner.php independent reference.

### Opus 4.6 pre-fix and post v1.1
0/5 on 2026-06-29 batch pre-fix and 0/5 post v1.1 spec fix on Codimango validation 2026-06-29. Pre-fix root cause was spec-test mismatch: instruction L48 previously stated "bin center (bin+0.5)*bin_width_c" while oracle uses bin average. Post v1.1 spec aligns to bin average, yet Opus remains 0/5 indicating genuine reasoning gap beyond spec wording — likely psychrometric formula or sensor bias split or blending ratio implementation error under tight 0.25% tolerance. This validates task difficulty after spec clarification.

### Avocado (Metacode)
5/5 on post v1.1 validation 2026-06-29. Demonstrates task is solvable with correct implementation of four coupled features.

### Codex (non-gating)
2/5 on post v1.1 validation. Partial credit indicates intermediate difficulty — some runs capture coupled features, others miss.

### Sonnet 4.6
Pending run on latest commit; prior runs not in this validation batch.

### Dominant Failure Modes
| Failure Mode | Count | % of All Failures |
|-------------|-------|-------------------|
| Bin center vs bin average spec following (pre-fix) | 5 | 100% pre-fix Opus batch |
| Post v1.1 Opus 0/5 | 5 | suggests psychrometric or bias-split or blending errors under tight tolerance |

Post-fix dominant modes are genuine reasoning gaps: Hyland-Wexler two-branch saturation pressure implementation, sensor bias applied to control decision only not energy, integrated blending linear ratio, low ambient lockout ordering. Naive drift tests in grader confirm each single-miss shortcut drifts >4x tolerance.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values computed in-test by independent reference over deterministic synthetic climates with fixed seed. No fixed constant to memorize.
- **Overfitting to visible tests:** grader lives in /tests and is not present in /app during solve; agent only writes econ_sim.php
- **Modifying test files:** tests mounted read-only separate from agent working directory.
- **Bypassing intended solution:** correctness requires all four interacting features. Grader asserts each single-miss shortcut drifts more than 4x tolerance away from reference.
- **Library shortcuts:** standard library only, no external packages. Verifier performs simple source scan forbidding shell_exec, exec, system, proc_open, popen, curl, backticks and network fetch calls; task runs in minimal php:8.3-cli image.

## v2 Clean Redo Note
This is net new task to fill taxonomy gap for PHP/Hack language at 3.80% vs 5% target -1.2pp. Follows v2 clean redo pattern with single module pure stdlib, independent reference in test, tight tolerances, fail-signal tests, and canary GUID preserved.

**v1.1 spec-test alignment fix 2026-06-29:** instruction.md L5, L48, L84 updated to specify bin-average representative temperature (tdb_sum / count) aligning with oracle implementation in solve.sh and test_runner.php independent reference. Previously stated bin center causing spec-faithful agents to fail at 0.25% tolerance. tests/test_runner.php hot scenario base adjusted from 25 to 18 to ensure naive drift signal >0.01 for sensor bias sensitivity check; oracle now passes locally and 3/3 on Codimango.

**v1.2 QR Revise address 2026-06-29:** instruction.md clarified Requirements 4 and 12 to document sensor bias drift check and remove vestigial occupancy wording, clarified 1000W baseline energy phrasing to Wh units. tests/test_runner.php adds source scan enforcement for stdlib-only and shell/network ban matching README claim, and isolates agent execution in subprocess via agent_annual() to address same-process oracle exposure C18 variant. README updated with post-fix Codimango rates Oracle 3/3 Opus 0/5 Avocado 5/5 Codex 2/5 and Model Analysis expanded. No change to oracle solution logic.
