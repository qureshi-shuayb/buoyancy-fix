# orc-binary-cycle-v1

## Description
Implement Python Organic Rankine Cycle binary geothermal simulation with R245fa pinned property table now provided as CSV file at `/app/r245fa_properties.csv` requiring file IO parsing, preheater evaporator superheater pinch constraint solved via bisection 31 iterations hardened v8 when target UA provided else clamp fallback, turbine and pump efficiencies, LMTD UA sizing with separate UA_sh UA_ev UA_ph UA_recuperator outputs totaling 11 keys including UA_recuperator, recuperator option boolean adding heat exchanger between turbine exhaust and pump outlet, part-load curve off-design evaluation across 11 brine flow fractions explicit [0.15,0.3,0.45,0.6,0.75,0.85,1.0,1.15,1.3,1.45,1.6], and exergy destruction. Deterministic stdlib-only model graded against independent reference across brine temperature, pinch, efficiency, condenser, recuperator enabled, and part-load scenarios; naive implementations omitting bisection, CSV parsing, recuperator branch, part-load loop, LMTD edge handling, property interpolation, or exergy formula fail tightened tolerances v8 to 5e-7 rel 1e-4 abs power UA and 1e-7 for efficiency.

The agent implements `simulate(brine_in_T, brine_mdot, brine_cp, pinch_K, condenser_T, eta_t, eta_p, ..., use_recup=False, target_UA=None)` in `/app/orc_cycle.py` returning dict with `net_power_W`, `thermal_efficiency`, `brine_out_T`, `UA_total`, `exergy_destruction`, `UA_sh`, `UA_ev`, `UA_ph`, `UA_recuperator`, `part_load_curve`, `recuperator_duty`.

The task is calibrated so that naive attempt fails. The hard parts:

1. **R245fa CSV property table with linear interpolation** must read CSV file not hardcode dict, interpolate saturation properties at Pe and Pc. Using constant properties or nearest-neighbor without interpolation fails tolerances by >1% in net power tightened to 5e-7.

2. **Pinch point constraint with bisection 31 iterations** brine_out_T must satisfy UA target via bisection search over bounds [condenser_T+5, brine_in_T-5] when target_UA provided, else fallback clamp to Tsat_e-pinch_K then clamped. Omitting bisection or using closed-form clamp only causes failure in target UA scenario; 31 iterations required for 1e-7 tolerance convergence.

3. **Four-section LMTD UA calculation separate outputs** superheater evaporator preheater recuperator with energy fraction scaling to enforce brine duty exactly, and pinned LMTD formula using max(dT,1e-3) and arithmetic mean fallback. Must output UA_sh UA_ev UA_ph UA_recuperator separately not just total; simplified single UA fails missing keys. UA_recuperator is 0 when use_recup False else UA_total*0.15.

4. **Recuperator option** when use_recup True, add recuperator heat exchanger transferring heat from turbine exhaust to pump outlet with effectiveness 0.8, updating h2, h4, Qin, Wnet, and recuperator_duty output non-zero and UA_recuperator non-zero. Ignoring flag causes recuperator test failure.

5. **Part-load curve** must compute net power for brine_mdot fractions [0.15,0.3,0.45,0.6,0.75,0.85,1.0,1.15,1.3,1.45,1.6] by re-running internal cycle helper, output list length 11. Hardcoding single point fails.

6. **Exergy destruction** using brine exergy drop minus net power with T0=298.15 K log mean. Omitting log term or using wrong reference fails exergy tolerance 5e-7.

7. **Turbine isentropic quality clipping** x4s clipped to [0,1] mandatory for high superheat edge; unclipped produces NaN or negative enthalpy.

Outputs graded against independent reference across fourteen scenarios: base 423K, high 453K, low pinch 3K, high pinch 15K, low eta_t 0.7, high condenser 315K, recuperator enabled, part-load validation, ultra high pressure, low brine flow, target UA, high superheat, ultra low pinch, low pump eta.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 3/3 (validated locally) |
| Sonnet | projected 0/5 after v8 hardening |
| Opus | projected 0/5 |
| Avocado | projected 0/5 |
| GPT | projected 0/5 |

Oracle validated locally with solution/orc_cycle.py against reference in tests/test_outputs.py (14/14 scenarios pass).

## Model Analysis
Task targets hard 0-1% band after v8 hardening (0/5 expected). Successful solutions demonstrate correct CSV file reading and parsing not hardcoded dict, Newton-free but bisection 31 iterations for pinch UA target, property interpolation, pump work via deltaP/rho_l divided by eta_p, turbine isentropic expansion with quality clipping, pinch clamp fallback logic, four-section LMTD with scale factor outputting separate UA_sh UA_ev UA_ph UA_recuperator totaling 11 keys, recuperator energy balance updating h2 and h4 and recuperator_duty output and UA_recuperator=UA_total*0.15, part-load curve loop abstracting cycle into helper with 11 fractions [0.15,0.3,0.45,0.6,0.75,0.85,1.0,1.15,1.3,1.45,1.6], and exergy log formula across 14 scenarios. Failures typically omit CSV parsing hardcoding dict leading to file-not-found or stale values, ignore bisection using only clamp causing UA target mismatch, use 10 or 23 iterations not 31 causing tolerance miss at 5e-7, miss recuperator branch returning zero duty when True expected non-zero or missing UA_recuperator key, return wrong list length 5 or 9 for part_load_curve instead of 11, omit separate UA keys returning only UA_total, mis-implement LMTD edge case without max 1e-3, hardcode properties instead of interpolating, or mis-handle turbine efficiency sign leading to negative net power. Pinned constants rho_l=1300, cp_v=800, superheat default 10, epsilon 0.8 for recuperator ensure deterministic composition.

## Anti-Cheating Analysis
- **Hardcoded outputs**: Tests use continuous physical parameters across fourteen scenarios with tightened 5e-7 relative tolerance 1e-4 absolute for power and UA, 1e-7 for efficiency brine_out_T; precomputed answers cannot match without implementing full model including bisection 31 and recuperator UA.
- **Overfitting to visible tests**: Test inputs parameterized across base, high temperature, low/high pinch, low turbine efficiency, high condenser, recuperator enabled, part-load covering edge cases; grader evaluates exact pinned formulas.
- **Modifying test files**: Tests mounted read-only at /tests/; test.sh applies chmod 700 defense during pytest similar to pwr-primary-loop-v2 precedent.
- **Bypassing intended solution path**: Tests verify eleven outputs including separate UA components including UA_recuperator, part-load list length 11, recuperator duty not just net power; stdlib-only check enhanced to detect dynamic imports via __import__ and importlib to prevent CoolProp bypass, now allows csv module as stdlib. Agent file must exist at /app/orc_cycle.py and CSV at /app/r245fa_properties.csv.
- **Spec alignment**: Instruction pins CSV file path, interpolation method, bisection 31 iterations, pump formula, turbine quality clipping, pinch clamp bounds fallback, LMTD formula, UA sum and separate outputs including UA_recuperator, recuperator effectiveness 0.8, part-load fractions list 11 values, exergy T0=298.15, tolerances rel 5e-7 abs 1e-4 for power UA and 1e-7 for efficiency brine_out_T. Implementation must follow order for determinism.
- **Novelty**: ORC binary geothermal with R245fa CSV, bisection pinch 31, recuperator UA, 11-fraction part-load is novel composition not matching public benchmarks; contamination risk MEDIUM per internal reasoning as specific pinned table and LMTD four-section split plus recuperator branch is bespoke.

<!-- v8 hardening to target 0% band with oracle 3/3 projected 0/5 addressing AI Revise as of 2026-07-06 -->
