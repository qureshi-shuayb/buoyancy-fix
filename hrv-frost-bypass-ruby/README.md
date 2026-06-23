# hrv-frost-bypass-ruby

## Description
A pure-Ruby numerical modeling task implementing heat recovery ventilator with frost control bypass damper, effectiveness derate, and supply temperature maintenance for commercial building ventilation. Agent implements `/app/hrv_sim.rb` exposing functions to read hourly temperatures, interpolate curves, compute frost point, and produce annual fan energy kWh, supplementary heating kWh, recovered heat kWh, and frost hours via bin method per occupancy state with hysteresis state machine.

The task is calibrated so naive attempt fails. Four interacting hard parts not scaffolding:

1. **Effectiveness derate non-linear** with airflow ratio and temperature differential via NTU-effectiveness relation approximated by curve, not constant effectiveness. Fixed effectiveness overpredicts recovery at part load and extreme cold.
2. **Frost threshold dynamic** depends on exhaust humidity ratio which depends on indoor moisture generation schedule varying by hour-of-day occupancy, requiring psychrometric saturation pressure calculation to derive frost point dynamically per hour not fixed outdoor temp threshold.
3. **Bypass damper hysteresis state machine** interacting with supply temperature maintenance: when bypass opens to protect core from frost, supply temperature drops triggering supplementary electric heater to maintain setpoint; heater energy depends on bypass fraction which depends on frost state history creating stateful coupling across hours. No hysteresis causes chattering and wrong energy.
4. **Fan power rise with bypass** non-linear increase in pressure drop through bypass path versus core path, so fan power rises during bypass events not constant. Ignoring this underpredicts fan energy during coldest hours.

These couple: frost threshold depends on indoor humidity schedule which changes by hour-of-day occupancy state; bypass hysteresis state determines effectiveness derate and fan power rise simultaneously; supplementary heating depends on bypass fraction history; effectiveness derate depends on airflow which depends on occupancy state. A model implementing any single feature but missing coupling drifts past tight 0.5% tolerance on recovered energy and 5% on supplementary heating.

Other requirements: 8760 and 8784 row files both valid for hourly outdoor temperature and indoor humidity generation profiles; malformed CSV rows skipped; hour-of-day derives from position within valid data; all unit conversions W to kW hour to energy must reconcile.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | TBD |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

Oracle to be validated locally in Docker and on Codimango. Expected difficulty calibration target similar to psychrometrics-library-v2 baseline: Oracle passing, best models 1-2/5 passing to achieve pass/fail balance. Ruby unusual for numerical thermodynamics increases difficulty beyond Python baseline.

## Model Analysis
TBD after Codimango runs. Anticipated failure modes:
- Fixed effectiveness constant 0.75 ignoring derate curve will overpredict recovered heat by >5% at part load.
- Fixed frost threshold at -5C outdoor ignoring dynamic psychrometric frost point calculation will misclassify frost hours by >20%.
- No hysteresis on bypass damper will cause chattering and wrong supplementary heating energy.
- Constant fan power ignoring bypass pressure rise will underpredict fan energy during coldest hours.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values computed in-test by independent reference over deterministic synthetic outdoor temperature and indoor humidity generation profiles with fixed seed across cold mixed mild climates. UA effectiveness curves frost threshold parameters bin width parametrized across cases. No fixed constant to memorize.
- **Overfitting to visible tests:** grader lives in /tests and is not present in /app during solve; agent only writes hrv_sim.rb
- **Modifying test files:** tests mounted read-only separate from agent working directory.
- **Bypassing intended solution:** correctness requires all four interacting features — effectiveness derate per bin per occupancy, dynamic frost point via psychrometrics, hysteresis state machine for bypass, fan power rise with bypass. Grader asserts each single-miss shortcut drifts more than 4x tolerance away from reference.
- **Library shortcuts:** standard library only csv and math allowed. No third-party HVAC psychrometrics or numerical packages permitted. Verifier reads source to forbid wrapping.

## v2 Clean Redo Note
This is net new task to fill taxonomy gap for Ruby language at 4.74% vs 10% target -5.26pp red >5pp below highest priority per language coverage table. Follows v2 clean redo pattern established for psychrometrics-library-v2 degree-day-energy-v2 thermostat-heatpump-v2 homebidder-v2 with single module pure stdlib, independent reference in test, tight tolerances, fail-signal tests, and canary GUID preserved.
