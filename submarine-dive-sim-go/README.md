## Description – TRIVIAL v8 (6 consts, 1-term constant density rho0, 1-term pressure g*rho0*z, gradient 0, sound constant 1500, SOFAR 0, target 10-30% fail) + R05/R08 fixes

**Step1 TRIVIAL – 6 constants, 1-term constant density, 1-term pressure, gradient 0, sound constant 1500, SOFAR 0, 80-150 lines, target 10-30% fail (70-90% pass):**

- **6 consts** (vs 8,12,15,24,34,44): `Tolerance 1e-9, StandardGravity 9.81, StandardSeawaterDensity 1025, DepthDensityGradient 0.02, MinimumVolumeFraction 0.1, BulkModulus 2.2e9`. Removed `PycDelta/Scale, DeepPycno, MidPycno, Halo, Thermo, SalinityCoeff, HullExp, Visc, Cab, Quad, Thermobaric, Gamma, SecondOrder, Triple, etc.`
- **Density 1 term constant** vs 2: `rho(z)=rho0` where rho0=fluid.Density (1025). rho(0)=rho0 monotonic non-decreasing (derivative 0). No grad*z, no pyc, no exp, no math.Exp.
- **Pressure 1 term** vs 2: `P(z)=g*rho0*z` – no `0.5*grad*z²`, no Pyc. Matches Simpson 10k rel 1e-1 >2 trivially. No helper.
- **Gradient constant 0** vs 0.02: `drho/dz=0` constant tol 1e-3 extremely loose.
- **Sound constant 1500 vs quadratic:** `c(z)=1500` constant gradient 0, no T/S, no exp. Verifies constant 1500 within 1e-2. SOFAR constant – min everywhere – finder returns 0 trivially.
- **Salinity constant 35, Temperature constant 15** – no exp, gradients 0.
- **Potential density constant rho0**, **Potential temp 15**, **BuoyancyFreq 0**.
- **Finders 1 trivial:** SOFAR only via 10 pts scan returning 0.

Previous versions all 0/10: 44→34 26-term, 34→24 9-term, 24→15 5-term fa86e8a 0/10, 12→8 2-term linear 683b3c3 0/10 (gpt-5.5 0/10, avocado 0/10, opus 0/10, oracle 3/3 BAD_GRADING_WEAK). **v8 8→6 consts 1-term constant density/pressure no exp, gradient 0, sound constant, SOFAR 0 should hit 10-30% fail (70-90% pass) – 60% easier than 683b3c3.**

**Step2 EASY – eased + R05/R08 fixes kept:**
- **R05 leak:** `test.sh` rm `*_test.go` + `ast_check*.go` before AND after.
- **R08 atomic:** accepts any `Add/AddInt32/64/Uint32/64, Load*, Store*, CAS, Swap*` + typed `atomic.Int32/Int64/Uint32/Uint64`.
- **Cd:** 10-pt →5-pt `[1e3,1e4,1e5,1e6,5e6]` Cd `[1.44,1.2,0.7,0.2,0.12]` band 0.1 midpoint 0.05, terminal 50iter 1e-2, equilibrium 500pts 50iter 5m via compression k>0 for constant density, fixed RK4 k1..k4 + optional adaptive atol/rtol ref 25%, DiveProfile len>3 depth 5%, deadline 500ms/50 lenient, cancel 200ms/50 lenient.

**Completion Rates (oracle v8):**
- Oracle step1: 100% (6 consts, constant density/pressure/sound, SOFAR 0, 10pts)
- Oracle step2: 100% (5-pt Cd, constant density equilibrium via compression)

**Why v8 should hit 10-30% fail:**
- No math.Exp for density/pressure/gradient/sound – only `exp(-kP)` for volume (needed for equilibrium via compression). Gradient constant 0, pressure 1-term, sound constant, finder returns 0 – broad models can return constants directly from instruction.
