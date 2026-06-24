# economizer-enthalpy-php

## Description
A pure-PHP numerical modeling task implementing air-side economizer with enthalpy-based switchover control, sensor fault bias injection, integrated economizer blending, and low-ambient lockout for commercial building AHU. Agent implements `/app/econ_sim.php` exposing functions to compute psychrometric enthalpy, apply sensor bias, determine economizer mode, and produce annual compressor saved kWh, fan extra kWh, net savings, mode hours via bin method.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | TBD |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

Oracle to be validated locally in Docker and on Codimango.

## Model Analysis
TBD after Codimango runs.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values computed in-test by independent reference over deterministic synthetic climates with fixed seed. No fixed constant to memorize.
- **Overfitting to visible tests:** grader lives in /tests and is not present in /app during solve; agent only writes econ_sim.php
- **Modifying test files:** tests mounted read-only separate from agent working directory.
- **Bypassing intended solution:** correctness requires all four interacting features. Grader asserts each single-miss shortcut drifts more than 4x tolerance away from reference.
- **Library shortcuts:** standard library only, no external packages. Verifier reads source to forbid wrapping.

## v2 Clean Redo Note
This is net new task to fill taxonomy gap for PHP/Hack language at 3.80% vs 5% target -1.2pp. Follows v2 clean redo pattern with single module pure stdlib, independent reference in test, tight tolerances, fail-signal tests, and canary GUID preserved.
