## Description
Three-step buoyancy physics task in Go with increasing difficulty:

**Step1 (1_basic_float_check):** Basic float/sink/neutral via Archimedes principle with tolerance handling. Object vs fluid density comparison with Tolerance=1e-9 for neutral boundary. Provides reusable types Object, Fluid for later steps.

**Step2 (2_partial_submersion):** Uniform fluid prismatic (constant cross-section), conical apex-down (similar cones, non-linear depth), frustum bucket (R1 bottom, R2 top, linear radius interpolation, cubic via bisection) PLUS stratified ocean where density varies linearly with depth. Buoyant mass is integral BM(d)=∫rho(z)A(z)dz requiring derivation of A(z) for each geometry. Reduction property G=0 must equal uniform within 1e-6.

**Step3 (3_compressible_dynamics):** Compressible dynamics with hydrostatic pressure derived from density integral, bulk-modulus volume compression clamped to MinimumVolumeFraction 0.1 with crush depth handling, buoyant force rho(z)V(z)g, quadratic drag opposing motion with reference area Ad=V(z)/Height, terminal velocity from Fnet=0, equilibrium depth solving M=rho(z)V(z) via bisection, and time-to-depth via classic RK4 integration of coupled ODE with interpolation. Concurrent batch with order preservation and race-free implementation using WaitGroup+mutex. Reduction K→∞ approaches stratified incompressible.

Why naive implementations fail: simple density equality misses tolerance boundary tests; simple fraction=rho_obj/rho_fluid fails for stratified because buoyant mass is integral not rho*V_sub; conical requires non-linear relation (cbrt for uniform) not linear; frustum requires cubic bisection; stratified requires deriving A(z) and integrating rho(z)A(z); pressure integral requires proper derivation; volume compression without clamping gives negative volume; crush handling missing; drag sign without proper opposing-motion handling; Euler instead of RK4 fails accuracy test (Euler error >25% vs RK4 dt/10, tolerance ±15%).

## Completion Rates
| Model | Step | Pass Rate (of trials reaching this step) | Last Updated |
|---|---|---|---|
| Oracle | 1_basic_float_check | 3/3 (1.0) | 2026-07-19 |
| Oracle | 2_partial_submersion | 3/3 (1.0) | 2026-07-19 |
| Oracle | 3_compressible_dynamics | 3/3 (1.0) | 2026-07-19 |
| meta/avocado | 1_basic_float_check | TBD | TBD |
| meta/avocado | 2_partial_submersion | TBD | TBD |
| meta/avocado | 3_compressible_dynamics | TBD | TBD |
| anthropic/opus | 1_basic_float_check | TBD | TBD |
| anthropic/opus | 2_partial_submersion | TBD | TBD |
| anthropic/opus | 3_compressible_dynamics | TBD | TBD |
| gpt-5.5 | 1_basic_float_check | TBD | TBD |
| gpt-5.5 | 2_partial_submersion | TBD | TBD |
| gpt-5.5 | 3_compressible_dynamics | TBD | TBD |

## Model Analysis
TBD — will be populated after re-running codimango with updated instructions.

## Anti-Cheating Analysis
- Hardcoded outputs: many density/mass/radii/S/G/K/Cd combinations parameterized; depths are solutions to non-linear equations and RK4 integration, not simple lookups; pressure integration correctness, drag sign, RK4 accuracy with 15% tolerance
- Overfitting to visible tests: tests in /tests not visible in /app during solve
- Modifying test files: tests separate, read-only mount
- Bypassing intended solution: must implement Archimedes with tolerance, derive A(z) for each geometry, integrate rho(z)A(z) for stratified, derive pressure from integral, implement compression with clamping and crush, drag with proper sign handling, bisection for equilibrium, RK4 with interpolation, concurrent batch with WaitGroup+mutex; tests detect linear vs non-linear, reduction properties, race conditions

## Notes
Refactored from 2-step ultra-hard to 3-step on 2026-07-19 for better multi-turn gradient. Step1 basic float/sink/neutral, Step2 uniform+stratified, Step3 compressible dynamics.
