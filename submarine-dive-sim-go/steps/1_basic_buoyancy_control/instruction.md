# Step 1: Submarine Buoyancy with Depth-Dependent Ocean & Compressible Hull

## Overview
This is **Step 1 of 2** in a multi-turn submarine simulator. You are building a Go package that models submarine buoyancy with realistic ocean stratification and pressure-compressible hull.

Step 1 implements foundational types plus depth-aware buoyancy: surface sink/float/neutral decisions, plus how density, pressure, hull volume, buoyant force, and required ballast change with depth. **Step 2 will extend the same package** to include drag, terminal velocity, equilibrium depth search via bisection, RK4 time-to-depth integration, and fleet batch processing. Step 2 must reuse your `Submarine` and `Seawater` types without redefining them — so define them cleanly now.

Goal: model a fully submerged submarine where seawater density increases with depth and hull volume shrinks under pressure.

## Ocean & Physics Background

**Effective mass:** DryMass + BallastLevel. Effective density = EffectiveMass / Volume.

**State decision:** Compare effective density to seawater density with absolute tolerance 1e-9. If |eff - fluid| <= Tolerance => "neutral", else if eff < fluid => "float", else "sink". Exact lower-case strings.

**Depth-dependent ocean:** In this simplified model density grows linearly with depth:
- `rho(z) = rho_surface + DepthDensityGradient * z`
where `DepthDensityGradient = 0.02 kg/m4`, z >=0 depth positive downward. At surface z=0 rho = surface.

**Hydrostatic pressure:** Pressure at depth is integral of rho(z')*g dz' from 0 to z. For linear density `rho(z')=rho0+grad*z'`, integral yields `P(z)=g*∫(rho0+grad*z')dz' = g*(rho0*z + 0.5*grad*z^2)`. The 0.5 comes from integrating z' to z²/2. Implement:
- `P(z) = g * (rho_surface * z + 0.5 * DepthDensityGradient * z^2)`
It is 0 at surface, monotonic increasing, quadratic in depth. g is gravity.

**Compressible hull:** Volume shrinks under pressure:
- `V(z) = V0 * (1 - HullCompressibility * P(z))` clamped to at least `MinimumVolumeFraction * V0` (0.1). If `HullCompressibility=0` volume stays constant. If depth > CrushDepth => error containing "crush".

**Effective density at depth:** EffectiveMass / V(z)

**Buoyancy at depth:** `Fb(z) = rho(z) * V(z) * g` (weight of displaced fluid). Weight `Fw = EffectiveMass * g` independent of depth. Required ballast for neutral at depth: `rho(z)*V(z) - DryMass` (may be outside [0,Capacity]).

**State at depth:** Compare EffectiveDensityAtDepth vs rho(z) with same Tolerance.

## File Location and Package
- File: `/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only (`math`, `fmt`, `errors` etc)
- `go vet` must pass. Do not create conflicting go.mod.
- Step2 compatibility: DO NOT rename fields/package/constants.

## Constants to Define (exact)

```go
const Tolerance = 1e-9
const StandardGravity = 9.81
const StandardSeawaterDensity = 1025.0
const DepthDensityGradient = 0.02
const MinimumVolumeFraction = 0.1
```

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
    DragCoefficient float64 // >=0
}
type Seawater struct { Density float64 }
```

Methods:
- `(s Submarine) Validate() error` : check DryMass>0, Volume>0, Length>0, BallastCapacity>0, BallastLevel in [0,Capacity], HullCompressibility>=0, CrushDepth>0, DragCoefficient>=0. Error message must contain keyword: "mass","volume","length","capacity","ballast","compressibility","crush","drag" case-insensitive for relevant failure.
- `(s Submarine) EffectiveMass() float64` = DryMass+BallastLevel
- `(s Submarine) EffectiveDensity() (float64,error)` = EffectiveMass/Volume
- `(f Seawater) Validate() error` Density>0
- `(f Seawater) DensityAtDepth(depth) (float64,error)` : depth>=0 else error containing "depth", fluid valid, rho = Density + DepthDensityGradient*depth
- `(f Seawater) PressureAtDepth(depth,g) (float64,error)` : depth>=0,g>0 else error, P = g*(Density*depth + 0.5*DepthDensityGradient*depth^2)
- `(s Submarine) VolumeAtDepth(depth,fluid,g) (float64,error)` : validate all, if depth>CrushDepth error "crush", P via PressureAtDepth, V = Volume*(1-HullCompressibility*P) clamped to MinimumVolumeFraction*Volume, if HullCompressibility==0 return Volume
- `(s Submarine) EffectiveDensityAtDepth(depth,fluid,g) (float64,error)` = EffectiveMass / VolumeAtDepth

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

Detailed:

- **BuoyantForce** surface: fluid.Density * sub.Volume * g, validate fluid,sub,g>0
- **WeightForce**: EffectiveMass*g
- **BuoyantForceAtDepth**: rhoAtDepth * volAtDepth * g, validate depth>=0,g>0,crush
- **RequiredBallastForNeutral** surface: rho_surface*Volume - DryMass, validate dry properties + fluid (not BallastLevel)
- **RequiredBallastForNeutralAtDepth**: rhoAtDepth*volAtDepth - DryMass, validate dry+depth+g, may be negative or >Capacity
- **CheckSubmarineState** surface: effective vs fluid with Tolerance
- **CheckSubmarineStateAtDepth**: effectiveAtDepth vs rhoAtDepth with Tolerance, check crush
- **IsNeutralBuoyancyPossible** surface and at depth: required in [0,Capacity]

## Requirements
1. File /app/submarine.go package submarine
2. Constants exact values
3. Structs exact field names/types
4. All functions exact signatures
5. Tolerance handling
6. Error handling with keywords
7. Stdlib only, go vet passes
8. Pressure must use quadratic formula (tests check 0.5*grad term)
9. Volume clamping and crush

## Grading
Hidden tests check constants, EffectiveMass, Validate keywords, DensityAtDepth, PressureAtDepth monotonic and quadratic term, VolumeAtDepth clamping and crush, EffectiveDensityAtDepth, BuoyantForce surface/at depth, RequiredBallast, IsPossible, CheckState with tolerance 5e-10 vs 1e-5.

## Anti-Cheating
Do not hardcode lookup, must compute. Tolerance via math.Abs, not ==.
