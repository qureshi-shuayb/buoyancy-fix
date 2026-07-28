## Description – EASY v5 (12 consts, 3-term density, 1 finder SOFAR 100pts, target 5/10 passes) + R05/R08 fixes

**Step1 EASY – 12 constants, 3-term density, 3-term pressure, 1st derivative only, 1 finder SOFAR, 200-350 lines, target 5/10 passes (50%):**

- **12 consts** (vs 15,24,34,44): `Tolerance 1e-9, StandardGravity 9.81, StandardSeawaterDensity 1025, DepthDensityGradient 0.02, MinimumVolumeFraction 0.1, PycnoclineDelta 10/Scale 200, HaloclineDelta 2.5/Scale 30, ThermoclineScale 120, SalinityCoeff 0.8, BulkModulus 2.2e9`. Removed Deep 4.5/45, Mid 7/90, Cab 0.06, HullExp 2e-4, Viscosity 0.001, HullQuad 1.2e-6, SoundQuad 1.2e-5, Thermobaric 0.5, ThermalCoupling 0.15, Gamma 0.0001, Tquad 0.002, Squad 0.01, SecondOrder, Triple, Thermo/Halo/Vort, PressureNonLinear, Quadruple, Compensated, etc.
- **Density 3 terms** (vs 5): `rho0 + grad*z + pyc1` where `pyc1=10*(1-exp(-z/200))`. No `beta*s`, no `gamma*t`, no cab, no quad. rho(0)=rho0 monotonic inc, no diff check needed – just increase.
- **Pressure 3 terms** (vs 5): `g*(rho0*z +0.5*grad*z² +10*(z+200*exp(-z/200)-200))` only `integralOneMinusExp` needed, no product, no squared, no z*exp. Simpson **20k rel 1e-2 missing >2** (was 50k 1e-3 >5, 100k 1e-4 >10) extremely loose/fast.
- **Derivatives 1st only** vs 2nd: `drho/dz=grad+PycDelta/Scale*exp(-z/Scale)` 2 terms, tol **1e-4** (was 1e-6) looser.
- **Sound 3 terms** vs 4: `c=1449.2+4.6*T+0.016*z` where `T=15-12*(1-exp(-z/120))`. Checks c0>c200 and c1500>c200 still holds (minimum). Gradient `4.6dT+0.016` 2 terms.
- **Potential temp 1st order** `theta=T*(1 - x)` where `x=P/Bulk*1e-3`, surface 15 <=T.
- **BuoyancyFrequency simple** `N²=g/rho*drho/dz` no acoustic correction.
- **Finders 1 vs 2**: only `FindSOFARAxis` via **100 pts scan** (was 500) + **50 iter ternary** (was 80) no Brent, brute 2m within **10m** (was 5m, was 3m).
- **Methods ~12 vs 14**: core ocean + sound + 1 finder + pressure + volume simple no thermal.

**Step2 MEDIUM – eased further + R05/R08 fixes kept:**

- **R05 leak:** `test.sh` rm `*_test.go` + `ast_check*.go` before AND after verifier.
- **R08 atomic:** accepts any `Add/AddInt32/64/Uint32/64, Load*, Store*, CAS, Swap*` + typed `atomic.Int32/Int64/Uint32/64` – instruction says any valid style.
- **Cd:** 10-pt → **5-pt** `[1e3,1e4,1e5,1e6,5e6]` Cd `[1.44,1.2,0.7,0.2,0.12]` band 0.1 midpoint 0.05.
- **Terminal:** 50 iter 1e-2, **Equilibrium:** 500 pts 50 iter root tol 5m, **TimeToDepth:** fixed RK4 k1..k4 + optional adaptive atol/rtol/errorEstimate, ref **25% rel** (was 15%), **DiveProfile** len>3 depth tol 5%, **deadline 500ms/50items lenient**, **cancel 200ms/50items lenient**, max concurrency <=4 behavioral.

**Completion Rates (oracle v5):**
- Oracle step1: 100% (12 consts, 3-term, 1st deriv, 1 finder 100pts)
- Oracle step2: 100% (5-pt Cd, 500pts eq, fixed RK4, heap+atomic any width)

**Why v5 should hit 5/10:**
- Eliminates all 3-scale and 2-scale product integrals (`∫(1-expH)(1-expT)`), removes `beta*dS/gamma*dt`, removes second derivative, removes salinity from density – only one exp scale 200 for density/pressure, one exp scale 120 for T/sound – broad models can copy directly from instruction.
- Looser tolerances: pressure 20k 1e-2 >2, gradient 1e-4, SOFAR 10m tol, 100 pts no Brent.

## Anti-Cheating – v5
- Density exact at 6 depths 3-term, gradient vs central diff h=0.001 tol 1e-4, sound 3-term exact + grad, SOFAR brute 2m within 10m 100pts, pressure Simpson 20k 1e-2 missing >2, steric simple, volume simple no thermal, pot temp 1st order exact.
- Step2: Cd 5-pt log-interp band 0.1, eq sorted f~0 within 20, TimeToDepth vs ref 25%, DiveProfile mono len>3 tol 5%, Batch order 20, invalid, crush, deadline 500ms/50 lenient, cancel 200ms/50 lenient, max concurrency behavioral, AST go/wg/make4/heap/atomic any width + typed atomic + context/sync/heap/atomic imports.
- R05: test.sh removes `/app/*_test.go` and `ast_check*.go` before and after.
