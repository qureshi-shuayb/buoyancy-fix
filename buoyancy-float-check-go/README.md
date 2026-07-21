## Description
Bespoke three-step Go package `buoyancy` with concise API contracts (<120 lines per milestone). Distinctive identifiers zero hits in public search.

**Step1 (basic):** `Tolerance=1e-9`, `StandardGravity=9.81`, `Object`, `Fluid`, `CylinderObject` V=πR²H, `SphereObject` V=4/3πr³, `BuoyancyReport`. Functions: `BuoyantForce`, `WeightForce` (use g param), `CheckBuoyancyByDensity` (neutral `|diff|<=Tol`), `CheckBuoyancy`, `ApparentWeight` (tolerance-zeroing →0 when within Tol), `RequiredBallastMass` (same zeroing, `rhoV-Mass`), `BatchCheckBuoyancy` concurrent with WaitGroup+Mutex, order via Index, nil→`make(...,0)`, invalid→State="invalid", overflow post-op IsInf/IsNaN → error.

**Step2 (partial + stratified):** `FrustumObject` R1 bottom R2 top, `StratifiedFluid` S surface density G gradient, `SubmersionResult`. `r(z)=R1+(R2-R1)z/H`, `A(z)=π*r(z)²`, `Vol=πH/3(R1²+R1R2+R2²)`. Uniform: prismatic A=Vol/H linear, conical apex-down `d=H*cbrt(Fraction)` non-linear, frustum bisection. Stratified: `rho(z)=S+G*z`, `BM(d)=∫rho(z)A(z)dz` → prismatic `A(Sd+0.5Gd²)`, conical `πR²/H²(Sd³/3+Gd⁴/4)`, frustum quartic mixing R1,deltaR,S,G with 0.5,1/3,1/4,R1*R2 coefficients. Exported `BuoyantMass`, `BuoyantMassConical`, `Frustum.BuoyantMass` return BM(d) directly within 1e-6. Equilibrium via bisection, `rho_avg=BM(H)/Vol`. Reductions: G=0→uniform 1e-6, R1==R2 linear, R1==0 cone. Batch concurrent WaitGroup+Mutex race-free.

**Step3 (compressible):** `CompressibleObject`, `DiveResult`, `MinimumVolumeFraction=0.1`. `P(z)=g(Sz+0.5Gz²)` (integral), `V(z)=V0(1-P/K)` clamped to Vmin=V0*MinFraction, crush if depth>CrushDepth error "crush", 90% threshold CrushRisk. `Fb=rho(z)V(z)g`, `Ad=V(z)/Height`, drag `Fd=0.5*rho*Cd*Ad*v*|v|` sign via v*|v|, terminal `Fnet=0`, equilibrium `Mass=rho(z)V(z)` bisection, time-to-depth RK4 with Butcher [0,0.5,0.5,1] depth clamped >=0 and interpolation, ±15% vs dt/10. Concurrent batch WaitGroup+Mutex race-free.

## Completion Rates
| Model | Step | Pass Rate | Updated |
|---|---|---|---|
| Oracle | 1_basic | 3/3 (1.0) | 2026-07-20 |
| Oracle | 2_partial | 3/3 (1.0) | 2026-07-20 |
| Oracle | 3_compressible | 3/3 (1.0) | 2026-07-20 |
| avocado-5.14-code (v0.15 763b050) | 1_basic | 15/15 (100%) | before harden |
| avocado-5.14-code (v0.15) | 2_partial | 15/15 (100%) | before harden |
| avocado-5.14-code (v0.15) | 3_compressible | 8/15 (53.3%) | before harden |
| avocado-5.14-code (v0.15) | overall | 8/15 (53.3% in-band too easy) | 2026-07-20 |
| avocado-5.14-code (v0.16 9e3e883 hardened v2) | 1_basic | 3/15 (20%) | 2026-07-20 |
| avocado-5.14-code (v0.16) | 2_partial | 3/3 of those reaching (100% but of 3) | 2026-07-20 |
| avocado-5.14-code (v0.16) | 3_compressible | 0/3 (0%) | 2026-07-20 |
| Expected after super hard v3 | 1_basic | 3-5/15 (20-35%) | target |
| Expected after super hard v3 | 2_partial | 2-4/15 (15-30%) | target |
| Expected after super hard v3 | 3_compressible | 3-6/15 (20-40%) | target |
| Expected overall | overall | 10-25% in-band hard tier | target |

Hardened v2 2026-07-20: Added Cylinder Pi, Sphere 4/3, tolerance-zeroing, batch ordering, overflow, inverse validation, concurrent BatchCheckBuoyancy → Step1 100%→20%. Step2 still 100% → need super hard.

Super hard v3 2026-07-20: 
- Step1: Batch concurrent WaitGroup+Mutex race-free (already) + overflow + Pi + tolerance-zeroing → target 20-35%
- Step2: Added BuoyantMass exported methods exposing polynomial coefficients (0.5,1/3,1/4,R1*R2) within 1e-6, plus concurrent BatchAnalyze with race detector → target 15-30%
- Fixed verbosity: All 3 instructions rewritten from 200-550 lines (2500-4500 words) to 70-86 lines (<900 words), clear API contract (Constants, Types, Functions, Behavior, Error Handling, General), removed Grading Hidden Tests, minimized What NOT to Do, neutral tone, no trap/avocado language.

## Notes
- Instructions now concise per reviewer feedback while keeping hardness via physics derivation and concurrency, not verbose trap descriptions.
- Reference solutions use WaitGroup+Mutex for all batch functions and implement BuoyantMass polynomials directly.
- Tests enforce Pi, 4/3, diameter vs radius, tolerance-zeroing, nil→make, order via Index, overflow IsInf, G=0 reduction 1e-6, R1==R2 linear, R1==0 cone, pressure 0.5 factor, clamping, crush 90%, Ad=V/H, v*|v|, RK4 ±15%, race.
