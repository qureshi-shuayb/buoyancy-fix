# orc-binary-cycle-v1

## Description
Implement Python Organic Rankine Cycle binary geothermal simulation with R245fa pinned property table now provided as CSV file at `/app/r245fa_properties.csv` requiring file IO parsing, preheater evaporator superheater pinch constraint solved via bisection 10 iterations when target UA provided else clamp fallback, turbine and pump efficiencies, LMTD UA sizing with separate UA_sh UA_ev UA_ph outputs, recuperator option boolean adding heat exchanger between turbine exhaust and pump outlet, part-load curve off-design evaluation across 5 brine flow fractions, and exergy destruction. Deterministic stdlib-only model graded against independent reference across brine temperature, pinch, efficiency, condenser, recuperator enabled, and part-load scenarios; naive implementations omitting bisection, CSV parsing, recuperator branch, part-load loop, LMTD edge handling, property interpolation, or exergy formula fail tightened tolerances.

The agent implements `simulate(brine_in_T, brine_mdot, brine_cp, pinch_K, condenser_T, eta_t, eta_p, ..., use_recup=False, target_UA=None)` in `/app/orc_cycle.py` returning dict with `net_power_W`, `thermal_efficiency`, `brine_out_T`, `UA_total`, `exergy_destruction`, `UA_sh`, `UA_ev`, `UA_ph`, `part_load_curve`, `recuperator_duty`.

The task is calibrated so that naive attempt fails. The hard parts:

1. **R245fa CSV property table with linear interpolation** must read CSV file not hardcode dict, interpolate saturation properties at Pe and Pc. Using constant properties or nearest-neighbor without interpolation fails tolerances by >1% in net power tightened to 1e-2.

2. **Pinch point constraint with bisection 10 iterations** brine_out_T must satisfy UA target via bisection search over bounds [condenser_T+5, brine_in_T-5] when target_UA provided, else fallback clamp to Tsat_e-pinch_K then clamped. Omitting bisection or using closed-form clamp only causes failure in target UA scenario.

3. **Three-section LMTD UA calculation separate outputs** superheater evaporator preheater with energy fraction scaling to enforce brine duty exactly, and pinned LMTD formula using max(dT,1e-3) and arithmetic mean fallback. Must output UA_sh UA_ev UA_ph separately not just total; simplified single UA fails missing keys.

4. **Recuperator option** when use_recup True, add recuperator heat exchanger transferring heat from turbine exhaust to pump outlet with effectiveness 0.8, updating h2, h4, Qin, Wnet, and recuperator_duty output non-zero. Ignoring flag causes recuperator test failure.

5. **Part-load curve** must compute net power for brine_mdot fractions [0.6,0.8,1.0,1.1,1.2] by re-running internal cycle helper, output list length 5. Hardcoding single point fails.

6. **Exergy destruction** using brine exergy drop minus net power with T0=298.15 K log mean. Omitting log term or using wrong reference fails exergy tolerance.

7. **Turbine isentropic quality clipping** x4s clipped to [0,1] mandatory for high superheat edge; unclipped produces NaN or negative enthalpy.

Outputs graded against independent reference across ten scenarios: base 423K, high 453K, low pinch 3K, high pinch 15K, low eta_t 0.7, high condenser 315K, recuperator enabled, part-load validation.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 3/3 (validated locally) |
| Sonnet 4.6 | TBD pending cloud re-run after v6 hardening |
| Opus 4.6 | TBD |
| Avocado (metacode) | TBD |

Oracle validated locally with solution/orc_cycle.py against reference in tests/test_outputs.py (8/8 scenarios pass).

## Model Analysis
Task targets hard 0-2% band after v6 hardening (0-1/5 expected). Successful solutions demonstrate correct CSV file reading and parsing not hardcoded dict, Newton-free but bisection 10 iterations for pinch UA target, property interpolation, pump work via deltaP/rho_l divided by eta_p, turbine isentropic expansion with quality clipping, pinch clamp fallback logic, three-section LMTD with scale factor outputting separate UA_sh UA_ev UA_ph, recuperator energy balance updating h2 and h4 and recuperator_duty output, part-load curve loop abstracting cycle into helper, and exergy log formula. Failures typically omit CSV parsing hardcoding dict leading to file-not-found or stale values, ignore bisection using only clamp causing UA target mismatch, miss recuperator branch returning zero duty when True expected non-zero, return wrong list length for part_load_curve, omit separate UA keys returning only UA_total, mis-implement LMTD edge case without max 1e-3, hardcode properties instead of interpolating, or mis-handle turbine efficiency sign leading to negative net power. Pinned constants rho_l=1300, cp_v=800, superheat default 10, epsilon 0.8 for recuperator ensure deterministic composition.

## Anti-Cheating Analysis
- **Hardcoded outputs**: Tests use continuous physical parameters across ten scenarios with tightened 5e-3 relative tolerance 0.1 absolute for power and UA, 1e-3 for efficiency brine_out_T; precomputed answers cannot match without implementing full model including bisection and recuperator.
- **Overfitting to visible tests**: Test inputs parameterized across base, high temperature, low/high pinch, low turbine efficiency, high condenser, recuperator enabled, part-load covering edge cases; grader evaluates exact pinned formulas.
- **Modifying test files**: Tests mounted read-only at /tests/; test.sh applies chmod 700 defense during pytest similar to pwr-primary-loop-v2 precedent.
- **Bypassing intended solution path**: Tests verify ten outputs including separate UA components, part-load list, recuperator duty not just net power; stdlib-only check enhanced to detect dynamic imports via __import__ and importlib to prevent CoolProp bypass, now allows csv module as stdlib. Agent file must exist at /app/orc_cycle.py and CSV at /app/r245fa_properties.csv.
- **Spec alignment**: Instruction pins CSV file path, interpolation method, bisection 10 iterations, pump formula, turbine quality clipping, pinch clamp bounds fallback, LMTD formula, UA sum and separate outputs, recuperator effectiveness 0.8, part-load fractions list, exergy T0=298.15, tolerances rel 1e-2 abs 0.1 for power UA and 1e-3 for efficiency brine_out_T. Implementation must follow order for determinism.
- **Novelty**: ORC binary geothermal with R245fa CSV, bisection pinch, recuperator, part-load is novel composition not matching public benchmarks; contamination risk MEDIUM per internal reasoning as specific pinned table and LMTD three-section split plus recuperator branch is bespoke.

<!-- v6 hardening to target 0-2% band with oracle 3/3 validated locally addressing AI Revise as of 2026-07-05 -->
