## Description – EASY v4 (15 consts, 5-term density, 1 finder, target 2/10 fails) + R05/R08 fixes

**Step1 EASY – 15 constants, 5-term density, 5-term pressure, 1st derivative, 1 finder, ~250-400 lines, target 2/10 fails (8/10 pass):**

Previous v3 was 24 consts 9-term density 10-term pressure 2nd derivative 2 finders but still 10/10 non-oracle failed. This v4 is ultra-easy:

- **15 consts** (vs 24, vs 34, vs 44): `Tolerance 1e-9, StandardGravity 9.81, StandardSeawaterDensity 1025, DepthDensityGradient 0.02, MinimumVolumeFraction 0.1, PycnoclineDelta 10/Scale 200, HaloclineDelta 2.5/Scale 30, ThermoclineScale 120, HullThermalExpansionCoeff 2e-4, SeawaterViscosity 0.001, SalinityDensityCoeff 0.8, BulkModulus 2.2e9, ThermalCouplingCoeff 0.15`. Removed `DeepPycnoclineDelta/Scale 4.5/45, MidPycnoclineDelta/Scale, CabbelingCoeff, HullThermalExpansionQuadCoeff, SoundSpeedPressureQuadCoeff, ThermobaricCoeff, GammaDepthFactor, TAnomQuadCoeff, SAnomQuadCoeff, SecondOrder, Triple, Thermosteric, Halosteric, Adiabatic, Vorticity, DoubleDiff, PressureNonLinear, Quadruple, Compensated, etc.`
- **Density 5 terms** (vs 9): `rho0 + grad*z + pyc1 + beta*sAnom + gamma*tAnom` where `pyc1=10*(1-exp(-z/200)), sAnom=2.5*(1-exp(-z/30)), tAnom=12*(1-exp(-z/120))`, beta=0.8, gamma=0.15. No deep pycno, no mid pycno, no `Gamma*z`, no cab `s*t`, no quad `t²/s²`, no thermo/halo/vort. Monotonic inc.
- **Pressure 5 terms** (vs 10): `g*(rho0*z + 0.5*grad*z² + PycDelta*(z+S*exp-S) + beta*Hd*(z+Hs*expH-Hs) + gamma*12*(z+Ts*expT-Ts))` only `integralOneMinusExp(S,z)=z+S*exp(-z/S)-S` needed, no product, no squared, no z*exp. Simpson **50k rel 1e-3 missing >5** (was 100k 1e-4 >10, 200k 1e-5 >20) very loose/fast.
- **Derivatives 1st only** (vs 2nd): `DensityGradientAtDepth` matches central diff h=0.001 within 1e-6. No second/third.
- **Sound 4 terms** (vs 5): `c=1449.2+4.6*T+1.34*(S-35)+0.016*z` no `-0.055T²` nor `SSq*z²` nor `0.01T(S-35)`. Checks c0>c200 and c1500>c200 still holds (minimum exists). Gradient `4.6dT+1.34dS+0.016` (3 terms). No pressure dependency.
- **Potential temperature 1st order** vs 2nd: `theta=T*(1 - x)` where `x=P/Bulk*1e-3`, surface 15 <=T.
- **BuoyancyFrequency simple** vs acoustic: `N²=g/rho*grad` (no `rho*g/c²` correction) positive.
- **Finders 1 vs 2**: only `FindSOFARAxis` (min sound). Removed `FindPycnoclineMaxGradient` (which needed gradient). Scan **500 pts** (was 1000) + **50 iter** (was 80) ternary, brute 2m within 5m (was 1m within 3m).
- **Methods ~14 vs 20**: keep SalinityAtDepth, TemperatureAtDepth, DensityAtDepth, DensityGradient, SoundSpeed, SoundSpeedGradient, FindSOFARAxis, PotentialDensity, PotentialTemperature, BuoyancyFrequencySquared, PressureAtDepth, StericHeight, VolumeAtDepth, EffectiveDensityAtDepth, Validate, EffectiveMass, EffectiveDensity.

**Step2 MEDIUM – eased slightly (from MEDIUM-HARD):**

- **R05 leak fix**: `test.sh` removes `*_test.go` + `ast_check*.go` before AND after verifier in both steps.
- **R08 atomic alternatives fix**: AST accepts any `Add/AddInt32/AddInt64/AddUint32/64, Load*, Store*, CompareAndSwap*, Swap*` + typed `atomic.Int32/Int64/Uint32/Uint64` with `Add/Load/Store/CompareAndSwap`. Instruction explicitly says "any valid style". Validated with `atomic.Int64` alternative golden → PASS (previously 6 rollouts failed at `atomicC`).
- **Cd table:** 10-pt → **5-pt** `[1e3,1e4,1e5,1e6,5e6]` Cd `[1.44,1.2,0.7,0.2,0.12]` log-interp band 0.1 midpoint 0.05 (was 10-pt band 0.05 midpoint 0.02).
- **Terminal:** 80 iter 1e-3 → **50 iter 1e-2** looser.
- **Equilibrium:** 1000 pts 80 iter → **500 pts 50 iter**, root tol 5m (was 3m), crush check.
- **TimeToDepth:** fixed RK4 `k1..k4` only + optional adaptive `atol/rtol/errorEstimate` also accepted, reference RK4 dt=0.001 **25% rel** (was 15%, was 8%).
- **DiveProfile:** len>3 (was 5) depth tol 5% (was 2%) pressure monotonic.
- **Fleet:** many=20 order preserved, deadline **200ms/100 → 500ms/50 lenient** with fallback log, cancellation **100ms/100 → 200ms/50 lenient**, max concurrency behavioral <=4 (checked via timing <10s + source `make(chan struct{},4)` + `WaitGroup` + `go` + `heap` + `atomic` any width).

**Completion Rates (oracle after v4):**
- Oracle step1: 100% (15 consts, 5-term density/pressure, 1st deriv, 1 finder)
- Oracle step2: 100% (5-pt Cd, 500pts equilibrium, fixed RK4, heap+atomic any width)

**Why v4 should hit 2/10 fails:**
- Step1 eliminates all product integrals (`∫(1-expH)(1-expT)`) and squared terms and z*exp – only single-scale `∫(1-exp)` needed. Gradient only 1st order, sound 4 terms trivial. Broad models can implement simple sum.
- Step2 fewer points (500 not 1000/2000) and 50 items not 300 reduces compute, looser tolerances reduce numerical misses.

## Anti-Cheating – v4
- Density exact at 6 depths 5-term, gradient vs central diff h=0.001 tol 1e-6, sound 4-term exact + grad h=0.05 tol 1e-3, SOFAR brute 2m within 5m 500pts, pressure Simpson 50k rel 1e-3 missing >5, steric simple, volume simple `exp(-kP)*(1+alpha*dT)` clamped 0.1, pot temp 1st order exact.
- Step2: Cd 5-pt log-interp band 0.1, equilibrium sorted f~0 within 20, TimeToDepth vs ref 25%, DiveProfile monotonic len>3 tol 5%, BatchFleet order 20, invalid handling, crushRisk, BatchWithTargets length mismatch, BatchWithContext background/cancel, cancellation lenient 200ms/50items, deadline lenient 500ms/50items, MaxConcurrency behavioral <10s ordering, ReuseCheck accepts any atomic Int32/64.
- AST: go/ast counts GoStmt>=1, WaitGroup>=1, make4>=1, heap>=1 (Push/Pop/Init + heap import), atomic>=1 (any Add/Load/Store/CompareAndSwap/Swap width + typed atomic detection + atomic import), context/sync/heap/atomic imports.
- R05: test.sh removes `/app/*_test.go` and `ast_check*.go` before and after verifier.

## Notes
v4 EASY 15 consts, 5-term density/pressure single-scale only, 1st derivative, sound 4 terms, 1 finder 500pts 50iter, pot temp 1st order. Fixes R05 leak, R08 atomic alternatives, eases step1 from 9/10 fails to target 2/10 fails and step2 slightly easier.
