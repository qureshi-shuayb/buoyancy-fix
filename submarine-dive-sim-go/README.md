## Description
Rebalanced: Step1 ultra super-hard, Step2 easier moderate. Step1 triple pycnocline + halocline salinity + thermocline T/S coupling (beta 0.8, gamma 0.15), 18 constants, 5 exponentials in density, analytic gradient, second derivative, salinity/temperature gradients, sound speed SOFAR channel with minimum, potential density with bulk modulus, potential temperature, Brunt-Vaisala frequency, Turner angle, hydrostatic integral quadratic + 5 exponentials, exponential hull with thermal contraction. Step2 easier: simple Re table Cd 1.2/0.5/0.2, fixed RK4 5% tolerance, implicit terminal bisection, multi-root equilibrium scanning 0.5m, bounded worker-pool fleet 20 order preserved with simple context cancellation.

**Why Step1 is ultra super-hard:**

- **Zero formula spoilers**: Only differential relations dP/dz=rho*g, drho/dz analytic with 5 exps, T(z)=15-12*(1-exp(-z/Therm)), S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale)). No code-ready pressure integral coefficients. Agent must derive density rho=rho0+grad*z+D1(1-exp(-z/S1))+D2(1-exp(-z/S2))+D3(1-exp(-z/S3))+beta*(S-35)+gamma*(15-T) with 5 exps, pressure integral `P=g*(rho0*z+0.5*grad*z²+Σ Di*(z+Si*exp(-z/Si)-Si)+beta*H*(z+Hs*exp(-z/Hs)-Hs)+gamma*12*(z+Therm*exp(-z/Therm)-Therm))`, sound speed `c=1449.2+4.6T-0.055T²+1.34(S-35)+0.016z`, potential density without grad*z, Turner angle via Atan2.
- **Triple pycnocline + halocline + thermocline**: rho includes linear gradient 0.02 plus shallow Delta 10 Scale 200, deep Delta 4.5 Scale 45, mid Delta 7 Scale 90, halocline Delta 2.5 Scale 30, thermocline density 0.15*12*(1-exp(-z/120)). 5 exponential saturation scales, density monotonic but with complex curvature. Tests verify each term via density at 30m halocline, 45m deep, 90m mid, 200m shallow, 120m therm.
- **Full gradient suite**: Density gradient `grad+Σ Di/Si*exp+beta*Halocline/Hs*exp+gamma*12/Therm*exp` positive decreasing, second derivative negative increasing toward 0, salinity gradient positive decreasing, temperature gradient negative increasing, all checked vs numeric central diff 1e-4.
- **Sound speed SOFAR minimum**: c(z) decreases initially due to T drop then increases due to 0.016*z term, creating minimum around 600-1000m. Tests check c0>c200 and c1500>c200 exists.
- **Potential density & temperature**: Potential density without grad*z term, less steep than in-situ, must be < in-situ at depth, monotonic inc. Potential temperature = T(z)*(1-P*1e-10) tiny correction using BulkModulus, surface 15, decreasing, <= T.
- **Buoyancy frequency & Turner angle**: N²=g/rho*drho/dz positive decreasing, Turner angle via `atan2(gamma*dT/dz - beta*dS/dz, gamma*dT/dz + beta*dS/dz)*180/pi` -90..90 check, not NaN.
- **Eighteen constants**: Tolerance, StandardGravity, StandardSeawaterDensity, DepthDensityGradient, MinimumVolumeFraction, PycnoclineDelta, Scale, DeepDelta, Scale, MidDelta, Scale, HaloclineDelta, Scale, ThermoclineScale, HullThermalExpansionCoeff, SeawaterViscosity, SalinityDensityCoeff, BulkModulus. All exact, unique fingerprint.
- **Five-exp pressure integral**: Integral includes quadratic +5 exp terms, Simpson 100k ref, missing any term fails >1, quadratic 0.5*grad check.
- **Thermal hull**: Volume `V0*exp(-kP)*(1+alpha*(T-15))` clamped to 0.1*V0, even k=0 volume decreases ~0.2% due to cooling.

**Step1 Methods (14):** DensityAtDepth (5 exp), DensityGradientAtDepth, DensitySecondDerivativeAtDepth, SalinityAtDepth, SalinityGradientAtDepth, TemperatureAtDepth, TemperatureGradientAtDepth, SoundSpeedAtDepth, PotentialDensityAtDepth, PotentialTemperatureAtDepth, BuoyancyFrequencySquared, TurnerAngleAtDepth, PressureAtDepth (5 exp), VolumeAtDepth (exp+thermal), EffectiveDensityAtDepth, plus surface BuoyantForce etc.

**Step2 Easier:**

- **Simple Re table drag**: Cd=1.2 if Re<1e5 else 0.5 if Re<5e5 else 0.2, no crisis, monotonic drag vs v, simple bisection after doubling hi to find upper bound, tol 0.1 tight (was 0.05). Simple sqrt constant Cd fails where Re threshold crossed.
- **Fixed RK4 5%**: Coupled ODEs dz/dt=v, dv/dt=Fnet/m with m=EffectiveMass (no added mass), Fnet_down=Fw-Fb-0.5 rho Cd A v|v|, classic k1..k4 down-positive, interpolation for target crossing, unreachable & crush handling, accuracy 5% vs ref dt 0.01 (Euler fails >15%).
- **Equilibrium multi-root scanning still**: Product rho*V non-monotonic hump due to triple pycnocline + exponential volume, 0-2 roots, naive bisection over [0,max] fails when both ends same sign but interior root exists, requires scanning 1000 points to bracket sign changes then bisection each, tolerance 0.5m (was 0.3m), FindEquilibriumDepths returns all sorted, FindEquilibriumDepthsWithStability returns same depths with Stable=true (or via perturbation ±1m) — tests check depth sorted only, not strict stability sign.
- **Fleet batch moderate**: Bounded worker-pool sem size 4 via `make(chan struct{},4)`, WaitGroup, order preservation via indexed results, 20 subs stress (not 50), invalid marking, empty, mismatched lengths error, race-safe, context import, plus BatchAnalyzeFleetWithContext simple pre-check ctx.Err() returns context error on immediate cancel, background works order preserved. AST checks for go, WaitGroup, chan, context, sem, k1..k4, Exp, Sqrt, CdFromRe.

**Step 1 - Triple Pycnocline + Halocline + Thermocline + Sound Speed:**
Package submarine with 18 constants. Types Submarine, Seawater. Methods: Validate, EffectiveMass, EffectiveDensity, DensityAtDepth (5 exp), DensityGradientAtDepth, DensitySecondDerivativeAtDepth, SalinityAtDepth, SalinityGradientAtDepth, TemperatureAtDepth, TemperatureGradientAtDepth, SoundSpeedAtDepth, PotentialDensityAtDepth, PotentialTemperatureAtDepth, BuoyancyFrequencySquared, TurnerAngleAtDepth, PressureAtDepth (5 exp), VolumeAtDepth (exp+thermal), EffectiveDensityAtDepth. Functions: BuoyantForce surface, WeightForce, BuoyantForceAtDepth with 5-exp + T/S, RequiredBallastForNeutral surface/at depth, CheckSubmarineState surface/at depth, IsNeutralBuoyancyPossible surface/at depth.

**Step 2 - Dive Dynamics, Simple Re Table, Fixed RK4 & Fleet:**
File /app/dive.go reusing Step1 types. Must NOT redefine types/constants. DiveResult with EquilibriumDepth, TerminalVelocity, TimeToDepth, MaxPressure, VolumeAtDepth, CrushRisk etc, plus EquilibriumPoint{Depth,Stable,FPrime}. Functions: SubmergedFraction, NetVerticalForce surface, VerticalAcceleration, CdFromRe table, NetVerticalForceAtDepth with table Cd, TerminalVelocity bisection, FindEquilibriumDepth shallowest via scanning+bisection, FindEquilibriumDepths all sorted, FindEquilibriumDepthsWithStability simple, TimeToDepth fixed RK4 down-positive, AnalyzeDive, BatchAnalyzeFleet bounded pool, BatchAnalyzeFleetWithTargets, BatchAnalyzeFleetWithContext simple.

Tests context-following: check prior file exists, no redefinition, concurrency primitives, RK4 k1..k4, Exp, Sqrt, CdFromRe, etc., order preservation 20 subs, context cancellation simple.

## Completion Rates (to be filled after codimango runs)
| Model | Step | Pass Rate | Updated |
|---|---|---|---|
| Oracle | 1_basic_buoyancy_control | TBD | TBD |
| Oracle | 2_dive_dynamics | TBD | TBD |
| meta/avocado_dvsc_tester | 1_basic_buoyancy_control | TBD | TBD |
| meta/avocado_dvsc_tester | 2_dive_dynamics | TBD | TBD |
| claude-opus-4-6 | 1_basic_buoyancy_control | TBD | TBD |
| claude-opus-4-6 | 2_dive_dynamics | TBD | TBD |

## Model Analysis
Expected pass rates: Step1 <1% due to 5-exp density with T/S coupling often missed (HaloclineDelta, MidPycnoclineDelta, SalinityDensityCoeff, ThermalDensityCoeff gamma 0.15, BulkModulus), gradient and second derivative analytic required, salinity/temperature gradients, sound speed minimum existence, potential density less steep, Turner angle Atan2, pressure integral 5 exps with quadratic. Step2 ~15-20% due to simple table drag, fixed RK4 5% (Euler fails), multi-root scanning still required (naive fails), bounded pool 20 subs order preserved, simple context cancellation.

## Anti-Cheating Analysis
- Hardcoded outputs: 500 random combos, density at 30m halocline, 45m deep, 90m mid, 200m shallow, 120m therm each term missing fails, gradient vs numeric central diff 1e-4, second derivative vs numeric diff, salinity monotonic inc, temperature dec, sound speed min c0>c200 and c1500>c200, potential density < in-situ monotonic, pressure Simpson 5-exp 1e-3 rel, volume thermal, N² positive dec, Turner -90..90, Cd table bands 1.1-1.3 low 0.4-0.6 mid 0.15-0.3 high, terminal inverse 0.1, equilibrium brute 0.5m, fleet 20 order, race -count=1.
- No formula spoilers: pressure integral coefficients not given, only differential dP/dz=rho*g, drho/dz qualitative, sound speed formula given but pressure quadr+5 exp must derive.
- Overfitting: hidden tests read-only.
- AST checks: submarine.go must contain math.Exp >=5, MidPycnoclineDelta, HaloclineDelta, SalinityDensityCoeff, BulkModulus, SoundSpeedAtDepth, DensitySecondDerivative, TurnerAngle; dive.go must NOT contain type Submarine struct nor const Tolerance, must contain DensityAtDepth, PressureAtDepth, VolumeAtDepth, WaitGroup, chan, go, Sqrt, Exp, CdFromRe, EquilibriumPoint, BatchAnalyzeFleetWithContext, make(chan struct{}, 4), k1..k4.

## Notes
Rebalanced from ultra-hard both steps to super hard Step1 (18 const, triple pycnocline 10/200,4.5/45,7/90, halocline 2.5/30, therm 12/120, beta 0.8, gamma 0.15, salinity 35+2.5*(1-exp), T 15-12*(1-exp), rho with 5 exps, gradient with 5 exps, second derivative negative, salinity/temperature gradients, sound speed 1449.2+4.6T-0.055T²+1.34(S-35)+0.016z with SOFAR min, potential density without grad, potential temperature, N², Turner via Atan2) + easier Step2 (simple Re table 1.2/0.5/0.2, fixed RK4 5%, no added mass, single-root tolerant 0.5m, fleet 20, simple context). Unique API surface (MidPycnoclineDelta, HaloclineDelta, SalinityDensityCoeff, BulkModulus, DensitySecondDerivativeAtDepth, SalinityAtDepth, SoundSpeedAtDepth, PotentialDensityAtDepth, TurnerAngleAtDepth) has no public match. Schema 1.1 multi-turn inherit_prior_session true.
