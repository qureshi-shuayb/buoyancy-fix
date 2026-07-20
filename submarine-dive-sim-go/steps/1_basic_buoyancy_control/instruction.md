# Step 1: Ultra Super-Hard Submarine — Triple Pycnocline + Halocline + Thermocline

## Overview
Step 1 of 2. Build Go package `submarine` modeling realistic stratified ocean: triple exponential pycnocline (shallow/mid/deep), halocline salinity, thermocline temperature with T/S coupling to density. Includes analytic gradients, second derivative, sound speed SOFAR minimum, potential density, potential temperature using BulkModulus, Brunt-Vaisala frequency, Turner angle, hydrostatic pressure integral, and exponential hull with thermal contraction.

Step 2 will reuse your types/constants/methods without redefinition. Define them cleanly now.

## Constants (exact values, 18)

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
```

Fixed scalars: reference salinity 35 psu, reference temperature 15 C, thermal density coefficient gamma=0.15 kg/m3 per C (fixed, not a constant), salinity coefficient beta=SalinityDensityCoeff=0.8.

All 18 must be defined exactly. Tests verify existence and values.

## Ocean Model (derive analytically, no numeric approximation for pressure)

Coordinate: z >=0 positive downward, surface z=0. All depth args must validate >=0 else error containing "depth". g validation >0 else "gravity".

**Salinity (halocline):**
`S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale))`
Surface 35, deep ~37.5, monotonic inc saturating.

- `dS/dz = HaloclineDelta/HaloclineScale*exp(-z/HaloclineScale)` positive decreasing.

**Temperature (thermocline):**
`T(z)=15-12*(1-exp(-z/ThermoclineScale))`
Surface 15C, deep ~3C, monotonic dec.

- `dT/dz = -12/ThermoclineScale*exp(-z/ThermoclineScale)` negative increasing toward 0.

**Density with triple pycnocline + T/S coupling:**
Contributions:
- `rho0 = fluid.Density` (surface reference)
- Linear compressibility `DepthDensityGradient*z` where grad=0.02 kg/m4
- Shallow: `PycnoclineDelta*(1-exp(-z/PycnoclineScale))`
- Deep: `DeepPycnoclineDelta*(1-exp(-z/DeepPycnoclineScale))`
- Mid: `MidPycnoclineDelta*(1-exp(-z/MidPycnoclineScale))`
- Halocline coupling: `SalinityDensityCoeff*(S(z)-35)` = `beta*HaloclineDelta*(1-exp(-z/HaloclineScale))`
- Thermocline coupling: `0.15*(15-T(z))` = `0.15*12*(1-exp(-z/ThermoclineScale))`

`rho(z)=rho0+grad*z + D1*(1-exp(-z/S1))+D2*(1-exp(-z/S2))+D3*(1-exp(-z/S3)) + beta*(S-35)+0.15*(15-T)`

Must contain 5 distinct exp terms, monotonic inc, rho(0)=rho0. Tested at 30m (halocline),45m deep,90m mid,200m shallow,120m therm – each missing term fails.

**Density gradient:**
Analytic derivative of rho(z). Must contain 5 exp terms, positive decreasing with depth, matches numeric central diff `(rho(z+h)-rho(z-h))/(2h)` with h=0.1 within 1e-4.

Do not give implementation away – derive `drho/dz = grad + Σ Di/Si*exp(-z/Si) + beta*dS/dz + 0.15*(-dT/dz)`.

**Second derivative:**
`d2rho/dz2` analytic, negative, increasing toward 0, matches numeric diff of gradient with h=0.1 within 1e-4.

**Sound speed (SOFAR channel):**
Single authoritative formula:
`c(z)=1449.2+4.6*T(z)-0.055*T(z)^2+1.34*(S(z)-35)+0.016*z`
Surface ~1500, must have minimum: `c0>c200` and `c1500>c200`.

**Potential density (no linear compression):**
Single authoritative:
`rho_pot(z)=rho0 + D1*(1-exp(-z/S1))+D2*(1-exp(-z/S2))+D3*(1-exp(-z/S3)) + beta*(S(z)-35)+0.15*(15-T(z))`
= rho(z) - grad*z. Monotonic inc, less steep than in-situ, `rho_pot < rho` at depth>0, surface = rho0.

**Potential temperature (uses BulkModulus):**
Single authoritative definition:
`theta(z)=T(z)*(1 - P(z)/BulkModulus*1e-3)` where `P(z)` is hydrostatic pressure from PressureAtDepth with same g=StandardGravity for evaluation. BulkModulus must be used. Surface 15, monotonic decreasing, `theta <= T(z)` for z>0. Tiny correction ~1e-5 at 1000m but required.

This is the ONLY acceptable formula. Do not return T(z) alone.

**Buoyancy frequency:**
`N^2 = g/rho(z) * drho/dz` positive, decreasing with depth.

**Turner angle (double-diffusive):**
Single authoritative:
`Tu = atan2( gamma*dT/dz + beta*dS/dz , beta*dS/dz - gamma*dT/dz ) * 180/pi` where gamma=0.15, beta=SalinityDensityCoeff, using `math.Atan2`. Range -90..90, not NaN.

**Hydrostatic pressure – you must derive integral yourself:**
Differential `dP/dz = rho(z)*g`, `P(0)=0`. Integrate analytically to closed form. Since rho contains linear + 5 exponentials, integral must contain quadratic term `0.5*grad*z^2` plus 5 exponential saturation terms. Do NOT approximate numerically with sum/Euler. Must be monotonic inc, 0 at surface. Grading uses Simpson 100k reference with rel tol 1e-3 and checks quadratic and each of 5 exp terms present (missing mid pycnocline fails).

Derivation hint: `∫ D*(1-exp(-z/S)) dz = D*(z + S*exp(-z/S) - S)` – you must apply this to all 5 terms. Do not hardcode numeric coefficients.

**Hull volume with thermal coupling:**
`V(z)=V0*exp(-k*P(z))*(1+alpha*(T(z)-15))` where k=HullCompressibility, alpha=HullThermalExpansionCoeff=2e-4, T(z) thermocline, P hydrostatic. If k=0, volume still decreases ~0.2% due to cooling. Clamped below to `MinimumVolumeFraction*V0=0.1*V0`. If depth>CrushDepth error containing "crush".

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
  - `DensityAtDepth(depth) (float64,error)` – 5 exp formula above
  - `DensityGradientAtDepth(depth) (float64,error)` – analytic, positive decreasing
  - `DensitySecondDerivativeAtDepth(depth) (float64,error)` – negative inc to 0
  - `TemperatureAtDepth(depth) (float64,error)` – thermocline
  - `TemperatureGradientAtDepth(depth) (float64,error)` – negative inc
  - `SalinityAtDepth(depth) (float64,error)` – halocline
  - `SalinityGradientAtDepth(depth) (float64,error)` – positive dec
  - `SoundSpeedAtDepth(depth) (float64,error)` – SOFAR min
  - `PotentialDensityAtDepth(depth) (float64,error)` – rho without grad*z
  - `PotentialTemperatureAtDepth(depth) (float64,error)` – T*(1-P/(BulkModulus)*1e-3) uses BulkModulus
  - `BuoyancyFrequencySquared(depth,g) (float64,error)` – g/rho*drho/dz, validate g>0
  - `TurnerAngleAtDepth(depth) (float64,error)` – Atan2 formula -90..90
  - `PressureAtDepth(depth,g) (float64,error)` – analytic integral quadratic+5 exps
  - `(Submarine) VolumeAtDepth(depth,fluid,g) (float64,error)` – exp+thermal clamp crush
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
- File /app/submarine.go package submarine, 18 constants exact, structs exact, methods/functions exact signatures
- Tolerance via math.Abs
- Stdlib only, go vet passes, must use math.Exp, math.Abs, Atan2
- Pressure must include 0.5*grad quadratic and 5 exps, 0 at surface, monotonic
- Volume exp+thermal clamping + crush error
- No hardcoded tables
- Monotonic properties enforced by tests
