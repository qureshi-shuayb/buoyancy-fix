# Step 1: Ultra-Hard Submarine Buoyancy with Dual Pycnocline & Thermal Hull

## Overview
This is **Step 1 of 2** ultra-hard multi-turn submarine simulator. You are building a Go package that models realistic ocean with **dual exponential stratification** (shallow pycnocline + deep halocline) plus **thermocline-dependent hull thermal contraction**.

Step 1 implements foundational types plus depth-aware buoyancy: surface sink/float/neutral, plus how density, its gradient, temperature, Brunt-Vaisala frequency, pressure, hull volume with thermal coupling, buoyancy, and required ballast evolve with depth. **Step 2 will reuse your types** to add continuous Clift-Gauvin drag with logistic crisis, added mass, adaptive RK4 time-to-depth, multi-root equilibrium + stability classification, and context-aware bounded fleet analysis. Define types cleanly now; do NOT rename fields/package/constants.

Goal: model a fully submerged submarine where seawater density increases non-linearly with depth due to compressibility plus dual pycnocline, temperature decreases with depth, and hull volume decays exponentially under pressure with additional thermal contraction.

## Ocean & Physics Background (Derive Formulas Yourself - No Explicit Pressure Formula Given)

**Effective mass:** DryMass + BallastLevel. Effective density = EffectiveMass / Volume at that depth.

**State decision:** Compare effective density to local seawater density using absolute tolerance `Tolerance=1e-9`. If |eff - fluid| <= Tolerance => "neutral", else if eff < fluid => "float", else "sink". Exact lower-case strings.

**Depth coordinate:** z >=0 positive downward, surface z=0.

**Seawater density with dual pycnocline:**
Ocean density has four contributions:
- Surface density `rho_surface = fluid.Density`
- Linear compressibility increase proportional to `DepthDensityGradient = 0.02 kg/m4` times depth z.
- Shallow pycnocline: `PycnoclineDelta=10.0 kg/m3` over scale `PycnoclineScale=200.0 m` via exponential relaxation `Delta1*(1 - exp(-z/Scale1))`. At surface zero, deep tends to Delta1.
- Deep halocline: `DeepPycnoclineDelta=4.5 kg/m3` over scale `DeepPycnoclineScale=45.0 m` via `Delta2*(1 - exp(-z/Scale2))`.

You must combine into single rho(z) that is monotonic increasing, starts at rho_surface at z=0, includes linear growth plus dual exponential saturation. Do not hardcode numeric examples; derive expression from description.

**Density gradient:**
Derivative `drho/dz` is needed for stability. Since rho(z) = rho0 + grad*z + D1*(1-exp(-z/S1)) + D2*(1-exp(-z/S2)), its derivative is `grad + D1/S1*exp(-z/S1) + D2/S2*exp(-z/S2)`. You must implement `DensityGradientAtDepth` that returns this analytic derivative. Monotonic decreasing with depth (since exp decays).

**Temperature profile (thermocline):**
Reference surface temperature `Tref = 15.0 C`. Temperature drops with depth as `T(z) = 15.0 - 12.0*(1 - exp(-z/ThermoclineScale))` where `ThermoclineScale=120.0 m`. So at surface T=15, at deep depth T≈3 C (12 degree drop). Monotonic decreasing, saturates. Implement `TemperatureAtDepth`.

**Brunt-Vaisala frequency squared:**
Buoyancy frequency `N^2 = g/rho * drho/dz` with z down-positive for stable stratification (positive when density increasing downward). This is classic ocean stability measure. Requires your `DensityAtDepth` for rho and `DensityGradientAtDepth` for drho/dz. Must be positive for this model, decreasing with depth as gradient decays. Implement `BuoyancyFrequencySquared(depth,g)`.

**Hydrostatic pressure:**
Differential: dP/dz = rho(z) * g where g>0. Pressure at surface zero. Pressure at depth is integral `P(z)= g* ∫_0^z rho(z') dz'`. Since rho contains linear plus dual exponentials, you must integrate analytically to obtain closed form containing polynomial (linear + quadratic) plus two exponential terms. Do NOT approximate with Euler sum or numeric integration; integrate exactly using calculus (integral of linear is quadratic, integral of 1-exp is linear + exponential). The result must be monotonic increasing, zero at surface, and include contributions from all density terms. Derive it yourself. Must involve `math.Exp` and contain both pycnocline scales.

**Compressible hull with thermal coupling:**
Submarine hull compresses under pressure and contracts thermally. Real hull follows:
`V(z) = V0 * exp(-k*P(z)) * (1 + alpha*(T(z)-Tref))` where k=HullCompressibility (1/Pa >=0), alpha=HullThermalExpansionCoeff=2.0e-4 1/K, Tref=15, T(z) thermocline temperature, P hydrostatic pressure. If k=0 and alpha=0 volume stays V0. Otherwise volume decreases monotonically with pressure and cooling, never reaching zero but clamped below by `MinimumVolumeFraction*V0 = 0.1*V0`. So final volume = max( computed , MinimumVolumeFraction*V0 ). If depth > CrushDepth => error containing case-insensitive "crush".

Thermal factor: Since T(z)-Tref negative deep, factor `1+alpha*(T-15)` <1, causing additional shrinkage ~0.2-0.5% (with alpha=2e-4 and 12 degree drop, ~0.24% reduction). Must be implemented to pass thermal volume test; missing thermal term fails.

**Effective density at depth:** EffectiveMass / V(z). Since V shrinks exponentially + thermally, effective density rises with depth.

**Buoyancy at depth:** Archimedes: `Fb(z)=rho(z)*V(z)*g` upward. Weight `Fw=EffectiveMass*g` downward independent of depth (mass constant, though added mass in step2). Required ballast for neutral at depth: `rho(z)*V(z)-DryMass`.

**State at depth:** Compare EffectiveDensityAtDepth vs local rho(z) with same Tolerance.

**Viscosity:** For step2 Reynolds, dynamic viscosity `SeawaterViscosity=0.001 Pa.s`.

## File Location and Package
- File: `/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only (`math`, `fmt`, `errors` etc). You may use `math.Exp`, `math.Pow`.
- `go vet` must pass. Do not create conflicting go.mod.
- Step2 compatibility: DO NOT rename fields/package/constants.

## Constants to Define (exact values, 12 constants)

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
const SeawaterViscosity = 0.001
const ThermoclineScale = 120.0
const HullThermalExpansionCoeff = 2.0e-4
```

You must define all twelve constants with those exact values. Tests verify existence and values.

## Types to Define

```go
type Submarine struct {
    DryMass float64
    Volume float64
    Length float64
    BallastCapacity float64
    BallastLevel float64
    HullCompressibility float64 // 1/Pa >=0
    CrushDepth float64 // m >0
    DragCoefficient float64 // >=0, base, step2 makes Re-dependent continuous
}
type Seawater struct { Density float64 }
```

Methods (you must implement):

- `(s Submarine) Validate() error` : check DryMass>0, Volume>0, Length>0, BallastCapacity>0, BallastLevel in [0,Capacity] inclusive, HullCompressibility>=0, CrushDepth>0, DragCoefficient>=0. Error message must contain keyword (case-insensitive) indicating failing field: "mass","volume","length","capacity","ballast","compressibility","crush","drag".

- `(s Submarine) EffectiveMass() float64` = DryMass+BallastLevel

- `(s Submarine) EffectiveDensity() (float64,error)` = EffectiveMass/Volume. Validate first.

- `(f Seawater) Validate() error` Density>0 else error containing "density".

- `(f Seawater) DensityAtDepth(depth) (float64,error)` : validate fluid, depth>=0 else error "depth". Return rho_surface + DepthDensityGradient*depth + PycnoclineDelta*(1-exp(-depth/PycnoclineScale)) + DeepPycnoclineDelta*(1-exp(-depth/DeepPycnoclineScale)). Must be monotonic increasing, at depth 0 equals Density, and include second exponential term (check via value at 45m scale).

- `(f Seawater) DensityGradientAtDepth(depth) (float64,error)` : analytic derivative `DepthDensityGradient + PycnoclineDelta/PycnoclineScale*exp(-depth/PycnoclineScale) + DeepPycnoclineDelta/DeepPycnoclineScale*exp(-depth/DeepPycnoclineScale)`. Validate fluid, depth>=0 else error "depth". Must be positive, decreasing with depth. Check vs numeric central diff in hidden tests.

- `(f Seawater) TemperatureAtDepth(depth) (float64,error)` : `15 - 12*(1-exp(-depth/ThermoclineScale))`. Validate fluid, depth>=0. Surface 15, monotonic decreasing, tends to 3 at depth.

- `(f Seawater) BuoyancyFrequencySquared(depth,g) (float64,error)` : `g/rho * drho/dz`. Validate fluid, depth>=0,g>0 else error "depth" or "gravity". Must be positive, decreasing with depth due to gradient saturation.

- `(f Seawater) PressureAtDepth(depth,g) (float64,error)` : validate fluid, depth>=0,g>0 else error "depth" or "gravity". Return hydrostatic integral g*∫ rho(z') dz'. You must derive closed form including linear, quadratic, and TWO exponential terms (shallow and deep). Must be 0 at depth 0, monotonic increasing, quadratic plus dual exponentials. Do NOT use numerical Euler accumulation; use analytic integral with `math.Exp`. Tests check presence of both exp terms via numeric Simpson reference.

- `(s Submarine) VolumeAtDepth(depth,fluid,g) (float64,error)` : validate sub, fluid, depth>=0,g>0, if depth>CrushDepth error "crush". If HullCompressibility==0 and HullThermalExpansionCoeff==0 return Volume constant (else still apply thermal). Compute pressure via PressureAtDepth, temperature via TemperatureAtDepth, then `V = Volume*exp(-HullCompressibility*pressure)*(1+HullThermalExpansionCoeff*(T-15))` clamped to at least MinimumVolumeFraction*Volume. Ensure monotonic decreasing for k>0 or alpha>0. If pressure huge, clamp to min fraction.

- `(s Submarine) EffectiveDensityAtDepth(depth,fluid,g) (float64,error)` = EffectiveMass / VolumeAtDepth.

## Functions to Implement (Exact Signatures)

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

Detailed same as before but now BuoyantForceAtDepth uses dual density and thermal volume.

## Requirements
1. File /app/submarine.go package submarine
2. Constants exact values (12 constants)
3. Structs exact field names/types
4. All methods/functions exact signatures plus new DensityGradient, Temperature, BuoyancyFrequencySquared
5. Tolerance via math.Abs
6. Error handling with keyword substrings
7. Stdlib only, go vet passes, must use math.Exp, math.Abs
8. Pressure must include quadratic 0.5*grad term AND dual pycnocline exponential terms (tests check via Simpson)
9. Volume exponential decay plus thermal coupling with clamping and crush
10. No hardcoded lookup tables
11. Monotonic: density and pressure increase, gradient and N^2 decrease, temperature decreases, volume decreases for k>0

## Grading (Hidden)
- Constants 12 existence/values
- EffectiveMass, EffectiveDensity
- Validate keyword checks
- DensityAtDepth: zero = surface, includes both pycnocline terms (checked via value at 45m deep scale and 200m shallow scale, missing second term error >2 kg/m3), monotonic, error handling
- DensityGradientAtDepth: analytic vs numeric central diff tol 1e-4, positive decreasing
- TemperatureAtDepth: 15 at surface, monotonic decreasing to ~3, error handling
- BuoyancyFrequencySquared: positive decreasing, matches g/rho*grad formula
- PressureAtDepth: zero at surface, monotonic, matches Simpson dual-exp reference within 1e-3 relative, checks for 0.5 factor and both exp terms, error cases
- VolumeAtDepth: incompressible constant (if k=0 and alpha=0), compressible decreases, exp behavior not linear, thermal term presence (compare with alpha=0 diff), clamping, crush error
- EffectiveDensityAtDepth: increases with depth when compressible
- BuoyantForce surface/at depth including dual pycnocline + thermal
- RequiredBallast surface/at depth
- IsPossible, CheckState with tolerance edge 5e-10 vs 1e-5
- 500 random combos monotonic state checks
- AST: must contain math.Exp at least 3 distinct uses, must contain DeepPycnoclineDelta
- go vet and race pass
