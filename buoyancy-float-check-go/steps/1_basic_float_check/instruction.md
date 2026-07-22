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

- `Object.Density()`: validates Mass>0 finite, Volume>0 finite. **Does NOT validate Height.**
- `Object.Validate()`: validates Mass>0, Volume>0, Height>0.
- `Fluid.Validate()`: validates Density>0.
- `CylinderObject.Validate()`: validates Mass>0, Radius>0, Height>0.
- `CylinderObject.Volume()`: validates Radius>0, Height>0 only. **Does NOT validate Mass.**
- `CylinderObject.Density()`: validates Mass>0.
- `SphereObject.Validate()`: validates Mass>0, Radius>0.
- `SphereObject.Volume()`: validates Radius>0 only. **Does NOT validate Mass.**
- `SphereObject.Density()`: validates Mass>0.

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

- `Object.Density()`: `Mass/Volume`, must use `Volume()` call for Cylinder/Sphere variants.
- `CylinderObject.Volume()`: `π*R²*H` via `math.Pi`. `SphereObject.Volume()`: `4/3*π*R³` via `math.Pi`.
- `BuoyantForce`: `fluid.Density*volume*g` via passed g. `WeightForce`: `mass*g`.
- `CheckBuoyancyByDensity`: "float"/"sink"/"neutral" lowercase; neutral when `|objDensity-fluidDensity|<=Tolerance` inclusive. Test with 0.999*Tol→neutral, 1.001*Tol→non-neutral, exact Tol inclusive.
- `CheckBuoyancy`: validates Object, Fluid, delegates.
- `ApparentWeight`: if `|density-fluid.Density|<=Tolerance` returns exactly 0 else `(Mass-fluid.Density*Volume)*g`. Must check intermediate `rhoV=fluid.Density*Volume` for overflow before diff.
- `RequiredBallastMass`: if within Tolerance returns exactly 0 else `fluid.Density*Volume-Mass`.
- `IsNeutrallyBuoyant`: validates densities >0 finite, returns `|diff|<=Tolerance` using Tolerance constant, error contains "density".
- `BatchCheckBuoyancy`: Fluid invalid→nil,error; g invalid→nil,error; `objs==nil`→`make(...,0),nil`; order via `Index=i`; invalid→State="invalid" continue; concurrent `WaitGroup`+`Mutex` race-free.
- Negative zero: `Mass=-0.0` invalid must error (requires `<=0` not `<0`).
- Zero value on error: On any error return exactly 0 value (or nil,error or non-nil empty for batch nil case) not NaN/Inf/partial.
- Intermediate overflow: `ApparentWeight` must check `rhoV` for Inf before computing diff.

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
