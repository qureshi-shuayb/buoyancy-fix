## Description – EASY v6 (8 consts, 2-term linear density/pressure, quadratic sound, 1 finder SOFAR 100pts, target 5/10 passes) + R05/R08 fixes

**Step1 EASY – 8 constants, 2-term density, 2-term pressure, 1st derivative constant, 1 finder SOFAR, 150-250 lines, target 5/10 passes (50%):**

- **8 consts** (vs 12,15,24,34,44): `Tolerance 1e-9, StandardGravity 9.81, StandardSeawaterDensity 1025, DepthDensityGradient 0.02, MinimumVolumeFraction 0.1, BulkModulus 2.2e9, PycnoclineDelta 10, PycnoclineScale 200`. Removed `HaloclineDelta/Scale, ThermoclineScale, SalinityDensityCoeff, HullThermalExpansionCoeff, SeawaterViscosity, CabbelingCoeff, etc.`
- **Density 2 terms vs 3**: `rho0+grad*z` linear, no pyc, no beta*s, no gamma*t, no exp, rho(0)=rho0 monotonic inc. No math.Exp needed.
- **Pressure 2 terms vs 3**: `P(z)=g*(rho0*z+0.5*grad*z²)` – no Pyc*(z+S*exp-S), no integralOneMinusExp, just linear integral. Simpson 20k rel 1e-2 missing >2 extremely loose.
- **Derivatives constant**: `drho/dz=grad=0.02 constant` – matches central diff h=0.001 within 1e-9 easily, tol 1e-4 looser.
- **Sound quadratic 3 terms vs 3 terms with exp**: `c(z)=1500 -0.1*z +0.0002*z²` quadratic minimum at `z=0.1/0.0004=250m`, no T/S dependency, no exp. Gradient `dc/dz=-0.1+0.0004*z` 2 terms. Checks c0=1500 > c200=1488 and c1500=1800 >1488 → SOFAR minimum exists.
- **Salinity/Temperature linear**: `S=35+0.01*z`, `T=15-0.02*z` – no exp, monotonic, trivial gradients 0.01, -0.02.
- **Potential density:** `rho - grad*z` = rho0 constant.
- **Potential temperature:** `x=P/Bulk*1e-3, theta=T*(1 - x)` where T linear, surface 15 <=T.
- **BuoyancyFrequency simple**: `N²=g/rho*grad` constant.
- **Finders 1 vs 1 but trivialized**: SOFAR only via 100 pts scan returning precomputed minimum 250m (no Brent, no ternary). Brute 2m within 10m looser (was 5m).

**Step2 EASY-MEDIUM – eased further + R05/R08 fixes kept:**

- **R05 leak:** `test.sh` rm `*_test.go` + `ast_check*.go` before AND after verifier in both steps.
- **R08 atomic:** accepts any `Add/AddInt32/64/Uint32/64, Load*, Store*, CAS, Swap*` + typed `atomic.Int32/Int64/Uint32/Uint64` – instruction says any valid style.
- **Cd:** 10-pt → 5-pt `[1e3,1e4,1e5,1e6,5e6]` Cd `[1.44,1.2,0.7,0.2,0.12]` band 0.1 midpoint 0.05.
- **Terminal:** 50 iter 1e-2, **Equilibrium:** 500 pts 50 iter root 5m tol, **TimeToDepth:** fixed RK4 k1..k4 + optional adaptive, ref 25% rel, **DiveProfile** len>3 depth tol 5%, **deadline 500ms/50items lenient**, **cancel 200ms/50items lenient**, max concurrency <=4 behavioral.

**Completion Rates (oracle v6):**
- Oracle step1: 100% (8 consts, 2-term linear density/pressure, quadratic sound, SOFAR 100pts)
- Oracle step2: 100% (5-pt Cd, 500pts eq, fixed RK4, heap+atomic any width)

**Why v6 should hit 5/10:**
- Eliminates all exponentials from density/pressure (no math.Exp needed), gradient constant, sound quadratic with explicit minimum formula 0.1/0.0004=250, finder trivial scan 100 pts, no cab/quad/product integrals – broad models can implement directly.

## Anti-Cheating – v6
- Density exact at 6 depths 2-term linear, gradient constant tol 1e-4, sound quadratic exact + grad, SOFAR brute 2m within 10m 100pts, pressure Simpson 20k 1e-2 missing >2, steric simple, volume simple no thermal, pot temp 1st order exact.
- Step2: Cd 5-pt log-interp band 0.1, eq sorted f~0 within 20, TimeToDepth vs ref 25%, DiveProfile mono len>3 tol 5%, Batch order 20, invalid, crush, deadline 500ms/50 lenient, cancel 200ms/50 lenient, max concurrency behavioral, AST go/wg/make4/heap/atomic any width + typed atomic.
- R05: test.sh removes `/app/*_test.go` and `ast_check*.go` before and after.
