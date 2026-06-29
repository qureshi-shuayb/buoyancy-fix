# economizer-enthalpy-php

## Description
A pure-PHP numerical modeling task implementing air-side economizer with enthalpy-based switchover control, sensor fault bias injection, integrated economizer blending, and low-ambient lockout for commercial building AHU. Agent implements `/app/econ_sim.php` exposing functions to compute psychrometric enthalpy, apply sensor bias, determine economizer mode, and produce annual compressor saved kWh, fan extra kWh, net savings, mode hours via bin method.

## Completion Rates
| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | 0/5 (0%) |
| Sonnet 4.6 | _not run in validation suite_ |
| Avocado (Metacode) | 4/5 (80%) |
| Codex (non-gating) | 2/5 (40%) |

Oracle validated 3/3 on Codimango cloud validation after v1.4 difficulty hardening. Spec-test alignment fix applied in v1.1, QR Revise addressed in v1.2, difficulty calibrated in v1.3-v1.4. Avocado at 4/5 indicates hard but solvable task with tight 0.1% tolerance providing discrimination; Opus at 0/5 shows reasoning gap on coupled psychrometric features.

## Model Analysis

### Oracle
3/3 passed on Codimango cloud validation across v1.1, v1.3, v1.4 commits. Local podman validation also passes consistently. Reference solution stable using bin-average representative temperature matching test_runner independent reference.

### Opus 4.6
0/5 on 2026-06-29 pre-fix batch due to spec-test mismatch, and 0/5 post v1.1 spec fix, 0/5 post v1.3 tightening, 0/5 post v1.4 tightening on Codimango validation. Persistent failure indicates genuine reasoning gap on coupled features under tight tolerance, not spec ambiguity. Validates task difficulty after spec clarification.

### Avocado (Metacode)
5/5 pre-v1.3, 5/5 on v1.3 tightening to 0.15%, then 4/5 on v1.4 tightening to 0.1% — demonstrates successful difficulty calibration moving Avocado off ceiling while keeping Oracle passing. Shows task is hard but achievable.

### Codex (non-gating)
2/5 on post v1.1 and post v1.3 and post v1.4 runs — stable partial credit indicating intermediate difficulty and non-trivial reasoning required.

### Sonnet 4.6
Not run in default Codimango validation suite for this task; tracked as pending in README template but not required for gating.

### Dominant Failure Modes
| Failure Mode | Count | % of All Failures |
|-------------|-------|-------------------|
| Bin center vs bin average spec following (pre-v1.1 historical) | 5 | 100% pre-fix Opus batch |
| Post v1.1-v1.4 Opus 0/5 persistent | 15 across 3 runs | indicates psychrometric formula, sensor bias split, blending ratio, or lockout ordering errors under tight tolerance |
| Codex partial 2/5 | consistent | suggests some model variants capture coupled features partially |

Post-fix failures reflect genuine reasoning gaps, not spec ambiguity or test brittleness: Hyland-Wexler two-branch saturation pressure, sensor bias applied to control only not energy, integrated blending linear ratio, low ambient lockout ordering, bin-average aggregation.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values computed in-test by independent reference over deterministic synthetic climates with fixed seed. No fixed constant to memorize.
- **Overfitting to visible tests:** grader lives in /tests and is not present in /app during solve; agent only writes econ_sim.php
- **Modifying test files:** tests mounted read-only separate from agent working directory.
- **Bypassing intended solution:** correctness requires all four interacting features. Grader asserts each single-miss shortcut drifts more than 4x tolerance away from reference.
- **Library shortcuts:** standard library only, no external packages. Verifier performs simple source scan forbidding shell_exec, exec, system, proc_open, popen, curl, backticks and network fetch calls; task runs in minimal php:8.3-cli image.

## v2 Clean Redo Note
This is net new task to fill taxonomy gap for PHP/Hack language at 3.80% vs 5% target -1.2pp. Follows v2 clean redo pattern with single module pure stdlib, independent reference in test, tight tolerances, fail-signal tests, and canary GUID preserved.

**v1.1 spec-test alignment fix 2026-06-29:** instruction.md L5, L48, L84 updated to specify bin-average representative temperature (tdb_sum / count) aligning with oracle implementation in solve.sh and test_runner.php independent reference. Previously stated bin center causing spec-faithful agents to fail at 0.15% tolerance. tests/test_runner.php hot scenario base adjusted from 25 to 18 to ensure naive drift signal >0.01 for sensor bias sensitivity check; oracle now passes locally and 3/3 on Codimango.

**v1.2 QR Revise address 2026-06-29:** instruction.md clarified Requirements 4 and 12 to document sensor bias drift check and remove vestigial occupancy wording, clarified 1000W baseline energy phrasing to Wh units. tests/test_runner.php adds source scan enforcement for stdlib-only and shell/network ban matching README claim, and isolates agent execution in subprocess via agent_annual() to address same-process oracle exposure C18 variant. README updated with post-fix Codimango rates Oracle 3/3 Opus 0/5 Avocado 5/5 Codex 2/5 and Model Analysis expanded. No change to oracle solution logic.
