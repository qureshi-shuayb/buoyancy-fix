# Step 1: Basic Buoyancy and Geometry

## Overview
Step 1 of 3 building package `buoyancy`. Defines core types and primitives reused in Steps 2-3 (frustum, stratified integrals, compressible dynamics).

## File Location
- File: `/app/buoyancy.go`, package `buoyancy`
- Go 1.23+, stdlib only: `math`, `fmt`, `errors`, `sync`
- Must compile `GO111MODULE=off go test`, `go vet` and `go test -race` pass. File preserved for later steps.

## Constants
```go
const Tolerance = 1e-9
const StandardGravity = 9.81
```
Exact values. Must reference `Tolerance` in `CheckBuoyancyByDensity`, `ApparentWeight`, `RequiredBallastMass`. Must NOT use `StandardGravity` in `BuoyantForce`, `WeightForce`, `ApparentWeight`, `RequiredBallastMass`, `BatchCheckBuoyancy`; use passed `g`.

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
- `Object.Validate()`: validates Mass>0, Volume>0, Height>0 all finite.
- `Fluid.Validate()`: validates Density>0 finite.
- `CylinderObject.Validate()`: validates Mass>0, Radius>0, Height>0.
- `CylinderObject.Volume()`: validates Radius>0, Height>0 only. **Does NOT validate Mass.**
- `CylinderObject.Density()`: validates Mass>0, uses Volume() for geometry.
- `SphereObject.Validate()`: validates Mass>0, Radius>0.
- `SphereObject.Volume()`: validates Radius>0 only. **Does NOT validate Mass.**
- `SphereObject.Density()`: validates Mass>0, uses Volume().

## Functions
```go
func BuoyantForce(fluid Fluid, volume float64, g float64) (float64, error)
func WeightForce(mass float64, g float64) (float64, error)
func CheckBuoyancyByDensity(objDensity, fluidDensity float64) (string, error)
func CheckBuoyancy(obj Object, fluid Fluid) (string, error)
func ApparentWeight(obj Object, fluid Fluid, g float64) (float64, error)
func RequiredBallastMass(obj Object, fluid Fluid) (float64, error)
func BatchCheckBuoyancy(objs []Object, fluid Fluid, g float64) ([]BuoyancyReport, error)
```

## Behavior

- `Object.Density()`: `Mass/Volume` with overflow check post-division.
- `CylinderObject.Volume()`: `π*R²*H` via `math.Pi`.
- `SphereObject.Volume()`: `4/3*π*R³` via `math.Pi`.
- `BuoyantForce`: `fluid.Density*volume*g` via passed g.
- `WeightForce`: `mass*g`.
- `CheckBuoyancyByDensity`: "float", "sink", "neutral" lowercase; neutral when `|objDensity-fluidDensity|<=Tolerance` inclusive.
- `CheckBuoyancy`: validates Object, Fluid, delegates to `CheckBuoyancyByDensity`.
- `ApparentWeight`: if `|density-fluid.Density|<=Tolerance` returns exactly 0 else `(Mass-fluid.Density*Volume)*g`.
- `RequiredBallastMass`: if within Tolerance returns exactly 0 else `fluid.Density*Volume-Mass`.
- `BatchCheckBuoyancy`: if Fluid invalid → nil,error; if g invalid → nil,error; if `objs==nil` → `make([]BuoyancyReport,0),nil` non-nil empty; preserve order via `Index=i`; invalid Object → State="invalid" continue; valid → Density, Buoyant, Weight via g, State via CheckBuoyancyByDensity. Must be concurrent with `sync.WaitGroup` and `sync.Mutex`, race-free.

## Error Handling
All inputs >0 finite except as in Validation Rules; z/d must be >=0 where applicable. After any multiplication/division that can overflow, if result Inf or NaN return error. On error return 0 value and error containing field name: mass, volume, height, radius, density, gravity.

## General
- No external dependencies, no hardcoded tables, no redefinition of future types.
- Structs and constants exact spelling and values.
