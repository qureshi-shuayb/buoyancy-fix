## Description
Two-step buoyancy task with hardening far beyond textbook: Step1 basic float/sink/neutral via Archimedes. Step2 extends to prismatic, conical apex-down, and frustum (bucket) in UNIFORM fluid PLUS hardest extension to STRATIFIED ocean where density rho(z)=SurfaceDensity+Gradient*z varies linearly with depth, so buoyant mass is integral ∫rho(z)*A(z)dz (quadratic for prismatic, quartic for conical/frustum) requiring derivation of cross-sectional area A(z) and numeric root-finding (bisection). This pushes beyond density-ratio mnemonic to genuine construction. Plus batch processing with invalid marking, reduction property Gradient=0 → uniform, cylinder/cone reductions, and go vet. Tests buoyancy physics with context-following, geometry derivation, integral buoyancy, and numerical methods.

Why naive fails: simple density compare misses Tolerance=1e-9, simple fraction=rho_obj/rho_fluid fails for stratified because buoyant mass is integral not rho*V_sub, prismatic stratified requires solving quadratic 0.5*G*d²+S*d - Mass/A=0 not linear, conical uniform requires deriving non-linear cbrt via similar triangles not linear, frustum uniform requires deriving volume pi*H/3*(R1²+R1R2+R2²) and solving cubic via bisection (linear or cbrt fails for R1!=R2), stratified conical requires quartic S*d³/3+G*d⁴/4 and bisection (cbrt fails for G>0), stratified frustum requires quartic with R1,R2 and bisection, batch invalid handling, reduction checks G=0 must match uniform within 1e-6, cylinder R1==R2 linear and cone R1==0 cbrt, and remembering prior struct conventions across multi-turn. Removing explicit formula spoilers forces derivation from first principles, raising novelty from textbook recall to construction.

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
- Hardcoded outputs: many density/mass/radii combos parameterized plus stratified S/G combos, not in repo; precomputed depths are solutions to quartic not simple cbrt
- Overfitting to visible tests: tests in /tests not visible in /app during solve
- Modifying test files: tests separate, read-only mount
- Bypassing intended solution: must implement true Archimedes plus stratified integral and quartic solver; tests detect linear vs cbrt vs frustum cubic vs stratified quartic differences, plus reduction G=0 → uniform

## Notes
Manually scaffolded due to codimango template fetch network error. Structure matches multi-step spec: schema_version 1.1, [[steps]], inherit_prior_session true on step 2. Hardened twice: first added frustum cubic solver, second added stratified ocean integral buoyancy with quadratic/quartic numeric root-finding to address MEDIUM novelty / TOO EASY. No formula spoilers in final instruction.
