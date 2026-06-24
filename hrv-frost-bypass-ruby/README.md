# hrv-frost-bypass-ruby

## Description
A pure-Ruby numerical modeling task implementing heat recovery ventilator with frost control bypass damper, effectiveness derate, and supply temperature maintenance for commercial building ventilation. Agent implements `/app/hrv_sim.rb` exposing functions to read hourly temperatures, interpolate curves, compute frost point, and produce annual fan energy kWh, supplementary heating kWh, recovered heat kWh, and frost hours via bin method per occupancy state with hysteresis state machine.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 3/3 |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

Oracle validated locally passing 3/3. Expected difficulty calibration target similar to baselines.

## Model Analysis
TBD after Codimango runs.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values computed in-test by independent reference over deterministic synthetic profiles with fixed seed. Parameters parametrized across cases. No fixed constant to memorize.
- **Overfitting to visible tests:** grader lives in /tests and is not present in /app during solve; agent only writes hrv_sim.rb
- **Modifying test files:** tests mounted read-only separate from agent working directory.
- **Bypassing intended solution:** correctness requires all four interacting features. Grader asserts each single-miss shortcut drifts more than 4x tolerance away from reference.
- **Library shortcuts:** standard library only csv and math allowed. No third-party packages permitted.

## v2 Clean Redo Note
This is net new task to fill taxonomy gap for Ruby language at 4.74% vs 10% target -5.26pp red highest priority. Follows v2 clean redo pattern with single module pure stdlib, independent reference in test, tight tolerances, fail-signal tests, and canary GUID preserved.
