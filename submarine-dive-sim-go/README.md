## Description – EASY-MEDIUM (v3 – 24 consts, R05 leak fix, R08 atomic alternatives, target 2/10 fails step1)

**Step1 EASY-MEDIUM – 24 constants, 9-term density, 10-term pressure, 2nd derivative, 2 finders, 400-600 lines, target 2/10 fails:**

**Fixes from previous BAD_GRADING_WRONG:**
- Removed `Vorticity*0.01*z²*(1-expDm)` second-order vort term (rho 30m delta 0.000365) – spec now = tests = golden.
- Simplified sound: previously hidden `Quad*20*T*(S-35)+ThermoSecond*1e4*T²+HaloSecond*1e4*S²+T³+S³+P²*T+z*P` removed; now `c=1449.2+4.6T-0.055T²+1.34(S-35)+0.016z+SSq*z²` (5 terms) – displayed = tested.

**Why much easier than 34-const HARD (which still got 9/10 fails):**
- **24 consts** (vs 34, vs 44 ultra-ultra): `Tolerance, StandardGravity, StandardSeawaterDensity, DepthDensityGradient, MinimumVolumeFraction, PycnoclineDelta/Scale 10/200, Deep 4.5/45, Halo 2.5/30, Thermo 120, HullExp 2e-4, Visc 0.001, Salinity 0.8, Bulk 2.2e9, Cab 0.06, HullQuad 1.2e-6, SoundQuad 1.2e-5, Thermobaric 0.5, ThermalCoupling 0.15, Gamma 0.0001, Tquad 0.002, Squad 0.01`. Removed `MidPycnoclineDelta/Scale, SecondOrderCabbelingCoeff, TripleCabbelingCoeff, ThermostericAnomalyCoeff, HalostericAnomalyCoeff, AdiabaticLapseRate, VorticityMixingCoeff, DoubleDiffusiveMixingScale, PressureNonLinearCoeff`.
- **Density 9 terms** (vs 19, vs 26): `rho0 + grad*z + pyc1+pyc2 + beta*s + gamma*t*(1+Gamma*z) + Cc*s*t + Tquad*t² + Squad*s²`. Removed `pyc3, s²t, st², triple s*t*pyc, thermo 0.01*t*z, halo 0.01*s*z, vort z*(1-expDm)`. Monotonic, diff at 60m without cab/quad >=0.8 (was 1.0) looser.
- **Pressure 10 terms** (vs 18): `rho0*z + 0.5*grad*z² + pyc1+pyc2 + beta + gamma + gamma*z + cab s*t + quad t² + quad s²`. Helpers: `∫(1-exp)=z+S*exp-S`, `∫(1-expH)(1-expT)=z - S1(1-exp1)-S2(1-exp2)+Smix(1-expMix)` (4 masks only, k=2), `∫z(1-exp)=0.5z²+S*z*exp+S²*exp-S²`, `∫(1-exp)²=z+2S*exp-2S+S/2*(1-exp2)`. No 3-scale products, no z*exp for thermo/halo/vort. Simpson **100k rel 1e-4 missing >10** (was 200k 1e-5 >20, was 500k 1e-6 >30) much looser.
- **Derivatives 2nd only** (vs 3rd/5th): Gradient h=0.001 tol **1e-6** (was 1e-7), Second tol **1e-5** (was 1e-6). No third/fourth/fifth – removes Leibniz heavy.
- **Cab 3 terms** (vs 10): `Cc*s*t + Tquad*t² + Squad*s²`, zero at surface.
- **Sound 5 terms** (vs 7 with P*T, vs 12 with cubes): `1449.2+4.6T-0.055T²+1.34(S-35)+0.016z+SSq*z²` no `0.01T(S-35)` nor `Pn*P*T`. Gradient `4.6dT-0.11T dT+1.34dS+0.016+2SSq z` (4 terms). No PressureAtDepth needed.
- **Potential temp 2nd order** (vs 3rd + z lapse): `theta=T*(1 - x - Thermo*x²)` where `x=P/Bulk*1e-3`, surface 15, <=T.
- **Finders 2** (vs 4, vs 7): only `SOFAR` (min sound) and `PycnoclineMaxGradient` (max grad). Removed spiciness max and double-diffusive layer (which needed Turner angle). Scan **1000 pts** (was 2000) + Brent **80 iter** (was 100), brute 1m within 3m (was 0.5m within 2m).
- **Methods ~20** (vs 26): removed `DensityThirdDerivative, SpicinessCurvature, TurnerAngle, DoubleDiffusiveRegime, FindSpicinessMaximum, FindDoubleDiffusiveLayer`.
- **Expected lines 400-600** (was 800-1100).

**Step2 MEDIUM-HARD – eased slightly (still hard) + R08 fix:**

**R05 Information Isolation FIX:** `steps/*/tests/test.sh` now does `rm -f /app/*_test.go /app/ast_check*.go` **both before and after** verifier, plus clears ctrf.json, so `/app/sub_step1_test.go` cannot leak into Step2 inherited session. `test_outputs.py` also unlinks TEST_GO after go test.

**R08 Accepts Alternatives FIX + R06/R07 coverage:**
- Previously required `AddInt32, LoadInt32, CompareAndSwapInt32` – valid alternatives `AddInt64, AddUint32/64, LoadInt64, Store, Swap, typed atomic.Int32/Int64/Uint32/Uint64` with `Add/Load/Store/CompareAndSwap` were rejected (seen in 6 rollouts: D2pM29n, GVw9QGd, 4Uy9gWN, ze5kc6h, QZnVES7).
- Now AST checker accepts any: `Add, AddInt32, AddInt64, AddUint32, AddUint64, Load, LoadInt32/64, Store, StoreInt32/64, CompareAndSwap, CompareAndSwapInt32/64, Swap` plus typed `atomic.Int32/Int64` detection via `SelectorExpr` where X=atomic and Sel=Int32/64.
- Instruction.md explicitly says: "must use sync/atomic but accepts any valid style: AddInt32/LoadInt32/CompareAndSwapInt32 OR AddInt64, Uint, typed atomic.Int32/Int64 with Add/Load/Store/CompareAndSwap".
- `TestReuseCheck` no longer pins `AddInt32` only – it references both Int32 and Int64.
- **Behavioral concurrency:** `TestMaxConcurrencyBehavioral` measures batch 20 time <10s and order preserved, plus source check max <=4 (not ==4). Priority verified via heap Less descending and heap import, final Index ordering preserved 20.
- **Deadline/cancellation eased:** Deadline 50ms 300 items → **200ms 100 items** with lenient fallback (logs not fail on fast machine), Cancellation 30ms 300 → **100ms 100 items** with 10ms retry fallback. Reduces flakiness.
- **Other easing:** Cd band 0.05→0.1, midpoint tol 0.02→0.05, equilibrium scan 2000→1000 pts, Brent 150→80 iter, zero check 10→20, TimeToDepth ref 8%→15%, DiveProfile len>10→>5, final depth tol 1%→2%.

**Completion Rates (oracle after v3):**
- Oracle step1: 100% (24 consts, 10-term pressure, 2nd derivative, 2 finders)
- Oracle step2: 100% (log-interp band 0.1, equilibrium 1000 pts 80 iter, RK4 ref 15%, heap priority + atomic any width, deadline 200ms/100items)

**Why v3 should hit targets:**
- Step1: from 9/10 fails (34 consts) to expected 2/10 fails (24 consts) by removing Mid pycnocline, SecondOrder s²t/st², Triple, Thermo/Halo/Vort, PressureNonLinear, Third derivative, SOFAR? Actually SOFAR kept, double-diffusive removed. Only one 2-scale product integral remains – broad models can implement.
- Step2: easing reduces compute (1000 pts not 2000, 100 items not 300 in heavy tests) and relaxes tolerances, plus atomic alternatives accepted → fewer false negatives from over-specific checker.

## Anti-Cheating – v3 Hardened but Accepting Alternatives
- Density exact at 8 depths 9-term, cab 3-term exact, gradient/second vs central diff h=0.001 tol 1e-6/1e-5 looser, sound 5-term exact + grad h=0.05 tol 1e-3, finders brute 1m within 3m 1000 pts, pressure Simpson 100k rel 1e-4 missing >10, steric simple, volume simple, bulk positive, PV positive, pot temp 2nd order exact.
- Step2: Cd table 10-pt log-interp band 0.1, equilibrium multi-root sorted and f~0 within 20, stability FPrime<0, TimeToDepth vs independent RK4 ref 15%, DiveProfile monotonic depth/time and pressure len>5 tol 2%, BatchFleet order preserved 20, empty, invalid handling, crushRisk, BatchWithTargets length mismatch and crush, BatchWithContext background and immediate cancel and many 20 order, cancellation during flight 100ms/100items lenient 10ms retry, deadline 200ms/100items lenient, MaxConcurrency behavioral <10s ordering, ReuseCheck accepts any atomic.
- AST: go/ast counts GoStmt>=1, WaitGroup>=1, make4>=1 (chan 4), heap>=1 (Push/Pop/Init + heap import), atomic>=1 (any Add/Load/Store/CompareAndSwap/Swap width + typed atomic detection + atomic import), context/sync/heap/atomic imports.
- R05: test.sh removes /app/*_test.go and ast_check*.go before and after verifier.
- Empty test_no_hardcode kept as pass placeholder but not used for cheating.

## Notes
v3 EASY-MEDIUM 24 consts, 9-term density, 10-term pressure via 4 masks + z*exp + squared terms, 2nd derivative, sound 5 terms, 2 finders 1000 pts 80 iter, pot temp 2nd order. Fixes R05 leak, R08 atomic alternatives, plus eases step1 to 2/10 fails target and step2 slightly easier.
