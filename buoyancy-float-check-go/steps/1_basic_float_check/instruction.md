# Step 1: Basic Buoyancy Float / Sink / Neutral Check in Go (Package-Defined Convention)

## Overview
This is Step 1 of 3 in a multi-turn task building a bespoke Go package `buoyancy` that later extends to non-linear frustum geometries and compressible dynamics. This package defines its own conventions — it is NOT a generic tutorial for standard fluid mechanics.

Goal (package-defined): Determine floating state from mass/volume and fluid density with **package-defined** tolerance-aware neutral boundary. Step 2 reuses your types for prismatic, conical, frustum with stratified ocean integral buoyancy requiring derivation of cross-section A(z) and numeric root-finding of buoyant mass integral BM(d). Step 3 extends to compressible dynamics with pressure derived from density integral, volume compression clamped to MinimumVolumeFraction, drag opposing motion, and time integration with 4th-order weighted method.

Keep your Step 1 types clean and reusable — AST checks prevent redefinition in later steps. The distinctive type names `Object`, `Fluid`, `Tolerance`, `StandardGravity` are part of this package's bespoke API and are checked for exact spelling/values; they returned zero hits in public Go package search, confirming package novelty.

## Package Contract (Bespoke Definitions)
In **this package** (not textbook recall):
- Object average density is defined as `Mass/Volume` (package convention).
- Buoyant force for fully displaced volume `V` is defined by this package as `fluid.Density * V * g` using the passed `g` parameter (package convention).
- Weight force is `mass * g` using passed `g`.
- Neutral buoyancy is defined by this package as `|rho_obj - rho_fluid| <= Tolerance` using the exported constant `Tolerance=1e-9`.
- `Height` field is required for later A(z) derivations in Step 2/3 for prismatic/conical/frustum volume.
- All numeric inputs must be >0 and finite (not NaN/Inf).
- Object validation is central — consider reusing Validate() for all object checks to keep logic consistent and DRY.
- Error messages must contain relevant keyword case-insensitive — generic "invalid input" fails. This enforces package error contract.
  - Density() invalid → must contain "mass" or "volume" depending which field
  - Validate() invalid → "mass", "volume", "height" depending which field
  - Fluid Validate() invalid → "density"
  - BuoyantForce invalid → "density", "volume", "gravity" depending which param
  - WeightForce invalid → "mass", "gravity"
  - CheckBuoyancyByDensity invalid → "density"

Your implementation will be tested with densities differing by small tolerances around the neutral boundary.

## File Location and Package
- Implement in single file: `/app/buoyancy.go`
- Package: `buoyancy`
- Go 1.23+, standard library only. Allowed imports: `math`, `fmt`, `errors`.
- File must compile with `GO111MODULE=off go test`, `go vet` must pass.
- This file will be preserved and checked by AST in Step 2/3 — do NOT redefine `Object`, `Fluid`, `Tolerance`, `StandardGravity`.

## Constants to Define
You MUST define these exported constants with exact values:
```go
const Tolerance = 1e-9
const StandardGravity = 9.81
```
Use the constants where appropriate in your logic.

## Types to Define
```go
type Object struct {
    Mass   float64 // kg, >0 and finite
    Volume float64 // m^3, >0 and finite
    Height float64 // m, total vertical height when upright, >0 and finite — for later A(z) derivation
}

type Fluid struct {
    Density float64 // kg/m^3, >0 and finite
}
```
Methods with exact signatures:
- `func (o Object) Density() (float64, error)` — returns `Mass/Volume`. Error if Mass or Volume <=0 or not finite. Error message must contain "volume" or "mass" (case-insensitive).
- `func (o Object) Validate() error` — error if any of Mass, Volume, Height <=0 or not finite. Error message must contain relevant field name: "mass" for Mass invalid, "volume" for Volume invalid, "height" for Height invalid.
- `func (f Fluid) Validate() error` — error if Density <=0 or not finite. Error must contain "density".

Use `errors.New` or `fmt.Errorf`; exact wording not checked beyond substring requirements, but must be non-nil and not panic.

## Functions to Implement (Exact Signatures)
```go
func BuoyantForce(fluid Fluid, volume float64, g float64) (float64, error)
func WeightForce(mass float64, g float64) (float64, error)
func CheckBuoyancyByDensity(objDensity, fluidDensity float64) (string, error)
func CheckBuoyancy(obj Object, fluid Fluid) (string, error)
```

### Detailed Behavior

**BuoyantForce**:
- Validate `fluid.Density>0 finite`, `volume>0 finite`, `g>0 finite`. Must treat NaN/Inf as invalid. If invalid, return 0 and non-nil error containing relevant term: invalid fluid → must contain "density", invalid volume → "volume", invalid g → "gravity" (case-insensitive).
- Return `fluid.Density * volume * g` using passed `g` parameter.

**WeightForce**:
- Validate `mass>0 finite`, `g>0 finite`. Must reject non-finite values. Else error containing "mass" for bad mass, "gravity" for bad g.
- Return `mass * g` using passed g.

**CheckBuoyancyByDensity**:
- Validate both densities >0 finite, else error containing "density".
- Must use `Tolerance` constant to decide neutral vs float/sink. Return exactly "float", "sink", or "neutral" lower-case.
- Float when `objDensity < fluidDensity - Tol`, sink when `> +Tol`, neutral when within. Must work both directions.
- Must not use `==` for float equality — package requires tolerance band.
- Must return exactly lower-case strings, not "Float" or "FLOAT".

**CheckBuoyancy**:
- Validate Object and Fluid via their Validate methods.
- Compute average density via Density() and delegate to `CheckBuoyancyByDensity`.

## Requirements

1. File `/app/buoyancy.go`, package `buoyancy`.
2. Define constants `Tolerance` and `StandardGravity` exactly.
3. Define `Object` and `Fluid` structs exactly — these are foundational types for later steps.
4. All 4 functions + 3 methods with exact signatures, exported.
5. Tolerance-aware neutral boundary: use `Tolerance` constant, handle small differences correctly.
6. Height validation: Validate() must check Height bounds, Density() returns Mass/Volume.
7. Error substring: error messages must contain relevant keyword case-insensitive — generic "invalid input" fails.
8. Large/small number handling: must not overflow/underflow, compute via division. Handle tiny valid values correctly.
9. g param: must use passed g param in BuoyantForce and WeightForce, not hardcoded constant.
10. Must handle non-finite values as invalid: all validation must reject NaN and Inf as invalid. Error must contain relevant keyword.
11. No external dependencies, `go vet` must pass, no hardcoded tables.
12. Step 2/3 compatibility: Do NOT rename fields/package.

## Grading Hidden Tests

- Constants values and usage
- Density() and Validate() with substring checks: Validate Mass=0 must contain "mass", Volume=0 "volume", Height=0 "height"; Fluid Validate 0 "density"; Density Mass=0 "mass", Volume=0 "volume"
- Non-finite handling: various NaN/Inf cases must error with relevant substring
- BuoyantForce/WeightForce formula within 1e-6, invalid cases with substring checks, g param usage with various g values
- CheckBuoyancyByDensity float/sink/neutral including boundaries around Tolerance, exact lower-case return, error substring "density"
- Integration via CheckBuoyancy with struct validation
- AST checks for redefinition, no hardcoding
- `go vet`

## What NOT to Do

- Do NOT hardcode return values or use lookup table
- Do NOT use `==` for neutral check; must use `Tolerance` constant via `math.Abs(diff) <= Tolerance`
- Do NOT hardcode `1e-9` without referencing `Tolerance`
- Do NOT forget Height in Validate()
- Do NOT return generic error without substring containing relevant field name (mass/volume/height/density/gravity)
- Do NOT hardcode gravity constant in force calculations — must use passed `g` param
- Do NOT rely solely on `<=0` to validate — must handle non-finite values as invalid
