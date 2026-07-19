## Description
Three-step buoyancy - designed for proper multi-turn gradient:

**Step1 Easy (1_basic_float_check):** Basic float/sink/neutral via Archimedes with Tolerance=1e-9. Oracle should be 100%, Avocado 4/5 - explicit formula given `|rho_obj - rho_fluid| <= Tol => neutral`, plus examples. Provides reusable types for later steps.

**Step2 Medium (2_partial_submersion):** Uniform fluid prismatic, conical apex-down, frustum in uniform fluid (linear, cbrt, cubic solver) PLUS stratified ocean rho(z)=SurfaceDensity+Gradient*z where buoyant mass is integral ∫rho(z)A(z)dz (quadratic for prismatic, quartic for conical/frustum). Requires A(z) derivation, bisection, reduction G=0 → uniform within 1e-6. Medium difficulty to allow Opus 5/5, Avocado 3/4.

**Step3 Hard (3_compressible_dynamics):** Hardest compressible dynamics: hydrostatic pressure P(z)=∫rho(z')g dz' = g(S z+0.5 G z²) (0.5 factor trap), bulk-modulus volume V(z)=V0*(1-P/K) clamped to MinVolumeFraction 0.1 with crush handling, buoyant force rho(z)V(z)g, quadratic drag Fd=0.5 rho Cd Ad v|v| with sign trap v*|v| not v², terminal velocity sqrt(2|Fw-Fb|/(rho Cd Ad)), equilibrium depth solving M=rho(z)V(z) cubic/quadratic via bisection, and time-to-depth via RK4 integration of ODE dv/dt=(Fw-Fb-Fd)/M, dz/dt=v with interpolation, plus concurrent batch with order preservation and race-free. This step can be 0/3 for Avocado while Opus is 5/5 (allowed pattern: Avocado has fail on every step and task passes on Opus).

Why naive fails: simple density compare misses Tolerance, simple fraction=rho_obj/rho_fluid fails for stratified because buoyant mass is integral not rho*V_sub, prismatic stratified requires solving quadratic 0.5*G*d²+S*d - Mass/A=0 not linear, conical uniform requires cbrt via similar triangles not linear, frustum uniform requires cubic bisection, stratified conical requires quartic, pressure integral missing 0.5 factor (naive g*S*z gives 100062 vs correct 99081 for S=1000 G=2 depth10), volume compression without clamping gives negative volume, crush handling missing, drag sign using v² instead of v|v|, Euler instead of RK4 fails accuracy test (Euler error >25% vs RK4 dt/10, tolerance ±15%), batch order, race, reductions.

This split from previous 2-step ultra-hard (0/10 for all non-Oracle) to 3-step provides learning gradient per official multi-turn pass-rate rules: each step needs at least one pass on Avocado/Opus/GPT and at least one fail on Avocado, overall task needs at least one pass and one fail.

## Completion Rates
| Model | Step | Pass Rate (of trials reaching this step) | Last Updated |
|---|---|---|---|
| Oracle | 1_basic_float_check | 3/3 (1.0) - too easy expected | 2026-07-19 |
| Oracle | 2_partial_submersion | 3/3 (1.0) - too easy expected | 2026-07-19 |
| Oracle | 3_compressible_dynamics | 3/3 (1.0) | TBD after split |
| meta/avocado | 1_basic_float_check | TBD - target 4/5 (0.8) | TBD |
| meta/avocado | 2_partial_submersion | TBD - target 3/4 (0.75) | TBD |
| meta/avocado | 3_compressible_dynamics | TBD - target 0/3 or 2/3 (gradient) | TBD |
| anthropic/opus | 1_basic_float_check | TBD - target 5/5 (1.0) | TBD |
| anthropic/opus | 2_partial_submersion | TBD - target 5/5 (1.0) | TBD |
| anthropic/opus | 3_compressible_dynamics | TBD - target 5/5 (1.0) | TBD |
| gpt-5.5 | 1_basic_float_check | TBD - target 5/5 | TBD |
| gpt-5.5 | 2_partial_submersion | TBD | TBD |
| gpt-5.5 | 3_compressible_dynamics | TBD | TBD |

Cascade verdict (previous 2-step iteration): Oracle 100% (too easy) + Avocado/Opus/GPT 0/10 (too hard) = FAIL - no gradient, now fixed by 3-step split.

## Model Analysis
TBD — will be populated after re-running codimango with new 3-step structure. Expected: Step1 easy should be 100% for strong models, Step2 medium should show Avocado gradient (some fail on frustum cubic or stratified quartic), Step3 hard should show Opus solving compressible while Avocado 0/3, matching Pass — Avocado has fail on every step and task passes on Opus.

## Anti-Cheating Analysis
- Hardcoded outputs: many density/mass/radii/S/G/K/Cd combos parameterized; precomputed depths are solutions to quartic/cubic and RK4 integration not simple cbrt; pressure 0.5 factor trap catches naive g*S*z; drag sign trap catches v²; RK4 vs Euler trap with 15% tolerance catches Euler
- Overfitting to visible tests: tests in /tests not visible in /app during solve
- Modifying test files: tests separate, read-only mount
- Bypassing intended solution: must implement true Archimedes plus stratified integral plus compressible pressure integral with 0.5, volume clamped, crush, drag v|v|, terminal sqrt, bisection for equilibrium, RK4 with interpolation for time-to-depth, concurrent batch with WaitGroup+mutex; tests detect linear vs cbrt vs frustum cubic vs stratified quartic vs compressible cubic differences, plus reduction K→∞→(M/V0-S)/G and G=0→uniform

## Notes
Refactored from 2-step ultra-hard (b454446) to 3-step on 2026-07-19. Step1 basic float/sink/neutral now easier with explicit formula, Step2 now only uniform+stratified (medium) to allow Opus 5/5, Step3 now isolated compressible dynamics (hard) to allow Avocado 0/3 + Opus 5/5 passing pattern per multi-turn rules: each step needs at least one pass on Avocado/Opus/GPT and at least one fail on Avocado, no 1.0 Avocado step in 3-step task.
