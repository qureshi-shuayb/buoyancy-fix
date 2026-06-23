# economizer-enthalpy-php

## Description
A pure-PHP numerical modeling task implementing air-side economizer with enthalpy-based switchover control, sensor fault bias injection, integrated economizer blending, and low-ambient lockout for commercial building AHU. Agent implements `/app/econ_sim.php` exposing functions to compute psychrometric enthalpy from dry-bulb and wet-bulb temperatures via Hyland-Wexler saturation pressure, apply sensor bias to control decision, determine economizer mode per hour, and produce annual compressor energy saved kWh, fan extra energy kWh, net savings kWh, and mode hours via bin method.

The task is calibrated so naive attempt fails. Four interacting hard parts not scaffolding:

1. **Enthalpy calculation** requires psychrometric saturation pressure via ASHRAE Hyland-Wexler two-branch log-polynomial correlation with over-ice branch below 0C, then humidity ratio then moist air enthalpy formula. Simplified Magnus/Tetens or dry-bulb-only approximation drifts enthalpy crossover point outside tolerance especially at cold and humid edge cases.
2. **Sensor fault bias** shifts perceived outdoor enthalpy used for control decision but true enthalpy must be used for energy calculation split. Ignoring bias or applying to both control and energy misclassifies mode selection on shoulder hours.
3. **Integrated economizer blending** non-linear dependent on enthalpy differential and damper position limit allowing simultaneous economizer and mechanical cooling above changeover but below differential threshold with part-load blending ratio. Fixed threshold shortcut misses part-load blending energy.
4. **Low ambient lockout** disables economizer below low ambient cutout temperature to prevent coil freeze forcing mechanical cooling even when enthalpy favorable. Lockout interacts with sensor bias shifting perceived temperature across threshold.

These couple: sensor bias shifts perceived enthalpy crossing differential threshold changing mode selection; integrated blending ratio depends on enthalpy differential which depends on accurate psychrometrics; lockout availability depends on perceived outdoor temperature which depends on sensor bias; part-load fan extra energy depends on mode hours distribution. A model implementing any single feature but missing coupling drifts past tight 0.5% tolerance on net savings.

Other requirements: 8760 and 8784 row files both valid for hourly outdoor DB WB and return DB WB profiles; malformed CSV rows skipped; hour-of-day derives from position within valid data; all unit conversions must reconcile.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | TBD |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

Oracle to be validated locally in Docker and on Codimango. Expected difficulty calibration target similar to psychrometrics-library-v2 baseline with sensor fault adding extra trap.

## Model Analysis
TBD after Codimango runs. Anticipated failure modes:
- Dry-bulb-only economizer ignoring enthalpy will misclassify humid shoulder hours causing >5% net savings error.
- Ignoring sensor bias or applying bias to energy calculation instead of only control decision will drift mode selection.
- Fixed threshold without integrated blending will miss part-load blending energy at near-crossover hours.
- Igning low ambient lockout will overpredict savings in cold climate.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values computed in-test by independent reference over deterministic synthetic climates with fixed seed across cold mixed hot climates with parametrized sensor bias values economizer changeover differential thresholds lockout temperatures bin width. No fixed constant to memorize.
- **Overfitting to visible tests:** grader lives in /tests and is not present in /app during solve; agent only writes econ_sim.php
- **Modifying test files:** tests mounted read-only separate from agent working directory.
- **Bypassing intended solution:** correctness requires all four interacting features — accurate psychrometric enthalpy via Hyland-Wexler two-branch, sensor bias applied correctly to control not energy, integrated blending non-linear, low ambient lockout. Grader asserts each single-miss shortcut drifts more than 4x 0.5% tolerance away from reference.
- **Library shortcuts:** standard library only, no external psychrometrics HVAC or math packages beyond PHP built-in math functions. Verifier reads source to forbid wrapping.

## v2 Clean Redo Note
This is net new task to fill taxonomy gap for PHP/Hack language at 3.80% vs 5.00% target -1.20pp within 5pp yellow per language coverage table, and for economizer enthalpy control domain extending psychrometrics-library-v2. Follows v2 clean redo pattern established with single module pure stdlib, independent reference in test, tight tolerances, fail-signal tests, and canary GUID preserved.
