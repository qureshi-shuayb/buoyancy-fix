# Step 1: Basic Buoyancy and Geometry

## Overview
Step 1 of 3 building package `buoyancy`. Defines core types and primitives reused in Steps 2-3.

## File Location
- File: `/app/buoyancy.go`, package `buoyancy`
- Go 1.23+, stdlib only: `math`, `fmt`, `errors`, `sync`
- Must compile `GO111MODULE=off go test`, `go vet` and `go test -race` pass. File preserved.

## Constants
```go
const Tolerance = 1e-9
const StandardGravity = 9.81
```
Exact values. Must reference `Tolerance` in `CheckBuoyancyByDensity`, `ApparentWeight`, `RequiredBallastMass`, `IsNeutrallyBuoyant`. Must NOT use `StandardGravity` in `BuoyantForce`, `WeightForce`, `ApparentWeight`, `RequiredBallastMass`, `BatchCheckBuoyancy`; use passed `g`.

## Types
```go
type Object struct { Mass, Volume, Height float64 }
type Fluid struct { Density float64 }
type CylinderObject struct { Mass, Radius, Height float64 }
type SphereObject struct { Mass, Radius float64 }
type BuoyancyReport struct { Index int; State string; Density, BuoyantForce, WeightForce float64 }
```

## Validation Rules

- `Object.Density()`: validates Mass>0 finite, Volume>0 finite.
- `Object.Validate()`: validates Mass>0, Volume>0, Height>0 finite.
- `Fluid.Validate()`: validates Density>0 finite.
- `CylinderObject.Validate()`: validates Mass>0, Radius>0, Height>0 finite.
- `CylinderObject.Volume()`: validates Radius>0, Height>0 finite.
- `CylinderObject.Density()`: validates Mass>0 finite.
- `SphereObject.Validate()`: validates Mass>0, Radius>0 finite.
- `SphereObject.Volume()`: validates Radius>0 finite.
- `SphereObject.Density()`: validates Mass>0 finite.
- All validations must reject non-finite (NaN/Inf).

## Functions
```go
func BuoyantForce(fluid Fluid, volume float64, g float64) (float64, error)
func WeightForce(mass float64, g float64) (float64, error)
func CheckBuoyancyByDensity(objDensity, fluidDensity float64) (string, error)
func CheckBuoyancy(obj Object, fluid Fluid) (string, error)
func ApparentWeight(obj Object, fluid Fluid, g float64) (float64, error)
func RequiredBallastMass(obj Object, fluid Fluid) (float64, error)
func BatchCheckBuoyancy(objs []Object, fluid Fluid, g float64) ([]BuoyancyReport, error)
func IsNeutrallyBuoyant(objDensity, fluidDensity float64) (bool, error)
```

## Behavior

- `Object.Density()`: `Mass/Volume`.
- `CylinderObject`: `Volume()` is `π*R²*H` via `math.Pi`; `Density()` must call `Volume()` for geometry (not recompute). `SphereObject`: `Volume()` `4/3*π*R³` via `math.Pi`; `Density()` must call `Volume()`.
- `BuoyantForce`: `fluid.Density*volume*g` using passed `g`. `WeightForce`: `mass*g`.
- `CheckBuoyancyByDensity`: returns "float"/"sink"/"neutral" lowercase; neutral when `|objDensity-fluidDensity|<=Tolerance` inclusive.
- `CheckBuoyancy`: validates Object, Fluid, delegates to density version.
- `ApparentWeight`: returns neutral handling with exact zero when within tolerance, otherwise `(Mass-fluid.Density*Volume)*g`.
- `RequiredBallastMass`: returns exact zero within tolerance, otherwise `fluid.Density*Volume-Mass`.
- `IsNeutrallyBuoyant`: validates densities >0 finite, returns whether within Tolerance using Tolerance constant.
- `BatchCheckBuoyancy`: order and invalid handling with concurrency, race-free with `WaitGroup`+`Mutex` (or via shared helper).
- All error returns must be zero-value (or nil,error) and error message contains relevant field name.

## Error Handling

Explicit mapping, error must contain field name case-insensitive:
- Mass invalid → contains "mass"
- Volume invalid → contains "volume"
- Height invalid → contains "height"
- Radius invalid → contains "radius"
- Density invalid → contains "density"
- g invalid → contains "gravity"
- depth/d invalid → contains "depth"
Return 0 value and non-nil error on invalid.

## Overflow Handling

After any multiplication or division that can overflow, if intermediate or final result is Inf or NaN return error.
Example: `BuoyantForce(Fluid{Density:1e200},1e200,1e10)` must error not return Inf.
Example: `Object{Mass:1e308,Volume:1e-308,Height:1}.Density()` must error.
Example: `CylinderObject{Mass:1,Radius:1e150,Height:1e150}.Volume()` must error.
Tiny values like `1e-9` or `1e-12` must still succeed.

## General
- No external deps, no hardcoded tables, exact spelling and values.
