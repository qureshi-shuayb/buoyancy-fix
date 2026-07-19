## Description
Ultra-hard two-step buoyancy: Step1 basic float/sink/neutral via Archimedes with Tolerance. Step2 extends to prismatic, conical apex-down, frustum in uniform fluid (linear, cbrt, cubic solver) PLUS stratified ocean rho(z)=SurfaceDensity+Gradient*z where buoyant mass is integral ∫rho(z)A(z)dz (quadratic/quartic) requiring A(z) derivation, PLUS hardest compressible dynamics: hydrostatic pressure P(z)=∫rho(z')g dz' = g(S z+0.5 G z²) (0.5 factor trap), bulk-modulus volume V(z)=V0*(1-P/K) clamped to MinVolumeFraction with crush handling, buoyant force rho(z)V(z)g, quadratic drag Fd=0.5 rho Cd Ad v|v| with sign trap v*|v| not v², terminal velocity sqrt(2|Fw-Fb|/(rho Cd Ad)), equilibrium depth solving M=rho(z)V(z) cubic/quadratic via bisection, and time-to-depth via RK4 integration of ODE dv/dt=(Fw-Fb-Fd)/M, dz/dt=v with interpolation, plus concurrent batch with order preservation and race-free. No formulas given, requires deriving pressure integral, compression, drag sign, RK4 steps.

Why naive fails: simple density compare misses Tolerance=1e-9, simple fraction=rho_obj/rho_fluid fails for stratified because buoyant mass is integral not rho*V_sub, prismatic stratified requires solving quadratic 0.5*G*d²+S*d - Mass/A=0 not linear, conical uniform requires deriving non-linear cbrt via similar triangles not linear, frustum uniform requires deriving volume pi*H/3*(R1²+R1R2+R2²) and solving cubic via bisection (linear or cbrt fails for R1!=R2), stratified conical requires quartic S*d³/3+G*d⁴/4 and bisection (cbrt fails for G>0), pressure integral missing 0.5 factor (naive g*S*z gives 100062 vs correct 99081 for S=1000 G=2 depth10), volume compression without clamping gives negative volume, crush handling missing, drag sign using v² instead of v|v| gives wrong direction for upward motion, Euler instead of RK4 fails accuracy test (Euler error >25% vs RK4 dt/10 reference, tolerance ±15%), terminal velocity Cd<=0 should error containing "drag", batch invalid handling, reduction checks G=0 must match uniform within 1e-6 and K→∞ must match stratified (S+Gz)V0=M → (M/V0-S)/G, cylinder R1==R2 linear and cone R1==0 cbrt, concurrent batch must preserve order and pass -race, and remembering prior struct conventions across multi-turn. Removing explicit formula spoilers forces derivation from first principles, raising novelty from textbook recall to HIGH construction.

## Completion Rates
| Model | Step | Pass Rate (of trials reaching this step) | Last Updated |
|---|---|---|---|
| Oracle | 1_basic_float_check | TBD | TBD |
| Oracle | 2_partial_submersion | TBD | TBD |
| meta/avocado | 1_basic_float_check | TBD | TBD |
| meta/avocado | 2_partial_submersion | TBD | TBD |
| anthropic/opus | 1_basic_float_check | TBD | TBD |
| anthropic/opus | 2_partial_submersion | TBD | TBD |

Cascade verdict (this iteration): TBD

## Model Analysis
TBD — will be populated after agent trials.

## Anti-Cheating Analysis
- Hardcoded outputs: many density/mass/radii/S/G/K/Cd combos parameterized; precomputed depths are solutions to quartic/cubic and RK4 integration not simple cbrt; pressure 0.5 factor trap catches naive g*S*z; drag sign trap catches v²; RK4 vs Euler trap with 15% tolerance catches Euler
- Overfitting to visible tests: tests in /tests not visible in /app during solve
- Modifying test files: tests separate, read-only mount
- Bypassing intended solution: must implement true Archimedes plus stratified integral plus compressible pressure integral with 0.5, volume clamped, crush, drag v|v|, terminal sqrt, bisection for equilibrium, RK4 with interpolation for time-to-depth, concurrent batch with WaitGroup+mutex; tests detect linear vs cbrt vs frustum cubic vs stratified quartic vs compressible cubic differences, plus reduction K→∞→(M/V0-S)/G and G=0→uniform

## Notes
Manually scaffolded due to codimango template fetch network error. Structure matches multi-step spec: schema_version 1.1, [[steps]], inherit_prior_session true on step 2. Hardened three times: 1st added frustum cubic solver, 2nd added stratified ocean integral buoyancy quadratic/quartic, 3rd added compressible bulk-modulus P(z)=g(Sz+0.5Gz²) volume V(z)=V0(1-P/K) with crush, quadratic drag Fd=0.5 rho Cd Ad v|v|, terminal velocity, equilibrium bisection, RK4 time-to-depth with interpolation, concurrent batch with -race. No formula spoilers in final instruction.
