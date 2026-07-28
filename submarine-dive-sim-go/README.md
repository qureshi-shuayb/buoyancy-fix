## Description – VERY EASY v7 (6 consts, 2-term linear density/pressure, quadratic sound, 1 finder SOFAR 100pts, target 10-30% fail) + R05/R08 fixes

**Step1 VERY EASY – 6 constants, 2-term density, 2-term pressure, gradient constant, sound quadratic, 1 finder SOFAR, 100-200 lines, target 10-30% fail (70-90% pass):**

- **6 consts** (vs 8,12,15,24,34,44): `Tolerance 1e-9, StandardGravity 9.81, StandardSeawaterDensity 1025, DepthDensityGradient 0.02, MinimumVolumeFraction 0.1, BulkModulus 2.2e9`. Removed `PycDelta/Scale, DeepPycno, MidPycno, Halo, Thermo, SalinityCoeff, HullExp, Visc, Cab, Quad, Thermobaric, Gamma, SecondOrder, Triple, etc.`
- **Density 2 terms** (vs 3): `rho0+grad*z` linear, no pyc, no beta*s, no gamma*t, no exp, rho(0)=rho0 monotonic inc, no math.Exp needed for density.
- **Pressure 2 terms** (vs 3): `P(z)=g*(rho0*z+0.5*grad*z²)` – no `Pyc*(z+S*exp-S)`, no `integralOneMinusExp`, just linear+quadratic integral. Simpson 20k rel 1e-2 missing >2 extremely loose/fast.
- **Gradient constant** `0.02` tol 1e-4 looser (was 1e-6).
- **Sound quadratic 3 terms**: `c(z)=1500 -0.1*z +0.0002*z²` min at 250m =0.1/0.0004, no T/S dependency, no exp. Gradient `-0.1+0.0004*z` 2 terms. Checks c0=1500>c200=1488 and c1500=1800>c200.
- **Salinity/Temperature constant/linear trivial**: `S=35`, `T=15` or `S=35+0.01z, T=15-0.02z` – no exp.
- **Potential density constant**: `rho - grad*z = rho0`.
- **Potential temp**: `x=P/Bulk*1e-3, theta=T*(1 - x)` where T linear, surface 15 <=T.
- **BuoyancyFrequency simple**: `N²=g/rho*grad` constant.
- **Finders 1 trivial**: SOFAR only via 100 pts scan returning precomputed minimum 250m, no Brent, brute 2m tol 10m.

Previous versions:
- 44→34 consts 26→19 term density 5th deriv 7 finders → 10/10 fails (BAD_GRADING_WRONG false negatives on vort z² and sound hidden terms)
- 34→24 consts 19→9 term 2nd deriv 2 finders → 9/10 fails
- 24→15 consts 9→5 term → 0/10 Avocado at fa86e8a (your screenshot: opus 0/10, avocado 0/10, oracle 3/3)
- 15→12 consts 5→3 term → still 0/10 at 41a49dd
- 12→8 consts 3→2 term linear rho0+grad*z, pressure g*(rho0*z+0.5*grad*z²), sound quadratic 250m → still 0/10 at 683b3c3 (your screenshot: gpt-5.5 0/10, avocado 0/10, opus 0/10, oracle 3/3, Agentic Reviewer BAD_GRADING_WEAK)
- **v7 8→6 consts 2-term linear density/pressure no exp, gradient constant 0.02, sound quadratic min 250m, 100pts 50iter, 10m tol → should hit 10-30% fail (70-90% pass) targeting 5/10 earlier request.**

**Step2 EASY-MEDIUM – eased further + R05/R08 fixes kept:**

- **R05 leak:** `test.sh` rm `*_test.go` + `ast_check*.go` before AND after verifier in both steps.
- **R08 atomic:** accepts any `Add/AddInt32/64/Uint32/64, Load*, Store*, CAS, Swap*` + typed `atomic.Int32/Int64/Uint32/Uint64` – instruction says any valid style. Previously pinned Int32 only – 6 rollouts failed at atomicC check (D2pM29n, GVw9QGd, 4Uy9gWN, ze5kc6h, QZnVES7).
- **Cd:** 10-pt → **5-pt** `[1e3,1e4,1e5,1e6,5e6]` Cd `[1.44,1.2,0.7,0.2,0.12]` band 0.1 midpoint 0.05.
- **Terminal:** 50 iter 1e-2, **Equilibrium:** 500 pts 50 iter root tol 5m, **TimeToDepth:** fixed RK4 k1..k4 + optional adaptive atol/rtol/errorEstimate, ref **25% rel**, **DiveProfile** len>3 depth tol 5%, **deadline 500ms/50items lenient**, **cancel 200ms/50items lenient**, max concurrency <=4 behavioral.

**Completion Rates (oracle v7):**
- Oracle step1: 100% (6 consts, 2-term linear density/pressure, quadratic sound, SOFAR 100pts)
- Oracle step2: 100% (5-pt Cd, 500pts eq, fixed RK4, heap+atomic any width)

**Why v7 should hit 10-30% fail:**
- Eliminates all exponentials from density/pressure/gradient (no math.Exp needed for density/pressure/gradient), gradient constant 0.02, pressure 2-term with explicit 0.5 factor that is now very loose (20k 1e-2), sound quadratic with explicit minimum formula 0.1/0.0004=250, finder trivial scan 100 pts, no cab/quad/product integrals, no Turner, no double-diffusive – broad models can implement directly from instruction.
