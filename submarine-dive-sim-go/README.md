## Description – HARD (Simplified from ULTRA-ULTRA-HARD)
Step1 **HARD** stratified ocean with **34 constants** (26 core + SecondOrder 0.015, Triple 0.004, Thermosteric 0.0008, Halosteric 0.0003, Adiabatic 0.0002, Vorticity 0.00005, DoubleDiffusive 18, PressureNonLinear 1.5e-6), density **19 terms** rho0+grad*z+3 pycno+beta*s+gamma*t*(1+Gamma*z)+4 cab+2 quad+2 second-order s²t/st²+2 triple+thermo/halo/vort (removed quadruple s²t², compensated p1p2s, baroclinic z*s*t*I, z² thermo/halo, z² vort second-order), pressure **18-term** analytic via integralProduct 8 masks + z*exp (no z²*exp, z*product, z²*product, quad/comp/baro), Simpson 200k rel 1e-5 missing any >20 (was 500k 1e-6 >30), derivatives up to **3rd order** only (was 5th) via mul2 h=0.001 tol 1e-7/1e-6/1e-5 (was 1e-8/1e-7/1e-6/1e-5/1e-4), cabbeling includes second-order+triple (no quadruple+compensated), sound speed simplified: c=1449.2+4.6T-0.055T²+1.34(S-35)+0.016z+SSPressureQuad*z²+0.01T(S-35)+Pn*1e2*(P/Bulk*1e3)*T (removed depth-cube z³, T³, S³, Quad*T*S, ThermoSecond, HaloSecond, P²*T, z*P), gradient 7 terms, potential temp 3rd order x³ + z lapse (was 4th order x⁴+z² lapse), steric simple (P/g - rho0*z)/rho0 (was P²+P³), volume simple exp(-kP)*(1+alpha dT+alpha2 dT²) clamped (was P³+Comp*dT*P cross), bulk modulus simple K=1/k positive (was K=1/(k-2*Pn*P-3*Pc*P²-Comp*dT)), finders **4** via 2000 pts Brent 100 iter SOFAR/pycnocline/spice/double-diffusive (removed thermocline/halocline/compensated, was 3000 pts 200 iter 7 finders), N² acoustic correction g/rho*(drho/dz - rho*g/c²) + PV, Turner, regime, spiciness curvature (removed torsion, BV-gradient, curvature). Target solve rate 10-30% and ~800-1100 lines (was <0.1% 1800-2200 lines).

**Fixes applied (BAD_GRADING_WRONG):**
- Removed `VorticityMixingCoeff*0.01*z²*(1-expDm)` second-order vorticity term from instruction.md density formula – tests and golden never included it, causing rho 30m delta 0.000365 false negative. Spec now matches tests.
- Added missing sound terms to displayed formula OR removed hidden terms: Previous spec omitted `Quadruple*20*T*(S-35)+ThermoSecond*1e4*T²+HaloSecond*1e4*(S-35)²+Baroclinic*100*T³+Compensated*10*S³+P²*T+z*P` that tests required. Simplified version now explicitly lists only `+Pn*1e2*(P/Bulk*1e3)*T` coupling and excludes all hidden terms, so displayed formula = tested formula. Fixes sound 200m delta -0.313 false negative.
- All density, cabbeling, pressure, sound exact checks now align spec↔tests↔golden.

**Why Step1 is now HARD (50% easier):**
- **34 constants** exact fingerprint, down from 44.
- **Density** rho = rho0+grad*z + pyc1+pyc2+pyc3 + beta*sAnom + gamma*tAnom*(1+Gamma*z) + 4 cab + 2 quad + SecondOrder*s²t + SecondOrder*st² + Triple*s*t*pyc1 + Triple*s*t*pyc2 + Thermosteric*0.01*t*z + Halosteric*0.01*s*z + Vorticity*z*(1-expDm). 8 terms removed vs ultra-ultra.
- **Derivatives** up to 3rd only, matched to central diff h=0.001 tol 1e-7/1e-6/1e-5 (looser than 1e-8).
- **Cabbeling** includes second-order s²t/st² + triple s*t*pyc, no quadruple s²t² + compensated p1p2s.
- **Sound** includes P*T coupling only, gradient 7 terms, no depth-cube z³+T³+S³+Quad*T*S+ThermoSecond+HaloSecond+P²*T+z*P. Exact check at 200m uses simplified formula.
- **Finders** 2000 pts + Brent 100 iter (was 3000 pts 200 iter), 4 finders only (was 7), brute 0.5m within 2m (was 0.2m within 1m).
- **Pressure** 18-term analytic using integralProduct 8 masks + z*exp, no z²*exp, z*product, z²*product. Simpson 200k rel 1e-5 missing any fails >20 (was 500k 1e-6 >30).
- **Steric/Volume/Bulk** simple, no P²+P³, no P³+cross.
- **Methods** 26 vs 35: removed DensityFourth/Fifth, SoundSpeedCurvature, BuoyancyFrequencyGradient, SpicinessTorsion, 3 finders.

**Step2 HARD (hardened):**
- Reuses 34 constants (not 44), do NOT redefine.
- Log-interp drag 10-pt table unchanged, CdFromRe log10 interpolation, monotonic, midpoint log exact.
- Terminal Brent 150 iter tight 1e-3, doubling hi.
- Equilibrium 2000 pts scan, Brent 150 iter, dedup, stability FPrime<0.
- TimeToDepth adaptive Dormand-Prince RK45 atol 1e-6 rtol 1e-5 PI control, **now compared to independent reference RK4 dt=0.0005** (not self dt=0.001) to prevent gaming. Tolerance 8% rel.
- Dive profile ComputeDiveProfile returns []DiveState trajectory using same RK45, checks monotonic depth/pressure/time, final depth within 1%, len>10.
- Fleet priority queue via container/heap by effective density descending, bounded pool 4 via make(chan struct{},4), atomic max concurrency via sync/atomic AddInt32/Load/CompareAndSwap, **behavioral checks**: order preserved 20, deadline handling with 300 items 50ms timeout (was 20ms flaky), cancellation during flight 300 items cancel after 30ms (was 5ms), plus AST checks for go, WaitGroup, make4, heap, atomic.

## Completion Rates
| Model | Step | Pass Rate | Notes |
|---|---|---|---|
| Oracle | 1_basic_buoyancy_control | 100% | HARD 34 consts, 18-term pressure, 3rd derivative, 4 finders – fixed alignment |
| Oracle | 2_dive_dynamics | 100% | log-interp, adaptive RK45 with independent ref, priority heap+atomic, deadline 50ms |

## Model Analysis – HARD Expected 10-30%
Step1 now requires 19-term density (vs 26), 18-term pressure with generic product integral 8 masks (vs 26-term 16 masks + z²*exp + z*product), derivatives up to 3rd (vs 5th), sound with 1 pressure coupling (vs 7 couplings), 4 finders 2000 pts (vs 7 finders 3000 pts). Previous ultra-ultra had <0.1% solve due to artificial contradictions; fixing spec/test alignment alone should bring many broad Claude/GPT models from GRADING_FAILURE to PASS. Further simplification to 34 constants and 3rd derivative should target Avocado 1-3 fails out of 10 (vs 10/10 before). Lines ~800-1100 vs 1800-2200.

Step2 remains hard but with hardened behavioral checks: independent reference integrator prevents token-only gaming, deadline relaxed to 50ms for 300 items (was 20ms for 100) reduces flakiness, cancellation 30ms for 300 items (was 5ms for 100). Atomic max concurrency now behaviorally verified <=4.

## Anti-Cheating – Hardened
- Hardcoded: density at 8 depths exact 19-term, cab with second-order+triple exact, gradient/second/third vs central diff h=0.001 tol 1e-7/1e-6/1e-5, sound with P*T exact + gradient h=0.05 tol 1e-3, finders brute 0.5m 2000 pts within 2m, pressure Simpson 200k rel 1e-5 missing any fails >20, steric simple, volume simple, bulk modulus positive, PV positive, potential temp 3rd order x³ + z lapse exact.
- Concurrency step2: AST via go/parser counts GoStmt, WaitGroup, make4, heap Push/Pop/Init, atomic AddInt32/Load/CAS, imports context/sync/heap/atomic, atol/rtol/errorEstimate, k1_z/k1_v, DiveState, ComputeDiveProfile. Behavioral: order 20, deadline 50ms for 300 items with retry 10ms, cancellation during flight 30ms for 300 items with retry 5ms, independent ref RK4 tolerance 8%.
- Dockerfile: pip install retries unchanged.

## Notes
HARD v4 – 34 constants, 19-term density, 18-term pressure via integralProduct 8 masks + integralZOneMinusExp, sound with P*T only, 3rd derivative, 4 finders 2000 pts Brent 100 iter, potential temp 3rd order. Fixes BAD_GRADING_WRONG (vort z² and sound hidden terms), BAD_AMBIGUOUS (spec now lists exact terms tested), BAD_GRADING_WEAK (TimeToDepth independent ref, deadline relaxed), BAD_GOLDEN (golden matches spec). Targets 10-30% solve rate.
