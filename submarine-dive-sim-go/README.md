## Description
Rebalanced: Step1 super-hard stratified ocean with 26 constants (triple pycnocline + halocline + thermocline + quad cabbeling + depth-dependent gamma + quad anomalies), 11 exponential scales (200,45,90,30,120,24,22.5,26.08,32.72,60,15) plus z*exp term, full analytic derivatives (first, second, third) verified vs central diff, sound speed with quad and cross T*(S-35) coupling, SOFAR axis, pycnocline max gradient, spiciness max finders via 1000-point scan+ternary, potential density, second-order potential temperature using BulkModulus and ThermobaricCoeff, Brunt-Vaisala, Turner angle, double-diffusive regime, pressure closed-form 11 terms including mixed scales and double-freq and z*exp integrals verified via Simpson 500k, steric height, hull volume quad thermal exp. Step2 easier moderate: Re table drag Cd 1.2/0.5/0.2, terminal bisection, multi-root equilibrium scanning 200 points, fixed RK4 time-to-depth 15% tolerance, bounded worker-pool fleet 20 order preserved, context cancellation during flight.

**Why Step1 is super-hard (current 26-constant version):**

- **26 exact constants** including CabbelingCoeff 0.06, HullThermalExpansionQuadCoeff 1.2e-6, SoundSpeedPressureQuadCoeff 1.2e-5, ThermobaricCoeff 0.5, ThermalCouplingCoeff 0.15, GammaDepthFactor 0.0001, TAnomQuadCoeff 0.002, SAnomQuadCoeff 0.01. All verified via TestConstants.
- **Density** rho = rho0+grad*z + pyc1+pyc2+pyc3 + beta*sAnom + gamma0*tAnom*(1+GammaDepthFactor*z) + Cc*sAnom*tAnom + Cc*pyc3*sAnom + Cc*pyc1*sAnom + Cc*pyc2*tAnom + Tquad*tAnom^2 + Squad*sAnom^2 with explicit mapping PycnoclineDelta=10 scale 200 etc. 11 scales, monotonic inc, cab+quad diff >=0.5 at 60m.
- **Derivatives** first, second, third analytic matched to central diff h=0.01 tol 1e-6 / 1e-5.
- **Sound speed** c=1449.2+4.6T-0.055T^2+1.34*(S-35)+0.016z+quad*z^2+0.01*T*(S-35) cross term, min check c0>c200 and c1500>c200, gradient includes cross product, matched to numeric h=0.1 tol 1e-4.
- **Finders** SOFAR axis, pycnocline max gradient, spiciness maximum via scanning >=1000 then ternary until width<tolerance, brute 0.5m tolerance 1m/1.5m.
- **Pressure** complete closed-form with breakdown table (rho0*z, 0.5*grad*z^2, 3 pycno saturations, halocline beta, thermocline gamma, depth-dependent thermal z*tAnom with z*exp integral, 4 cabbeling mixed scales Smix24=24m, Smix22.5=22.5m, SmixS1_Hs=26.08m, SmixS2_Ts=32.72m, quad double-freq Hs/2=15m Ts/2=60m). Matches Simpson 500k rel 1e-5, missing any mixed/double-freq/z*exp fails by >10.
- **Steric height** (P/g - rho0*z)/rho0 matches Simpson 100k rel 1e-3, hull volume V=V0*exp(-kP)*(1+alpha*(T-15)+alpha2*(T-15)^2) clamped MinimumVolumeFraction*V0, crush error contains "crush".
- **Stability**: N^2=g/rho*drho/dz positive decreasing, Turner angle atan2(gamma*dT/dz+beta*dS/dz, beta*dS/dz-gamma*dT/dz)*180/pi range -90..90, regime contains "salt"/"diffus"/"stable".

**Step1 Methods (24 inc helpers):** SalinityAtDepth, SalinityGradientAtDepth, TemperatureAtDepth, TemperatureGradientAtDepth, DensityAtDepth, DensityGradientAtDepth, DensitySecondDerivativeAtDepth, DensityThirdDerivativeAtDepth, SoundSpeedAtDepth, SoundSpeedGradientAtDepth, FindSOFARAxis, FindPycnoclineMaxGradient, FindSpicinessMaximum, PotentialDensityAtDepth, PotentialTemperatureAtDepth, BuoyancyFrequencySquared, TurnerAngleAtDepth, DoubleDiffusiveRegimeAtDepth, PressureAtDepth, StericHeightAtDepth, VolumeAtDepth, EffectiveDensityAtDepth, Validate (both types), EffectiveMass, EffectiveDensity, plus CabbelingParameterAtDepth, SpicinessAtDepth.

**Step2 – Exact signatures now documented (fix for R01/R02/R03):**

```go
func SubmergedFraction(sub Submarine, fluid Seawater) (float64, error)
func NetVerticalForce(sub Submarine, fluid Seawater, g float64) (float64, error)
func VerticalAcceleration(sub Submarine, fluid Seawater, g float64) (float64, error)
func CdFromRe(re float64) float64
func NetVerticalForceAtDepth(sub Submarine, fluid Seawater, depth float64, velocity float64, g float64) (float64, error)
func TerminalVelocity(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error)
func FindEquilibriumDepth(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) (float64, error)
func FindEquilibriumDepths(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]float64, error)
func FindEquilibriumDepthsWithStability(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]EquilibriumPoint, error)
func TimeToDepth(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) (float64, error)
func AnalyzeDive(sub Submarine, fluid Seawater) (DiveResult, error)
func BatchAnalyzeFleet(subs []Submarine, fluid Seawater) ([]DiveResult, error)
func BatchAnalyzeFleetWithTargets(subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult, error)
func BatchAnalyzeFleetWithContext(ctx context.Context, subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult, error)
```

Tests compile against these – no more guessing NetVerticalForceAtDepth arity or missing EffectiveMass.

- **Re table**: Cd=1.2 if Re<1e5 else 0.5 if Re<5e5 else 0.2, monotonic non-increasing, drag 0.5*rho*Cd*A*v*|v| where A=V/Length, mu=SeawaterViscosity.
- **Terminal**: bisection after doubling hi until drag>=|delta| or 1e4, 100 iter.
- **Equilibrium**: scan 1000 points [0,maxDepth], bisection 100 iter, dedup tolerance*10, zero tol 1e-6, crush if maxDepth>CrushDepth, returns shallowest + all sorted + stability via FPrime.
- **TimeToDepth**: fixed RK4 k1..k4 down-positive, dt 0.1 vs ref 0.01, maxTime 30000, 15% rel, interpolate on crossing, crush handling.
- **Fleet**: bounded sem 4 via make(chan struct{},4), WaitGroup, order preservation indexed results sorted by Index, invalid sub DiveResult{Index:i,State:"invalid"}, empty slice, mismatched lengths error "length"/"mismatch", context check before and during flight via select on sem acquire and ctx.Done(), early abort.

**Step 1 - Triple Pycnocline + Halocline + Thermocline + Quad Cabbeling + Sound Speed:**
Package submarine with 26 constants. Types Submarine, Seawater. Methods: Validate, EffectiveMass, EffectiveDensity, DensityAtDepth (5 exp + 4 cab + 2 quad + gamma*z), DensityGradientAtDepth, DensitySecondDerivativeAtDepth, DensityThirdDerivativeAtDepth, SalinityAtDepth, SalinityGradientAtDepth, TemperatureAtDepth, TemperatureGradientAtDepth, SoundSpeedAtDepth (quad+cross), SoundSpeedGradientAtDepth, PotentialDensityAtDepth, PotentialTemperatureAtDepth using BulkModulus and ThermobaricCoeff second-order, BuoyancyFrequencySquared, TurnerAngleAtDepth, DoubleDiffusiveRegimeAtDepth, PressureAtDepth analytic 11 terms, StericHeightAtDepth, VolumeAtDepth quad thermal, EffectiveDensityAtDepth, CabbelingParameterAtDepth, SpicinessAtDepth, FindSOFARAxis, FindPycnoclineMaxGradient, FindSpicinessMaximum.

**Step 2 - Dive Dynamics, Re Table, Fixed RK4 & Fleet:**
File /app/dive.go reusing Step1 types. Must NOT redefine types/constants. DiveResult, EquilibriumPoint. Functions: SubmergedFraction, NetVerticalForce, VerticalAcceleration, CdFromRe, NetVerticalForceAtDepth, TerminalVelocity, FindEquilibriumDepth, FindEquilibriumDepths, FindEquilibriumDepthsWithStability, TimeToDepth, AnalyzeDive, BatchAnalyzeFleet, BatchAnalyzeFleetWithTargets, BatchAnalyzeFleetWithContext with exact signatures listed above.

Tests behavioral-first: density at multiple depths, gradient vs numeric diff, sound min + cross term, finders vs brute 0.5m, pressure vs Simpson 500k, steric vs formula, volume quad thermal, Turner formula, Cd bands, terminal inverse, equilibrium brute 0.5m, fleet 20 order preservation, race -count=1, context immediate cancel + cancellation during flight (15ms sleep then cancel, must return error quickly, not hang), bounded pool AST check for make(chan struct{},4) via go/parser (ignores comments) plus stripped-comment checks for k1..k4.

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
Expected: Step1 <5% due to 26 constants, 11 scales + z*exp + double-freq + quad terms, analytic derivatives, pressure 11-term closed-form vs Simpson 500k, sound speed cross term, 3 finders. Step2 now ~20-30% after fixing exact signatures – previously 0% of strong models passed due to compile errors from missing EffectiveMass and wrong arity (NetVerticalForceAtDepth expected 5 params, many guessed 3). With signatures documented, attempts can compile and focus on physics/RK4/fleet. Fleet still requires real bounded pool and context handling.

## Anti-Cheating Analysis
- Hardcoded: density terms verified at 0,30,45,60,90,120,200,500m including cab+quad diff >=0.5, gradient vs central diff h=0.01 tol 1e-6, second/third derivative vs diff, cabbeling parameter explicit, spiciness zero at surface, sound speed cross term 0.01*T*(S-35) diff >=0.05 and gradient vs diff h=0.1 tol 1e-4, SOFAR/pycnocline/spiciness max vs brute 0.5m scan, pressure vs Simpson 500k rel 1e-5 plus missing terms check diff >5, steric vs formula, volume quad thermal vs exact, N2, Turner range + regime string checks, Cd bands + monotonic, net force at depth 0 vs surface 1e-3 and low-v drag exact, terminal drag approx delta tol 0.1 + sign + drag error message, equilibrium single root near 0 and heavy no root and brute 0.5m tolerance, multi-root sorted + zero check <5, crush error contains "crush", TimeToDepth heavy time validity + 15% rel vs dt/10 + light should not reach + crush, AnalyzeDive state fraction net force volume MaxPressure, Batch 3 items float/invalid/neutral + empty + 20 order, BatchWithTargets mismatch error + crushRisk, BatchWithContext immediate cancel + 20 order + mismatch + new cancellation-during-flight (15ms sleep then cancel, must return context/cancel error within 10s) + bounded pool order 20.
- Concurrency: previously gameable string checks `go `, `WaitGroup`, `chan`, `make(chan struct` could be bypassed via comments `// go` – now fixed by strip_go_comments() removing //, /* */, and string literals before checking, plus AST-based check via go/parser that counts *ast.GoStmt, WaitGroup ident, make(chan struct{},4) with buffer 4, context and sync imports. AST ignores comments by design. Behavioral tests for bounded pool: order preservation 20, race detector, cancellation during flight proves context checked while work in flight (not just pre-check), not just presence of keyword.
- Overfitting: hidden tests read-only, but new tests also behavioral.
- Information isolation: test.sh now rm -f /app/*_test.go and ast_check_concurrency.go before pytest to prevent prior-step verifier Go files leaking via inherit_prior_session=true.
- Spec sufficiency: Step2 now lists all 14 exact signatures with param order, plus Types block, plus note about EffectiveMass() existence in Step1 Section E.

## Notes
Hardened after feedback: fixed R01/R02/R03 by adding exact Step2 signatures block, fixed R06/R07 by replacing gameable string checks with stripped-comment checks + AST parsing + behavioral cancellation-during-flight test, fixed R05 hygiene by cleaning test files in test.sh. 26 constants fingerprint, 11 scales, gamma depth factor, cabbeling, quad anomalies, SOFAR, spiciness, steric, Turner, second-order potential temperature. Schema 1.1 multi-turn inherit_prior_session true.
