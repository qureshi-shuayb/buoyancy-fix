## Description
Rebalanced: Step1 ultra super-hard, Step2 easier moderate. Step1 triple pycnocline + halocline salinity + thermocline T/S coupling (beta 0.8, gamma 0.15), 18 constants, 5 exponentials in density, analytic gradient, second derivative, salinity/temperature gradients, sound speed SOFAR channel with minimum, potential density without grad*z, potential temperature `theta=T*(1-P/BulkModulus*1e-3)` using BulkModulus, Brunt-Vaisala frequency, Turner angle via single Atan2 definition, hydrostatic integral quadratic + 5 exponentials must be derived from dP/dz=rho*g, exponential hull with thermal contraction. Step2 easier: simple Re table Cd 1.2/0.5/0.2, fixed RK4 5% tolerance with structured param table, implicit terminal bisection, multi-root equilibrium scanning 1000 points 0.5m, bounded worker-pool fleet 20 order preserved with simple context cancellation.

**Why Step1 is ultra super-hard (revised for clarity & difficulty):**

- **Single authoritative formulas, no contradictions**: Each method has ONE definition. PotentialTemperature previously gave 5 variants settling on T(z) – now single: `theta(z)=T(z)*(1-P(z)/BulkModulus*1e-3)` using PressureAtDepth and BulkModulus=2.2e9, surface 15, <=T, monotonic dec. Turner angle single: `Tu=atan2(gamma*dT/dz+beta*dS/dz, beta*dS/dz - gamma*dT/dz)*180/pi`. Sound speed single `c=1449.2+4.6T-0.055T^2+1.34*(S-35)+0.016z`. PotentialDensity single without grad*z. No more "Derive Yourself - No Explicit Formula" contradiction – pressure instruction ONLY gives differential `dP/dz=rho*g`, P(0)=0, requires analytic integration to quadratic+5 exp, no closed-form spoon-fed.
- **Zero formula spoilers for pressure**: Instruction states dP/dz=rho*g only, must integrate analytically containing 0.5*grad*z^2 plus 5 exp saturation terms. Agent must derive `∫ D*(1-exp(-z/S)) = D*(z+S*exp(-z/S)-S)` for each of 5 terms. Previously integral coefficients were listed code-ready – now removed to increase difficulty.
- **Triple pycnocline + halocline + thermocline**: rho = rho0+grad*z +10*(1-exp(-z/200))+4.5*(1-exp(-z/45))+7*(1-exp(-z/90))+0.8*2.5*(1-exp(-z/30))+0.15*12*(1-exp(-z/120)). 5 distinct saturation scales, monotonic inc but complex curvature. Tests verify each term via density at 30m halocline,45m deep,90m mid,200m shallow,120m therm – missing any term fails >0.4 kg/m3.
- **Full gradient suite behavioral**: Gradient analytic positive decreasing, checked vs numeric central diff 1e-4 at 10,45,90,100,200m, second derivative negative increasing toward 0 checked vs numeric diff of gradient, salinity gradient positive dec, temperature gradient negative inc.
- **Sound speed SOFAR minimum**: Checked via c0>c200 and c1500>c200 plus exact formula verification at 200m using T,S.
- **Potential density & temperature**: Potential density = rho without grad*z, less steep than in-situ, < in-situ at depth, exact formula checked at 100m. Potential temperature uses BulkModulus mandatory, exact formula checked at 10,100,200,500m: `T*(1-P/K*1e-3)`, monotonic dec.
- **Buoyancy frequency & Turner**: N^2 = g/rho*drho/dz positive decreasing, verified vs formula. Turner via Atan2 single definition verified at multiple depths -90..90 not NaN.
- **Eighteen constants**: All exact, unique fingerprint, verified via Go TestConstants – no AST keyword counting as primary gating (functional tests authoritative). Behavioral tests catch missing terms instead of `math.Exp>=5` count.
- **Five-exp pressure integral**: Simpson 100k reference rel 1e-3, quadratic 0.5*grad check, missing mid and halocline terms individually checked (delta >1).
- **Thermal hull**: V=V0*exp(-kP)*(1+alpha*(T-15)) clamped 0.1*V0, k=0 still decreases due to cooling.

**Step1 Methods (14):** DensityAtDepth (5 exp), DensityGradientAtDepth, DensitySecondDerivativeAtDepth, SalinityAtDepth, SalinityGradientAtDepth, TemperatureAtDepth, TemperatureGradientAtDepth, SoundSpeedAtDepth, PotentialDensityAtDepth, PotentialTemperatureAtDepth (uses BulkModulus), BuoyancyFrequencySquared, TurnerAngleAtDepth, PressureAtDepth (5 exp analytic), VolumeAtDepth (exp+thermal), EffectiveDensityAtDepth.

**Step2 Easier (structured params):**

- **Simple Re table**: Cd=1.2 if Re<1e5 else 0.5 if Re<5e5 else 0.2, monotonic stepwise, bisection doubling hi to find bound tol 0.1.
- **Fixed RK4 5%**: Table of dt=0.1 vs ref 0.01, maxSteps implicit 100000, classic k1..k4 down-positive, interpolation for target crossing, unreachable & crush handling, Euler fails >15%.
- **Equilibrium scanning table**: scan 1000 points equally spaced 0-maxDepth, bisection 100 iter until |f|<1e-9 or width<tol, dedup tolerance*10, naive bisection over [0,max] fails when both ends same sign but interior root exists.
- **Fleet batch**: Bounded sem 4 via make(chan struct{},4), WaitGroup, order preservation indexed results, 20 subs stress (not 50), invalid marking, empty, mismatched lengths error containing "length" or "mismatch", race -count=1, context import, BatchAnalyzeFleetWithContext simple pre-check ctx.Err() returns context error on immediate cancel, background works order preserved. AST checks for go,WaitGroup,chan,context are supplementary smoke checks – primary is behavioral order preservation and race detector.

**Step 1 - Triple Pycnocline + Halocline + Thermocline + Sound Speed:**
Package submarine with 18 constants. Types Submarine, Seawater. Methods: Validate, EffectiveMass, EffectiveDensity, DensityAtDepth (5 exp behavioral), DensityGradientAtDepth, DensitySecondDerivativeAtDepth, SalinityAtDepth, SalinityGradientAtDepth, TemperatureAtDepth, TemperatureGradientAtDepth, SoundSpeedAtDepth, PotentialDensityAtDepth (without grad*z), PotentialTemperatureAtDepth single authoritative using BulkModulus, BuoyancyFrequencySquared, TurnerAngleAtDepth single Atan2, PressureAtDepth analytic derived from dP/dz, VolumeAtDepth exp+thermal, EffectiveDensityAtDepth.

**Step 2 - Dive Dynamics, Simple Re Table, Fixed RK4 & Fleet:**
File /app/dive.go reusing Step1 types. Must NOT redefine types/constants. DiveResult, EquilibriumPoint. Functions: SubmergedFraction, NetVerticalForce, VerticalAcceleration, CdFromRe table, NetVerticalForceAtDepth with table Cd, TerminalVelocity bisection, FindEquilibriumDepth shallowest via scanning+bisection table, FindEquilibriumDepths all sorted, FindEquilibriumDepthsWithStability, TimeToDepth fixed RK4 table, AnalyzeDive, BatchAnalyzeFleet bounded pool, BatchAnalyzeFleetWithTargets, BatchAnalyzeFleetWithContext.

Tests now behavioral-first: no `math.Exp>=5` count gating, no MidPycnoclineDelta keyword presence as primary – constants checked via values, density terms via values at 30/45/90/200/120m, gradient via numeric diff, pressure via Simpson, potential temperature via exact BulkModulus formula, Turner via Atan2 formula, fleet via order preservation 20 subs & race, context via immediate cancel. Concurrency keyword checks kept as supplementary smoke with comment explaining authoritative behavioral tests.

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
Expected: Step1 <1% due to 5-exp density with T/S coupling requiring all terms at specific depths, gradient/second derivative numeric diff 1e-4, pressure Simpson 1e-3 requiring quadratic+5 exps derivation, sound speed SOFAR min exact formula, potential density exact without grad, potential temperature now non-trivial requiring BulkModulus and PressureAtDepth integration (previously trivial T(z) allowed), Turner Atan2 single definition, thermal hull. Harder than before because pressure integral not spoon-fed and potential temperature mandatory uses BulkModulus. Step2 ~15-20% due to simple table drag, fixed RK4 5% table, multi-root scanning table still required, fleet 20 order preserved, simple context.

## Anti-Cheating Analysis
- Hardcoded: 500 random combos, density at 30m halocline,45m deep,90m mid,200m shallow,120m therm each missing fails, extra withoutMid and withoutDeep checks at 90m/45m, gradient vs numeric central diff 1e-4, second derivative vs numeric diff, salinity/temperature monotonic + gradient dec/inc, sound speed min c0>c200 and c1500>c200 + exact formula at 200m, potential density < in-situ monotonic exact without grad*z at 100m, potential temperature exact T*(1-P/K*1e-3) at 4 depths <=T monotonic, pressure Simpson 5-exp 1e-3 rel missing mid and halocline individually >1, volume thermal, N2 formula g/rho*grad at 0 exact positive dec, Turner formula Atan2 exact at 5 depths -90..90, Cd bands, terminal inverse 0.1, equilibrium brute 0.5m, fleet 20 order, race -count=1.
- No formula spoilers: pressure only dP/dz=rho*g, P(0)=0, must derive quadratic+5 exp – no explicit D*(z+S*exp-S) listed, gradient described as derivative of rho not full expression.
- Overfitting: hidden tests read-only.
- AST now secondary: test_exists only checks package exists and comments that constants and Exp usage verified via behavioral Go tests, not primary gating. Step2 check_no_redef comment says concurrency checks supplementary, primary is order preservation 20 subs & race. Avoids gameable keyword counting as primary.

## Notes
Hardened Step1: concise ~130 lines single-formula-per-method, no contradictory PotentialTemperature (now single BulkModulus formula), pressure derivation harder (no spoilers), behavioral tests replace keyword counting, structured tables for Step2 RK4 scan 1000/bisection 100/dedup tol*10/dt 0.1 vs 0.01 ref 5% accuracy, sem 4. 18 constants fingerprint, 5 exps, gamma 0.15, beta 0.8, salinity 35+2.5*(1-exp(-z/30)), T 15-12*(1-exp(-z/120)), potential density without grad*z, potential temp theta=T*(1-P/K*1e-3), SOFAR min, Turner Atan2. Schema 1.1 multi-turn inherit_prior_session true.
