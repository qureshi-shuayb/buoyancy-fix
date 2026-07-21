# Step 1: Basic Buoyancy and Geometry

## Overview
This is Step 1 of 3 building package `buoyancy`. It defines core types and buoyancy primitives reused in Steps 2-3, which extend to frustum geometries, stratified fluid integrals, and compressible dynamics.

## File Location
- File: `/app/buoyancy.go`
- Package: `buoyancy`
- Go 1.23+, standard library only: `math`, `fmt`, `errors`, `sync` (for concurrent batch)
- Must compile with `GO111MODULE=off go test` and `go vet` must pass. File is preserved for later steps.

## Constants
```go
const Tolerance = 1e-9
const StandardGravity = 9.81
```
Exact values required. Tolerance must be referenced in `CheckBuoyancyByDensity`, `ApparentWeight`, `RequiredBallastMass`. `StandardGravity` must not be used in `BuoyantForce`, `WeightForce`, `ApparentWeight`, `RequiredBallastMass`, `BatchCheckBuoyancy`; use passed `g`.

## Types
```go
type Object struct {
    Mass   float64
    Volume float64
    Height float64
}
type Fluid struct {
    Density float64
}
type CylinderObject struct {
    Mass   float64
    Radius float64
    Height float64
}
type SphereObject struct {
    Mass   float64
    Radius float64
}
type BuoyancyReport struct {
    Index        int
    State        string
    Density      float64
    BuoyantForce float64
    WeightForce  float64
}
```
Methods:
```go
func (o Object) Density() (float64, error)
func (o Object) Validate() error
func (f Fluid) Validate() error
func (c CylinderObject) Validate() error
func (c CylinderObject) Volume() (float64, error)
func (c CylinderObject) Density() (float64, error)
func (s SphereObject) Validate() error
func (s SphereObject) Volume() (float64, error)
func (s SphereObject) Density() (float64, error)
```

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
- `Object.Density()`: `Mass/Volume`, validates Mass and Volume only; Height is not validated for this method. `Validate()` validates Mass, Volume, Height.
- `CylinderObject.Volume()`: `π*R²*H` using `math.Pi`, validates Radius and Height only; Mass is not validated. `SphereObject.Volume()`: `4/3*π*R³` using `math.Pi`, validates Radius only.
- `CylinderObject.Density()` and `SphereObject.Density()`: Mass / Volume, Mass must be >0.
- `BuoyantForce`: `fluid.Density * volume * g` using passed `g`. `WeightForce`: `mass * g`.
- `CheckBuoyancyByDensity`: validates both densities >0 finite, returns "float", "sink", or "neutral" lowercase. Neutral when `|objDensity - fluidDensity| <= Tolerance` inclusive.
- `CheckBuoyancy`: validates Object and Fluid, computes density via `Density()`, delegates to `CheckBuoyancyByDensity`.
- `ApparentWeight`: validates Object, Fluid, g>0 finite. If `|density - fluid.Density| <= Tolerance`, returns exactly 0. Otherwise `(Mass - fluid.Density*Volume)*g`.
- `RequiredBallastMass`: validates Object, Fluid. If `|density - fluid.Density| <= Tolerance`, returns exactly 0. Otherwise `fluid.Density*Volume - Mass`.
- `BatchCheckBuoyancy`: validates Fluid and g>0 finite; if Fluid invalid return `nil, error`, if g invalid return `nil, error`. If `objs==nil` return non-nil empty slice via `make([]BuoyancyReport,0), nil`. Results length equals input length, order preserved via `Index = i`. Invalid Object → `State="invalid"`, zero other fields, continue. Valid → compute Density, BuoyantForce, WeightForce using passed g, State via `CheckBuoyancyByDensity`. Must be concurrent using `sync.WaitGroup` and `sync.Mutex`, preserve order via Index, race-free (`go test -race` must pass).

## Error Handling
All numeric inputs must be >0 and finite (not NaN/Inf). After any multiplication or division that can overflow, if result is Inf or NaN, return error. On error return 0 value and non-nil error with field name case-insensitive: mass, volume, height, radius, density, gravity as appropriate.

## General
- No external dependencies, no hardcoded tables.
- Structs and constants must have exact spelling and values.
