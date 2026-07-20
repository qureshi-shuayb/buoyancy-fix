## Description
Three-step **bespoke Go package `buoyancy`** with package-defined conventions (not generic textbook) and increasing difficulty. Distinctive identifiers `FrustumObject`, `StratifiedFluid`, `DiveResult`, `MinimumVolumeFraction`, `CrushDepth`, `CompressibleObject`, `SubmersionResult` returned **zero hits** in public Go package search during novelty check, confirming novel composition.

**Step1 (1_basic_float_check):** Package-defined float/sink/neutral with tolerance-aware neutral boundary `|rho_obj - rho_fluid| <= Tolerance` where `Tolerance=1e-9` must be referenced via constant (AST check, not hardcoded). Object vs fluid density comparison provides reusable types `Object`, `Fluid` for later steps. Package-specific traps: Height field validation for later A(z) derivation, error substring contract, `g` param usage (Mars 3.7 test catches hardcoded 9.81), large number handling (5e8, 1e12), tolerance boundaries 0.9*Tol vs 1.1*Tol. Bespoke package invariant, not generic Archimedes tutorial.

**Step2 (2_partial_submersion):** Uniform fluid prismatic (constant A=Vol/Height), conical apex-down (similar cones, non-linear depth via `d=H*cbrt(fraction)`, not linear), frustum bucket (R1 bottom, R2 top, package-defined linear radius interpolation `r(z)=R1+(R2-R1)*z/H`, cubic Volume=πH/3*(R1^2+R1R2+R2^2) via monotonic root-finding) PLUS stratified ocean where density `rho(z)=S+G*z` package-defined linear, buoyant mass integral `BM(d)=∫rho(z)A(z)dz` requiring derivation of `A(z)` per shape (prismatic constant, conical via similar triangles ∝z^2, frustum via linear r(z) → πr(z)^2). Per-shape BM(d) yields polynomial orders: quadratic for prismatic (S*d+0.5*G*d^2), cubic+quartic for conical (S*d^3/3+G*d^4/4), quartic mixing R1/deltaR/S/G for frustum. Bespoke reduction invariants: `G=0→uniform` within 1e-6, `R1==R2` cylinder linear, `R1==0` cone, monotonicity, nil→non-nil empty slice via explicit `make(...,0)` Go idiom, order preservation via Index field.

**Step3 (3_compressible_dynamics):** Compressible dynamics with hydrostatic pressure derived from density integral `P(z)=∫rho(z')g dz' = g*(S*z+0.5*G*z^2)` (must include 0.5 factor, discriminates naive `rho*g*z`), bulk-modulus linear compression `V(z)=V0*(1-P/K)` clamped to `MinimumVolumeFraction=0.1` with package constant reference requirement (AST check, not hardcoded 0.1), crush depth handling with 90% threshold (`depth>=0.9*CrushDepth` → CrushRisk=true, State="crush") and 'crush' error substring, buoyant force `rho(z)V(z)g`, quadratic drag opposing motion with **bespoke reference area `Ad(z)=V(z)/Height`** (not standard cross-section) and sign handling via `v*|v|`, terminal velocity from `Fnet=0` with sign matching `Fw-Fb`, equilibrium depth solving `M=rho(z)V(z)` via bisection with tolerance param, and time-to-depth via 4th-order weighted incremental integration (classic RK4 with Butcher [0,0.5,0.5,1] but with package-specific depth clamping during sub-steps to avoid negative depth errors) and linear interpolation. Concurrent batch `BatchFindEquilibrium` and `BatchTimeToDepthConcurrent` with order preservation, explicit nil→non-nil empty slice, race-free `sync.WaitGroup`+`sync.Mutex`, `go test -race` must pass. Reductions: `K→∞` approaches stratified incompressible, `G=0+K→∞` approaches uniform.

Why naive implementations fail: simple density equality misses tolerance boundary tests (0.9*Tol vs 1.1*Tol); simple `fraction=rho_obj/rho_fluid` fails for stratified because buoyant mass is integral not `rho*V_sub`; conical requires non-linear `cbrt` not linear; frustum requires cubic bisection; stratified requires deriving `A(z)` and integrating `rho(z)A(z)` yielding up to quartic; pressure integral requires 0.5 factor (tests discriminate >1% error); volume compression without clamping gives negative volume and missing `MinimumVolumeFraction` constant reference fails AST; crush handling missing 90% threshold; drag sign without `v*|v|` fails sign tests; Euler instead of RK4 fails accuracy test (Euler error >25% vs RK4 dt/10, tolerance ±15%); batch missing nil→non-nil empty fails; missing WaitGroup+Mutex fails race.

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

Oracle fixed 2026-07-19: added explicit nil→non-nil empty slice handling to all Batch* functions (`if objs==nil { return make(...,0), nil }`) per package Go idiom, fixed vet self-assignment, ensured `MinimumVolumeFraction` constant reference via `packageMin := V0*MinimumVolumeFraction` clamping.

## Model Analysis
TBD — will be populated after re-running codimango with updated instructions. Novelty revision 2026-07-19: reframed all three steps as package-defined conventions (not textbook Archimedes/RK4/bisection recall), emphasized bespoke invariants: Tolerance constant reference, MinimumVolumeFraction constant reference, Ad=V/H reference area, crush 90% threshold, nil→non-nil empty slice, order preservation via Index, WaitGroup+Mutex race-free, per-shape A(z) derivation yielding quartic, pressure integral 0.5 factor discrimination, G=0→uniform and R1==R2/R1==0 reductions, K→∞ reduction. Distinctive type names zero hits in public search. This shifts Check2 from MEDIUM (building blocks recallable) to LOW (integration requires genuine derivation beyond building blocks).

## Anti-Cheating Analysis
- Hardcoded outputs: many density/mass/radii/S/G/K/Cd combinations parameterized; depths are solutions to non-linear cubic/quartic equations and RK4 integration with interpolation, not simple lookups; pressure integration correctness via 0.5 factor check, drag sign via v*|v|, RK4 accuracy gating ±15% vs dt/10
- Overfitting to visible tests: tests in /tests not visible in /app during solve; hidden tests include tolerance boundaries 0.9*Tol vs 1.1*Tol, non-linearity traps, reduction G=0→uniform 1e-6, R1==R2 cylinder, R1==0 cone, K→∞, crush 90%, nil→non-nil empty, race
- Modifying test files: tests separate, read-only mount; vet and race checks
- Bypassing intended solution: must implement package-defined tolerance with constant reference, Height validation, derive A(z) for each geometry, integrate rho(z)A(z) per shape (quadratic/cubic/quartic), derive pressure integral with 0.5 factor, implement compression with MinimumVolumeFraction constant reference and clamping and crush 90%, drag with Ad=V/H and proper sign handling via v*|v|, bisection-like monotonic root-finding for equilibrium, 4th-order weighted integration with depth clamping during sub-steps and interpolation, concurrent batch with WaitGroup+Mutex and order preservation and nil handling; tests detect linear vs non-linear, reduction invariants, race conditions, error substrings (crush, drag, depth, gravity, dt, target)

## Notes
Refactored from 2-step ultra-hard to 3-step on 2026-07-19 for better multi-turn gradient. Step1 basic float/sink/neutral with package Tolerance invariant, Step2 uniform+stratified with per-shape integral derivation, Step3 compressible dynamics with bespoke Ad=V/H, MinimumVolumeFraction constant, crush 90%, and concurrent batch. Novelty-risk revision 2026-07-19: added package-defined framing, emphasized zero-hit distinctive identifiers, added MinimumVolumeFraction constant reference requirement, Ad=V/H bespoke definition, and explicit nil handling to push MEDIUM→LOW.
