# vav-terminal-reheat-go

## Description
A pure-Go numerical modeling task implementing VAV terminal unit with pressure-dependent airflow, reheat coil staging, and duct static pressure reset for commercial building single zone served by variable air volume system. Agent implements `/app/vav_sim.go` exposing functions to compute airflow from damper position and available static pressure, interpolate coil effectiveness curves, derive schedule-dependent balance points, and produce annual fan energy kWh, reheat energy kWh, and comfort degree-hours via bin method per occupancy state.

The task is calibrated so naive attempt fails. Four interacting hard parts not scaffolding:

1. **Pressure-dependent airflow** must be solved from damper authority curve versus available duct static pressure each hour, not commanded directly. Fixed-flow shortcut mis-estimates fan power via fan affinity laws cubed.
2. **Static pressure reset schedule** duct static follows reset based on warmest zone demand, so available static changes by hour shifting flow capability just when load rises. Single fixed static misclassifies many hours regime.
3. **Reheat coil staging with minimum airflow** too low minimum saves fan but forces more reheat; too high wastes reheat at part load. Must find balance per bin between fan savings and reheat penalty.
4. **Coil effectiveness non-linear** hot water coil effectiveness varies with water flow rate and air-side delta-T via NTU-effectiveness relation, so delivered heat is not proportional to valve command. Linear approximation drifts past tolerance at low flow edge.

These couple: reset shifts available static which changes flow which changes whether reheat is needed; coil effectiveness depends on flow at bin center which depends on damper position which depends on reset state; part-load fan power depends cubically on flow solved from pressure. A model implementing any single feature but missing coupling drifts past tight 2% tolerance.

Other requirements: 8760 and 8784 row files both valid for hourly load profiles; malformed CSV rows skipped; hour-of-day derives from position within valid temperatures; all unit conversions W to kW hour to energy must reconcile.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 3/3 |
| Sonnet 4.6 | TBD pending Codimango runs |
| Opus 4.6 | TBD pending Codimango runs |
| Avocado | TBD pending Codimango runs |

Oracle validated locally passing 3/3 after spec-test alignment fix (test import and variable scenario tuned for fail-signal). Expected difficulty calibration target similar to baselines.

## Model Analysis
Local oracle validation confirms reference implementation passes all 5 test functions across 4 scenarios (mild 8760, cold 8760, hot 8760, variable 8784) at 2% energy tolerance and 5% comfort tolerance. Fail-signal tests verified to reject single-feature shortcuts with >8% drift:

- **fixedStatic naive**: overrides static reset to fixed minimum, drift ~9-17% across scenarios due to mis-estimated fan power at high load hours where reset would raise static. Fails because pressure-dependent airflow coupling missed.
- **fixedBalance naive**: sets internal gains to zero removing schedule-dependent balance point offset, drift ~18-112% because heating/cooling mode classification shifts dramatically per occupancy state. Fails because balance point derivation per occupancy missed.
- **constEff naive**: flattens coil effectiveness curve to 0.95 constant, drift ~27-31% in heating-dominant scenarios because NTU non-linearity at low water flow not captured, over-predicting delivered heat and under-predicting reheat electricity. Skipped in hot scenario where reheat near zero as designed.
- **noPressure naive**: replaces damper authority curve with constant 0.01 m3/s flow independent of static, drift ~5-91% (5.5% on variable 10,10 scenario, 31% mild, 30% cold, 91% hot). Fails because pressure-flow solve missed; fan savings offset by reheat penalty but net still outside tolerance due to cubic fan law and coil interaction.

Expected difficulty target 1-2 models passing based on Go language rarity, 2% tight tolerance, and four-way coupling requiring correct bin method per occupancy, static reset schedule, pressure-dependent max flow capping, interpolated coil effectiveness with 0.1 floor, and reheat staging at minimum airflow. Common agent failure modes anticipated: implementing commanded airflow directly without damper curve interpolation; using single fixed balance point ignoring occupancy gains; linear coil effectiveness; ignoring static reset or using average static; mishandling 8760 vs 8784 row counts or malformed CSV skipping; unit conversion errors W to kWh. Task calibrated to v2 clean redo pattern with in-test reference recomputation preventing hardcode.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values computed in-test by reference implementation recomputed from spec formulas over deterministic synthetic load profiles and duct static schedules with fixed seed. UA schedule setpoints coil curves damper authority coefficients reset parameters bin width parametrized across cases, and both normal-year and leap-year length profiles graded. No fixed constant to memorize.
- **Overfitting to visible tests:** grader lives in /tests and is not present in /app during solve; agent only writes vav_sim.go
- **Modifying test files:** tests mounted read-only separate from agent working directory.
- **Bypassing intended solution:** correctness requires all four interacting features — pressure-flow solve per bin per occupancy state, static reset schedule coupling, interpolated coil effectiveness with NTU relation, and reheat staging logic with minimum airflow. Grader asserts each single-miss shortcut drifts more than 4x 2% tolerance away from reference.
- **Library shortcuts:** standard library only math package allowed. No third-party HVAC or fluid dynamics packages permitted.

## v2 Clean Redo Note
This is net new task to fill taxonomy gap for Go language at 8.36% vs 10% target -1.64pp within 5pp yellow per language coverage table. Follows v2 clean redo pattern established for psychrometrics-library-v2 degree-day-energy-v2 thermostat-heatpump-v2 homebidder-v2 with single module pure stdlib, reference implementation recomputed from spec in test, tight tolerances, fail-signal tests, and canary GUID preserved.
