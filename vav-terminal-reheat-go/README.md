# vav-terminal-reheat-go

## Description
A pure-Go numerical modeling task implementing VAV terminal unit with pressure-dependent airflow, reheat coil staging, and duct static pressure reset for commercial building single zone served by variable air volume system. Agent implements `/app/vav_sim.go` exposing functions to compute airflow from damper position and available static pressure, interpolate coil effectiveness curves, derive schedule-dependent balance points, and produce annual fan energy kWh, reheat energy kWh, and comfort degree-hours via bin method per occupancy state.

The task is calibrated so naive attempt fails. Four interacting hard parts not scaffolding:

1. **Pressure-dependent airflow** must be solved from damper authority curve versus available duct static pressure each hour, not commanded directly. Fixed-flow shortcut mis-estimates fan power via fan affinity laws cubed.
2. **Static pressure reset schedule** duct static follows reset based on warmest zone demand, so available static changes by hour shifting flow capability just when load rises. Single fixed static misclassifies many hours regime.
3. **Reheat coil staging with minimum airflow** too low minimum saves fan but forces more reheat; too high wastes reheat at part load. Must find balance per bin between fan savings and reheat penalty.
4. **Coil effectiveness non-linear** hot water coil effectiveness varies with water flow rate and air-side delta-T via NTU-effectiveness relation, so delivered heat is not proportional to valve command. Linear approximation drifts past tolerance at low flow edge.

These couple: reset shifts available static which changes flow which changes whether reheat is needed; coil effectiveness depends on flow at bin center which depends on damper position which depends on reset state; part-load fan power depends cubically on flow solved from pressure. A model implementing any single feature but missing coupling drifts past tight 1% tolerance.

Other requirements: 8760 and 8784 row files both valid for hourly load profiles; malformed CSV rows skipped; hour-of-day derives from position within valid temperatures; all unit conversions W to kW hour to energy must reconcile.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | TBD |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

Oracle to be validated locally in Docker and on Codimango. Expected difficulty calibration target similar to degree-day-energy-v2 and thermostat-heatpump-v2 baselines.

## Model Analysis
TBD after Codimango runs.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values computed in-test by independent reference over deterministic synthetic load profiles and duct static schedules with fixed seed. UA schedule setpoints coil curves damper authority coefficients reset parameters bin width parametrized across cases, and both normal-year and leap-year length profiles graded. No fixed constant to memorize.
- **Overfitting to visible tests:** grader lives in /tests and is not present in /app during solve; agent only writes vav_sim.go
- **Modifying test files:** tests mounted read-only separate from agent working directory.
- **Bypassing intended solution:** correctness requires all four interacting features — pressure-flow solve per bin per occupancy state, static reset schedule coupling, interpolated coil effectiveness with NTU relation, and reheat staging logic with minimum airflow. Grader asserts each single-miss shortcut drifts more than 4x 1% tolerance away from reference.
- **Library shortcuts:** standard library only math package allowed. No third-party HVAC or fluid dynamics packages permitted.

## v2 Clean Redo Note
This is net new task to fill taxonomy gap for Go language at 8.36% vs 10% target -1.64pp within 5pp yellow per language coverage table. Follows v2 clean redo pattern established for psychrometrics-library-v2 degree-day-energy-v2 thermostat-heatpump-v2 homebidder-v2 with single module pure stdlib, independent reference in test, tight tolerances, fail-signal tests, and canary GUID preserved.
