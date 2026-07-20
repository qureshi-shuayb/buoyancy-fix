# Step 1: Ultra-Hard Submarine — Triple Pycnocline + Halocline + Thermocline + Cabbeling Coupling

## Overview
Step 1 of 2. Build Go package `submarine` modeling highly stratified ocean: triple exponential pycnocline (shallow/mid/deep), halocline salinity, thermocline temperature, **cabbeling cross-coupling** (product of salinity and temperature anomalies) introducing a mixed exponential scale not present in any single layer, plus derived quantities (spiciness, sound speed gradient, SOFAR axis finder, steric height, double-diffusive regime). Step 2 will reuse your types/constants/methods without redefinition. Define them cleanly now.

This step is intentionally super-hard: density contains non-linear T/S coupling requiring product-rule differentiation and a mixed-scale exponential integral for pressure that does NOT appear in standard tutorials. Sound speed includes quadratic pressure term and a dedicated analytic gradient plus root-finding for its minimum.

## Constants (exact values, 22)

```go
const Tolerance = 1e-9
const StandardGravity = 9.81
const StandardSeawaterDensity = 1025.0
const DepthDensityGradient = 0.02
const MinimumVolumeFraction = 0.1
const PycnoclineDelta = 10.0
const PycnoclineScale = 200.0
const DeepPycnoclineDelta = 4.5
const DeepPycnoclineScale = 45.0
const MidPycnoclineDelta = 7.0
const MidPycnoclineScale = 90.0
const HaloclineDelta = 2.5
const HaloclineScale = 30.0
const ThermoclineScale = 120.0
const HullThermalExpansionCoeff = 2.0e-4
const SeawaterViscosity = 0.001
const SalinityDensityCoeff = 0.8
const BulkModulus = 2.2e9
const CabbelingCoeff = 0.06
const HullThermalExpansionQuadCoeff = 1.2e-6
const SoundSpeedPressureQuadCoeff = 1.2e-5
const ThermobaricCoeff = 0.5
```

Fixed scalars: reference salinity 35 psu, reference temperature 15 C, thermal density coefficient gamma=0.15 kg/m3 per C (fixed, not a constant), salinity coefficient beta=SalinityDensityCoeff=0.8. All 22 must be defined exactly. Tests verify existence and values.

## Ocean Model (derive analytically, no numeric approximation for pressure)

Coordinate: z >=0 positive downward, surface z=0. All depth args must validate >=0 else error containing "depth". g validation >0 else "gravity".

**Salinity (halocline):**
`S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale))`
Surface 35, deep ~37.5, monotonic inc saturating.
- `dS/dz = HaloclineDelta/HaloclineScale*exp(-z/HaloclineScale)` positive decreasing.
- `d2S/dz2 = -HaloclineDelta/HaloclineScale^2*exp(-z/HaloclineScale)`

**Temperature (thermocline):**
`T(z)=15-12*(1-exp(-z/ThermoclineScale))` = `3+12*exp(-z/ThermoclineScale)`
Surface 15C, deep ~3C, monotonic dec.
- `dT/dz = -12/ThermoclineScale*exp(-z/ThermoclineScale)` negative increasing toward 0.
- Define anomaly `tAnom(z)=15-T(z)=12*(1-exp(-z/ThermoclineScale))`, so `dtAnom/dz = -dT/dz = 12/ThermoclineScale*exp(-z/ThermoclineScale)`, `d2tAnom/dz2 = -12/ThermoclineScale^2*exp(-z/ThermoclineScale)`

**Density with triple pycnocline + T/S coupling + cabbeling:**
You must assemble density from physical components — do NOT simply copy a final expanded formula, derive it:

Components:
- `rho0 = fluid.Density` (surface reference)
- Linear compressibility `DepthDensityGradient*z`
- Shallow pycnocline: `PycnoclineDelta*(1-exp(-z/PycnoclineScale))`
- Deep pycnocline: `DeepPycnoclineDelta*(1-exp(-z/DeepPycnoclineScale))`
- Mid pycnocline: `MidPycnoclineDelta*(1-exp(-z/MidPycnoclineScale))`
- Halocline coupling: `beta*(S(z)-35)` where beta=SalinityDensityCoeff
- Thermocline coupling: `gamma*(15-T(z))` where gamma=0.15
- **Cabbeling coupling**: `CabbelingCoeff*(S(z)-35)*(15-T(z))` = `Cc*sAnom*tAnom` where `sAnom=HaloclineDelta*(1-exp(-z/HaloclineScale))`

Total: `rho(z)=rho0+grad*z + Σ Di*(1-exp(-z/Si)) + beta*sAnom + gamma*tAnom + Cc*sAnom*tAnom`

Key difficulty: `sAnom*tAnom` expands to `HD*12*[1 -exp(-z/Hs) -exp(-z/Ts) + exp(-z*(1/Hs+1/Ts))]`. The last term has **mixed scale** `Smix = 1/(1/Hs+1/Ts) = Hs*Ts/(Hs+Ts) = 24m` which does NOT appear in any single pycnocline/halocline/thermocline definition. Your pressure integral MUST include this mixed scale or it will be >50 off.

Must be monotonic increasing, rho(0)=rho0. Tested at 30m halocline,45m deep,90m mid,200m shallow,120m therm, and 60m cabbeling mixed term – missing any term fails by >0.3.

**Cabbeling parameter (isolated cross term):**
`cab(z)=Cc*sAnom*tAnom` positive increasing saturating. Required as separate method `CabbelingParameterAtDepth`.

**Spiciness (orthogonal to density):**
`spice(z)=beta*(S(z)-35)+0.15*(T(z)-15)` – note `T-15` negative, so spice combines salinity and temperature anomalies. Surface 0. Alternative authoritative acceptable if zero at surface and matches formula `beta*(S-35)+gamma_T*(T-15)` where gamma_T=0.15. Tests verify exact formula: `Spice = SalinityDensityCoeff*(S-35) + 0.15*(T-15)`.

**Density gradient:**
Analytic derivative – you must apply product rule for cabbeling term:

`drho/dz = grad + Σ Di/Si*exp(-z/Si) + beta*dS/dz + gamma*dtAnom/dz + Cc*( dS/dz*tAnom + sAnom*dtAnom/dz )`

Must contain halocline, thermocline, 3 pycnocline, plus mixed cross contributions. Positive decreasing with depth. Must match numeric central diff `(rho(z+h)-rho(z-h))/(2h))` with h=0.05 within 5e-5 (tighter than before).

**Second derivative:**
Second derivative with second product rule:

`d2rho/dz2 = Σ -Di/Si^2*exp + beta*d2S/dz2 + gamma*d2tAnom/dz2 + Cc*( d2S*tAnom +2*dS*dtAnom + sAnom*d2tAnom )`

Negative, increasing toward 0, matches numeric diff of gradient with h=0.05 within 5e-5.

**Sound speed (SOFAR channel with quadratic pressure):**
Single authoritative formula:
`c(z)=1449.2+4.6*T(z)-0.055*T(z)^2+1.34*(S(z)-35)+0.016*z+SoundSpeedPressureQuadCoeff*z^2`
Surface ~1500, must have minimum: `c0>c200` and `c1500>c200`. Tests verify quadratic term present: expected `c200` includes `quad*200^2`.

**Sound speed gradient:**
Analytic derivative:
`dc/dz = 4.6*dT/dz -0.11*T*dT/dz +1.34*dS/dz +0.016 +2*SoundSpeedPressureQuadCoeff*z`
Must match numeric central diff of sound speed with h=0.1 within 1e-4. Tests enforce presence of T*dT term, S term, and quadratic term.

**FindSOFARAxis (numerical root-finding for sound speed minimum):**
The SOFAR minimum depth where sound speed minimal. Due to competing T decrease (lowers c) and pressure increase (raises c), c(z) has single minimum. You must implement scanning + refinement similar to equilibrium finding in Step2 but now in Step1:

Parameters (same style as Step2):
- scan points >=1000 equally spaced in [0,maxDepth]
- tolerance arg e.g. 1e-3 bisection width target
- bisection max iter 100
- No hardcoded depth

Procedure:
- Validate maxDepth>0,tolerance>0 else error containing "depth"/"tolerance". If maxDepth> 10000 error maybe? but not required.
- Scan 0..maxDepth with >=1000 steps, compute c(z). Track minimum c. Also find bracketing where gradient changes sign or c decreases then increases.
- Simpler robust: find index of minimum c in scan, then refine via ternary search or bisection on derivative: while hi-lo > tolerance, evaluate. Use SoundSpeedGradientAtDepth for refinement if possible, or ternary on c.
- Return depth of minimum. Tests compare vs brute-force 0.5m scan reference within 1m tolerance, and verify `c(axis)` is <= c(axis±5m).
- Must work for maxDepth up to 2000m.

**Potential density (no linear compression, but includes cabbeling):**
`rho_pot(z)=rho0 + D1*(1-exp(-z/S1))+D2*(1-exp(-z/S2))+D3*(1-exp(-z/S3)) + beta*sAnom + gamma*tAnom + Cc*sAnom*tAnom`
= rho(z) - grad*z. Monotonic inc, less steep than in-situ, `rho_pot < rho` at depth>0, surface = rho0.

**Potential temperature with second-order correction (uses BulkModulus and ThermobaricCoeff):**
Single authoritative definition requiring BulkModulus and ThermobaricCoeff:
`theta(z)=T(z)*(1 - P(z)/BulkModulus*1e-3 - ThermobaricCoeff*(P(z)/BulkModulus*1e-3)^2)` where `P(z)` is hydrostatic pressure from PressureAtDepth with same g=StandardGravity for evaluation. BulkModulus must be used twice (first and second order). Surface 15, monotonic decreasing, `theta <= T(z)` for z>0. Second order tiny ~ 1e-10 at 1000m but required – tests check that `theta` is NOT equal to first-order only: they compute expected with second order and verify difference from first-order at 1000m is captured.

This is ONLY acceptable formula. Do not return T(z) alone.

**Buoyancy frequency:**
`N^2 = g/rho(z) * drho/dz` positive, decreasing with depth.

**Turner angle (double-diffusive):**
`Tu = atan2( gamma*dT/dz + beta*dS/dz , beta*dS/dz - gamma*dT/dz ) * 180/pi` where gamma=0.15, beta=SalinityDensityCoeff, using `math.Atan2`. Range -90..90, not NaN.

**Double-diffusive regime classification:**
`Regime(Tu)`:
- `Tu > 45` => "salt-fingering" (or "salt-finger" accepted as containing "salt" and "finger")
- `Tu < -45` => "diffusive" (must contain "diffus" case-insensitive)
- else => "stable" or "doubly-stable" (must contain "stable")
Method `DoubleDiffusiveRegimeAtDepth` returns string, validates depth.

**Hydrostatic pressure – you must derive integral yourself (now includes cabbeling mixed term):**
Differential `dP/dz = rho(z)*g`, `P(0)=0`. Integrate analytically to closed form. Since rho contains linear + 5 exponentials + cabbeling product, integral must contain quadratic term `0.5*grad*z^2` plus 5 exponential saturation terms plus mixed scale term with `Smix=Hs*Ts/(Hs+Ts)=24m`. Do NOT approximate numerically with sum/Euler.

Derivation required: `∫ D*(1-exp(-z/S)) dz = D*(z + S*exp(-z/S) - S)`. For cabbeling: `∫ sAnom*tAnom dz = HD*12 * ∫(1 -expH -expT + exp_mix) dz` where `exp_mix=exp(-z*(1/Hs+1/Ts))`, `∫ exp_mix dz = Smix*(1 -exp(-z/Smix))` with `Smix=1/(1/Hs+1/Ts)`. So `∫ sAnom*tAnom = HD*12*[z + Hs*(expH-1) + Ts*(expT-1) + Smix*(1 -exp_mix)]`.

Full integral must contain quadratic and each distinct exponential – missing cabbeling mixed term fails by >10. Grading uses Simpson 200k reference (tightened) with rel tol 5e-4 and checks quadratic and each of 5+1 mixed terms present.

**Steric height (dynamic height / steric anomaly integral):**
Defined as `steric(z) = ∫0^z (rho(z')-rho0)/rho0 dz'` = `(Pressure(z)/g - rho0*z)/rho0` (since Pressure/g = ∫ rho). Analytically computes same mixed term. Should be positive increasing. Tests compare vs Simpson 100k of `(rho-rho0)/rho0` with rel tol 1e-3.

**Hull volume with thermal coupling (linear + quadratic):**
`V(z)=V0*exp(-k*P(z))*(1+alpha*(T(z)-15)+alpha2*(T(z)-15)^2)` where k=HullCompressibility, alpha=HullThermalExpansionCoeff=2e-4, alpha2=HullThermalExpansionQuadCoeff=1.2e-6, T thermocline, P hydrostatic. If k=0, volume still decreases ~0.2% + quadratic due to cooling. Clamped below to `MinimumVolumeFraction*V0=0.1*V0`. If depth>CrushDepth error containing "crush".

Tests verify quadratic term present: compare volume at 500m depth between linear-only thermal formula and quadratic-included formula, expecting difference >1e-4 relative, and that k=0 case volume < surface.

**Effective density at depth:** `EffectiveMass / V(z)`

## File Location
- `/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only (`math`, `errors`, `fmt`). `go vet` must pass.

## Types
```go
type Submarine struct {
    DryMass float64
    Volume float64
    Length float64
    BallastCapacity float64
    BallastLevel float64
    HullCompressibility float64
    CrushDepth float64
    DragCoefficient float64
}
type Seawater struct { Density float64 }
```

## Methods Required
- `(Submarine) Validate() error` – check DryMass>0,Volume>0,Length>0,BallastCapacity>0,BallastLevel in [0,Capacity],HullCompressibility>=0,CrushDepth>0,DragCoefficient>=0. Errors contain keywords "mass","volume","length","capacity","ballast","compressibility","crush","drag".
- `(Seawater) Validate() error` Density>0 error contains "density"
- `(Submarine) EffectiveMass() float64` = DryMass+BallastLevel
- `(Submarine) EffectiveDensity() (float64,error)` = EffectiveMass/Volume
- Seawater depth methods all validate depth>=0 else "depth":
  - `DensityAtDepth(depth) (float64,error)` – with cabbeling product, 5 exp + mixed scale 24m, monotonic
  - `CabbelingParameterAtDepth(depth) (float64,error)` – isolated Cc*sAnom*tAnom
  - `SpicinessAtDepth(depth) (float64,error)` – beta*(S-35)+0.15*(T-15), zero at surface
  - `DensityGradientAtDepth(depth) (float64,error)` – analytic with product rule, matches numeric h=0.05 tol 5e-5
  - `DensitySecondDerivativeAtDepth(depth) (float64,error)` – with second product rule, negative inc to 0, h=0.05 tol 5e-5
  - `TemperatureAtDepth(depth) (float64,error)` – thermocline
  - `TemperatureGradientAtDepth(depth) (float64,error)` – negative inc
  - `SalinityAtDepth(depth) (float64,error)` – halocline
  - `SalinityGradientAtDepth(depth) (float64,error)` – positive dec
  - `SoundSpeedAtDepth(depth) (float64,error)` – includes quadratic pressure term, SOFAR min
  - `SoundSpeedGradientAtDepth(depth) (float64,error)` – analytic: 4.6*dT/dz -0.11*T*dT/dz +1.34*dS/dz+0.016+2*quad*z
  - `FindSOFARAxis(maxDepth, tolerance float64) (float64,error)` – scanning 1000+ ternary/bisection, returns min c depth
  - `PotentialDensityAtDepth(depth) (float64,error)` – rho without grad*z but includes cabbeling
  - `PotentialTemperatureAtDepth(depth) (float64,error)` – T*(1 - P/K*1e-3 - ThermobaricCoeff*(P/K*1e-3)^2) uses BulkModulus and ThermobaricCoeff
  - `BuoyancyFrequencySquared(depth,g) (float64,error)` – g/rho*drho/dz, validate g>0
  - `TurnerAngleAtDepth(depth) (float64,error)` – Atan2 formula -90..90
  - `DoubleDiffusiveRegimeAtDepth(depth) (string,error)` – classify Turner angle: >45 salt-fingering, <-45 diffusive, else stable
  - `PressureAtDepth(depth,g) (float64,error)` – analytic integral quadratic+5 exps+mixed Smix term
  - `StericHeightAtDepth(depth,g) (float64,error)` – ∫(rho-rho0)/rho0 dz = (P/g - rho0*z)/rho0, analytic includes mixed
  - `(Submarine) VolumeAtDepth(depth,fluid,g) (float64,error)` – exp + linear+quadratic thermal clamp crush
  - `(Submarine) EffectiveDensityAtDepth(depth,fluid,g) (float64,error)`

## Functions Required
```go
func BuoyantForce(fluid Seawater, sub Submarine, g float64) (float64,error)
func WeightForce(sub Submarine, g float64) (float64,error)
func RequiredBallastForNeutral(sub Submarine, fluid Seawater) (float64,error)
func CheckSubmarineState(sub Submarine, fluid Seawater) (string,error)
func IsNeutralBuoyancyPossible(sub Submarine, fluid Seawater) (bool,error)
func BuoyantForceAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func RequiredBallastForNeutralAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func CheckSubmarineStateAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (string,error)
func IsNeutralBuoyancyPossibleAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (bool,error)
```

Buoyancy: `Fb(z)=rho(z)*V(z)*g` up, `Fw=EffectiveMass*g` down. State via Tolerance=1e-9: `|eff - fluid| <= Tol => "neutral"` else `eff<fluid => "float"` else "sink".

## Requirements
- File /app/submarine.go package submarine, 22 constants exact, structs exact, methods/functions exact signatures
- Tolerance via math.Abs, must use math.Exp, math.Abs, Atan2
- Pressure must include 0.5*grad quadratic, 5 exponentials, and mixed scale term 24m from cabbeling, 0 at surface, monotonic; Simpson 200k ref rel 5e-4 fails without cabbeling
- Volume exp+thermal linear+quadratic clamping + crush error
- No hardcoded tables, monotonic properties enforced
- New methods must be present with exact signatures
- Stdlib only, go vet passes
