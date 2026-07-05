# orc-binary-cycle-v1

## Description
Implement Python Organic Rankine Cycle binary geothermal simulation with R245fa pinned property table, preheater evaporator superheater pinch constraint, turbine and pump efficiencies, LMTD UA sizing, and exergy destruction. Deterministic stdlib-only model graded against independent reference across brine temperature, pinch, efficiency, and condenser scenarios; naive implementations omitting pinch clamp, LMTD edge handling, property interpolation, or exergy formula fail tolerances.

The agent implements `simulate(brine_in_T, brine_mdot, brine_cp, pinch_K, condenser_T, eta_t, eta_p, ...)` in `/app/orc_cycle.py` returning dict with `net_power_W`, `thermal_efficiency`, `brine_out_T`, `UA_total`, `exergy_destruction`.

The task is calibrated so that naive attempt fails. The hard parts:

1. **R245fa pinned property table with linear interpolation** must interpolate saturation properties at Pe and Pc from exact dictionary in spec. Using constant properties or nearest-neighbor without interpolation fails tolerances by >3% in net power.

2. **Pinch point constraint with clamps** brine_out_T = Tsat_e - pinch_K then clamped to [condenser_T+5, brine_in_T-5]. Omitting clamps causes non-physical negative Q_brine in high pinch or high condenser scenarios.

3. **Three-section LMTD UA calculation** superheater evaporator preheater with energy fraction scaling to enforce brine duty exactly, and pinned LMTD formula using max(dT,1e-3) and arithmetic mean fallback. Simplified single UA or wrong temperature differences drift UA_total outside 3% tolerance.

4. **Exergy destruction** using brine exergy drop minus net power with T0=298.15 K log mean. Omitting log term or using wrong reference fails exergy tolerance.

5. **Turbine isentropic quality clipping** x4s clipped to [0,1] mandatory for high superheat edge; unclipped produces NaN or negative enthalpy.

Outputs graded against independent reference across six scenarios: base 423K, high 453K, low pinch 3K, high pinch 15K, low eta_t 0.7, high condenser 315K.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 3/3 (validated locally) |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado (metacode) | TBD |

Oracle validated locally with solution/orc_cycle.py against reference in tests/test_outputs.py (6/6 scenarios pass).

## Model Analysis
Task targets ideal 2-3/5 calibration band. Successful solutions demonstrate correct R245fa table interpolation, pump work via deltaP/rho_l divided by eta_p, turbine isentropic expansion with quality clipping, pinch clamp logic, three-section LMTD with scale factor, and exergy log formula. Failures typically omit pinch clamp, use single-section UA, mis-implement LMTD edge case without max 1e-3, hardcode properties instead of interpolating, or mis-handle turbine efficiency sign leading to negative net power. Pinned constants rho0 not used here but rho_l=1300, cp_v=800, superheat default 10 ensure deterministic composition.

## Anti-Cheating Analysis
- **Hardcoded outputs**: Tests use continuous physical parameters across six scenarios with 3% relative tolerance tight enough to reject memorized constants; precomputed answers cannot match without implementing full model.
- **Overfitting to visible tests**: Test inputs parameterized across base, high temperature, low/high pinch, low turbine efficiency, high condenser covering edge cases; grader evaluates exact pinned formulas.
- **Modifying test files**: Tests mounted read-only at /tests/; test.sh applies chmod 700 defense during pytest similar to pwr-primary-loop-v2 precedent.
- **Bypassing intended solution path**: Tests verify five outputs not just net power; stdlib-only check enhanced to detect dynamic imports via __import__ and importlib to prevent CoolProp bypass. Agent file must exist at /app/orc_cycle.py.
- **Spec alignment**: Instruction pins R245fa dictionary, interpolation method, pump formula, turbine quality clipping, pinch clamp bounds, LMTD formula, UA sum, exergy T0=298.15, tolerances rel 3e-2 abs 1.0 for power UA exergy and 1e-3 for efficiency and brine_out_T. Implementation must follow order for determinism.
- **Novelty**: ORC binary geothermal with R245fa table is novel composition not matching public benchmarks; contamination risk LOW per internal reasoning as specific pinned table and LMTD three-section split is bespoke.
