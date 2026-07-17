# Step 1: Basic Buoyancy Float / Sink / Neutral Check in Go

## Overview
This is **Step 1 of 2** in a multi-turn T-Bench task. You are building a Go package that models buoyancy via Archimedes' principle.

Goal: Given an object's mass/volume and fluid density, determine whether it floats, sinks, or is neutrally buoyant. Step 2 will reuse the types you define here to compute quantitative submersion, including non-linear conical geometry.

## Physics Background
Archimedes' principle: an object immersed in fluid experiences an upward buoyant force:

```
Fb = rho_fluid * V_displaced * g
Fw = m_object * g
```

Where:
- `rho_fluid` = fluid density (kg/m^3)
- `rho_object` = object density = mass / volume
- `V_displaced` = volume of fluid displaced
- `g` = gravitational acceleration

For a fully immersed comparison, compare densities with a tolerance to decide float/sink/neutral. Simple equality fails near the boundary — use the provided tolerance constant.

## File Location and Package

- Implement in single file: `/app/buoyancy.go`
- Package: `buoyancy`
- Go 1.23+, standard library only. No external imports beyond `math`, `fmt`, `errors` (if needed).
- File must compile standalone (tests will `go test` with `package buoyancy`).
- Do not create `go.mod` with conflicting module name; `go vet` must pass.

## Constants to Define

You MUST define and use these exported constants:

```go
const Tolerance = 1e-9          // absolute density tolerance for neutral buoyancy (kg/m^3)
const StandardGravity = 9.81    // m/s^2
```

`Tolerance` is the maximum absolute difference between object and fluid density that still counts as neutral.

## Types to Define

```go
// Object represents a physical body. All fields must be > 0 to be valid.
type Object struct {
    Mass   float64 // kg, >0
    Volume float64 // m^3, >0
    Height float64 // m, total vertical height when upright, >0
}

type Fluid struct {
    Density float64 // kg/m^3, >0
}
```

Methods:
- `func (o Object) Density() (float64, error)` — returns `o.Mass / o.Volume`. Error if `Volume <= 0` or `Mass <= 0`. Error message must contain "volume" or "mass" (case-insensitive).
- `func (o Object) Validate() error` — error if any of Mass, Volume, Height <= 0.
- `func (f Fluid) Validate() error` — error if Density <= 0.

Use `errors.New` or `fmt.Errorf`; exact wording not checked, but must be non-nil errors.

## Functions to Implement (Exact Signatures)

```go
func BuoyantForce(fluid Fluid, volume float64, g float64) (float64, error)
func WeightForce(mass float64, g float64) (float64, error)
func CheckBuoyancyByDensity(objDensity, fluidDensity float64) (string, error)
func CheckBuoyancy(obj Object, fluid Fluid) (string, error)
```

All functions must be exported.

### Detailed Behavior

**BuoyantForce**:
- Validate `fluid.Density >0`, `volume >0`, `g >0`. If invalid, return 0 and error.
- Return `fluid.Density * volume * g`.

**WeightForce**:
- Validate `mass >0`, `g >0`. Else error.
- Return `mass * g`.

**CheckBuoyancyByDensity**:
- Validate densities >0, else error.
- Use `Tolerance` to decide neutral vs float/sink. Return exactly "float", "sink", or "neutral" lower-case.
- Float when object less dense than fluid beyond tolerance, sink when greater.

**CheckBuoyancy**:
- Validate Object and Fluid via their Validate methods and Density.
- Delegate to `CheckBuoyancyByDensity`.

## Requirements

1. File location `/app/buoyancy.go`, `package buoyancy`.
2. Define constants `Tolerance` and `StandardGravity` exactly with those values.
3. Define `Object` and `Fluid` structs exactly as specified.
4. Implement all 4 functions + 3 methods with exact signatures; keep them exported.
5. Tolerance handling required for neutral buoyancy. Tests include boundary cases where densities differ by ~1e-10 (neutral) vs 1e-5 (not neutral).
6. Error handling: Return non-nil error on any non-positive input. Don't panic.
7. No external dependencies: stdlib only.
8. Deterministic pure functions.
9. Step 2 compatibility: Do NOT rename fields or package. Step 2 will reuse your types for prismatic and conical submersion calculations. If you change names, Step 2 fails cascade.
10. Clean `go vet` must pass.

## Grading (Hidden Tests)

Tests will check:
- Constants values, `Object.Density()`, `Validate()` errors
- `BuoyantForce` and `WeightForce` formulas within 1e-6
- `CheckBuoyancyByDensity` for float/sink/neutral including tolerance boundaries
- Integration via `CheckBuoyancy` with struct validation
- No hardcoding per object name; must compute via formulas

## What NOT to Do

- Do NOT hardcode return values per object name or density lookup table
- Do NOT skip tolerance check with `==`; must use `Tolerance`
- Do NOT hide `/app/buoyancy.go` behind another module
- Do NOT modify test files
