# Step 1: Basic Buoyancy Float / Sink / Neutral Check in Go

## Overview
This is **Step 1 of 3** in a multi-turn T-Bench task. You are building a Go package that models buoyancy via Archimedes' principle.

Goal: Given an object's mass/volume and fluid density, determine whether it floats, sinks, or is neutrally buoyant. Step 2 will reuse the types you define here to compute quantitative submersion in uniform fluid (prismatic, conical, frustum) PLUS stratified ocean where density varies with depth and buoyant mass is integral ∫rho(z)A(z)dz requiring numeric root-finding. Step 3 will add compressible dynamics with pressure integral, crush, drag and RK4. Keep your Step 1 types clean and reusable - this is the foundation for a valid multi-turn gradient.

This is now a 3-step task where the reference shows **Avocado must have a fail on every step**. If Step1 is 5/5 (1.0), the whole task fails per multi-turn rules (no 1.0 Avocado step in 3-step task).

## Physics Background
Archimedes' principle: an object immersed in fluid experiences an upward buoyant force:
```
Fb = rho_fluid * V_displaced * g
Fw = m_object * g
```
Where `rho_object = mass / volume`. Fully immersed state is determined by comparing average densities, but simple `==` fails near the boundary due to floating-point and physical tolerance – you must use the provided tolerance constant for neutral buoyancy decision. No explicit neutrality formula is given in tests spoiler – derive from `Tolerance`.

Where:
- `rho_fluid` = fluid density (kg/m^3)
- `rho_object` = object density = mass / volume
- `V_displaced` = volume of fluid displaced
- `g` = gravitational acceleration

Your implementation will be tested with cases where object and fluid densities differ by ~1e-10 (should be neutral) vs 1e-5 and larger (should be float/sink). Simple equality will fail these.

## File Location and Package
- Implement in single file: `/app/buoyancy.go`
- Package: `buoyancy`
- Go 1.23+, standard library only. No external imports beyond `math`, `fmt`, `errors`.
- File must compile standalone (tests will `go test` with `package buoyancy`).
- Do not create `go.mod` with conflicting module name; `go vet` must pass.
- This file will be preserved and checked by AST in Step 2/3 (no redefinition allowed).

## Constants to Define
You MUST define and use these exported constants:
```go
const Tolerance = 1e-9          // absolute density tolerance for neutral buoyancy (kg/m^3)
const StandardGravity = 9.81    // m/s^2
```
`Tolerance` is the maximum absolute difference between object and fluid density that still counts as neutral. You must actually reference this constant in `CheckBuoyancyByDensity` – hardcoding `1e-9` in logic without using the constant may be flagged by AST and fails if constant value changes in hidden tests.

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
- `func (o Object) Density() (float64, error)` — returns `o.Mass / o.Volume`. Error if `Volume <= 0` or `Mass <= 0`. Error message must contain "volume" or "mass" (case-insensitive). Hidden tests check substring.
- `func (o Object) Validate() error` — error if any of Mass, Volume, Height <= 0. Must distinguish invalid object.
- `func (f Fluid) Validate() error` — error if Density <= 0. Must be non-nil.

Use `errors.New` or `fmt.Errorf`; exact wording not checked besides substring requirements.

## Functions to Implement (Exact Signatures)
```go
func BuoyantForce(fluid Fluid, volume float64, g float64) (float64, error)
func WeightForce(mass float64, g float64) (float64, error)
func CheckBuoyancyByDensity(objDensity, fluidDensity float64) (string, error)
func CheckBuoyancy(obj Object, fluid Fluid) (string, error)
```
All functions must be exported and exist with exact signatures - checked by Go vet and reflection.

### Detailed Behavior

**BuoyantForce**:
- Validate `fluid.Density >0`, `volume >0`, `g >0`. If invalid, return 0 and error containing relevant term (density/volume/gravity).
- Return `fluid.Density * volume * g` (Archimedes).

**WeightForce**:
- Validate `mass >0`, `g >0`. Else error containing "mass" or "gravity".
- Return `mass * g`.

**CheckBuoyancyByDensity**:
- Validate densities >0, else error.
- Must use `Tolerance` to decide neutral vs float/sink. Return exactly "float", "sink", or "neutral" lower-case, no spaces.
- Float when object less dense than fluid beyond tolerance, sink when greater, neutral when within tolerance. Must work for both directions (object heavier and lighter).
- Must not use `==` for float equality.

**CheckBuoyancy**:
- Validate Object and Fluid via their Validate methods and Density.
- Must delegate to `CheckBuoyancyByDensity` conceptually - should compute `rho_avg` and check state via that function. If object is exactly neutral within tolerance, return neutral.

## Requirements (Hardened for Gradient)
1. File location `/app/buoyancy.go`, `package buoyancy`.
2. Define constants `Tolerance` and `StandardGravity` exactly with those values and use them.
3. Define `Object` and `Fluid` structs exactly as specified.
4. Implement all 4 functions + 3 methods with exact signatures; keep them exported.
5. **Tolerance handling required and non-trivial:** hidden tests include `diff=5e-10` (neutral), `diff=0.9*Tol` neutral, `diff=1.1*Tol` float/sink, `diff=1e-10` neutral vs `1e-5` not neutral. Simple `==` or missing tolerance fails these and creates Avocado 0/3 vs Oracle 3/3 gradient.
6. Error handling: Return non-nil error on any non-positive input, message must contain relevant keyword ("volume", "mass", "density", "gravity") case-insensitive. Don't panic.
7. No external dependencies: stdlib only. `go vet` must pass, no hardcoded lookup tables.
8. Step 2/3 compatibility: Do NOT rename fields or package. Step 2 will reuse your types for prismatic, conical, frustum uniform plus stratified integral buoyancy (quadratic/quartic). If you change names, Step 2 fails cascade. Step 2 must not redefine your types (AST check).
9. Deterministic pure functions, no randomness.
10. Must handle reduction: object with `Mass=1000, Volume=1, Height=2, Fluid 1000` => neutral exact; `Mass=1000+5e-10` => neutral (within Tol); `Mass=1200` => sink clamped.

## Grading (Hidden Tests)
Tests will check:
- Constants values via reflection, ensure `Tolerance` is used
- `Object.Density()`, `Validate()` errors with substring checks
- `BuoyantForce` and `WeightForce` formulas within 1e-6, including invalid cases
- `CheckBuoyancyByDensity` for float/sink/neutral including tolerance boundaries: `±5e-10`, `±0.9*Tol`, `±1.1*Tol`, `±1e-5`, `±25` etc.
- Integration via `CheckBuoyancy` with struct validation and delegation
- No hardcoding per object name; must compute via formulas; AST checks for redefinition
- `go vet` and reference tests from T-Bench

## What NOT to Do
- Do NOT hardcode return values per object name or density lookup table
- Do NOT skip tolerance check with `==`; must use `Tolerance` and actually have gradient on every step (Avocado must have fail)
- Do NOT hardcode `1e-9` value in logic without referencing `Tolerance` constant
- Do NOT hide `/app/buoyancy.go` behind another module
- Do NOT modify test files, `go.mod`, or define extra packages
