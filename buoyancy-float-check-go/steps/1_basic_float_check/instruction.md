# Step 1: Basic Buoyancy Float / Sink / Neutral Check in Go (Package-Defined Convention)

## Overview
This is Step 1 of 3 in a multi-turn task building a bespoke Go package `buoyancy` that later extends to non-linear frustum geometries and compressible dynamics. This package defines its own conventions — it is NOT a generic tutorial for standard fluid mechanics.

Goal (package-defined): Determine floating state from mass/volume and fluid density with **package-defined** tolerance-aware neutral boundary. Step 2 reuses your types for prismatic, conical, frustum with stratified ocean integral buoyancy requiring derivation of cross-section A(z) and numeric root-finding of buoyant mass integral BM(d). Step 3 extends to compressible dynamics with pressure derived from density integral, volume compression clamped to MinimumVolumeFraction, drag opposing motion, and time integration with 4th-order weighted method.

Keep your Step 1 types clean and reusable — AST checks prevent redefinition in later steps. The distinctive type names `Object`, `Fluid`, `Tolerance`, `StandardGravity` are part of this package's bespoke API and are checked for exact spelling/values; they returned zero hits in public Go package search, confirming package novelty.

## Package Contract (Bespoke Definitions)
In **this package** (not textbook recall):
- Object average density is defined as `Mass/Volume` (package convention)
- Buoyant force for fully displaced volume `V` is defined by this package as `fluid.Density * V * g` (package convention, uses passed `g` not hardcoded)
- Weight force is `mass * g`
- **Neutral buoyancy is defined by this package as `|rho_obj - rho_fluid| <= Tolerance`** using the exported constant `Tolerance=1e-9`, not equality. Simple `==` fails hidden tests with diff ~1e-10 vs 1e-5. This tolerance-aware boundary is a bespoke package invariant to create gradient (Avocado 4/5 not 5/5) and must use the `Tolerance` constant via reference, not hardcoded `1e-9`. AST and reflection checks enforce this.
- `Height` field validation is a package-specific requirement for later steps (Step 2/3 use Height for prismatic/conical/frustum volume derivations) — many naïve solutions forget Height, but hidden tests include `Height=0` and `Height=-1`.

Your implementation will be tested with densities differing by `5e-10` (neutral), `0.9*Tol` (neutral), `1.1*Tol` (float/sink), `1e-12` (neutral) vs `1e-6` (not neutral).

## File Location and Package
- Implement in single file: `/app/buoyancy.go`
- Package: `buoyancy`
- Go 1.23+, standard library only. Allowed imports: `math`, `fmt`, `errors`.
- File must compile with `GO111MODULE=off go test`, `go vet` must pass.
- This file will be preserved and checked by AST in Step 2/3 — do NOT redefine `Object`, `Fluid`, `Tolerance`, `StandardGravity`.

## Constants to Define
You MUST define and use these exported constants with exact values:
```go
const Tolerance = 1e-9
const StandardGravity = 9.81
```
`Tolerance` must be referenced in `CheckBuoyancyByDensity` logic — hardcoding `1e-9` without referencing the constant fails hidden AST and variation tests. `StandardGravity` is provided for reference; use the passed `g` param in force calculations, not hardcoded 9.81. This constant-reference requirement is a package-specific anti-hardcoding check, not standard physics.

## Types to Define
```go
type Object struct {
    Mass   float64 // kg, >0
    Volume float64 // m^3, >0
    Height float64 // m, total vertical height when upright, >0 — package-specific for later A(z) derivation
}

type Fluid struct {
    Density float64 // kg/m^3, >0
}
```
Methods with exact signatures:
- `func (o Object) Density() (float64, error)` — returns `Mass/Volume`. Error if `Volume <=0` or `Mass <=0`. Error message must contain "volume" or "mass" (case-insensitive) — checked via substring.
- `func (o Object) Validate() error` — error if any of Mass, Volume, Height <=0. Many implementations forget Height — hidden tests include `Height=0` and `Height=-1`. This Height check is package-specific for multi-geometry extension.
- `func (f Fluid) Validate() error` — error if Density <=0.

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
- Validate `fluid.Density>0`, `volume>0`, `g>0`. If invalid, return 0 and non-nil error containing relevant term ("density"/"volume"/"gravity" case-insensitive).
- Return `fluid.Density * volume * g` using passed `g` — hidden test uses `g=3.7` (Mars) to catch hardcoded 9.81.

**WeightForce**:
- Validate `mass>0`, `g>0`. Else error containing "mass" or "gravity".
- Return `mass * g`.

**CheckBuoyancyByDensity**:
- Validate both densities >0, else error.
- Must use `Tolerance` constant to decide neutral vs float/sink. Return exactly "float", "sink", or "neutral" lower-case.
- Float when `objDensity < fluidDensity - Tol`, sink when `> +Tol`, neutral when within. Must work both directions.
- Must not use `==` for float equality — package requires tolerance band.

**CheckBuoyancy**:
- Validate Object and Fluid via their Validate methods and Density().
- Compute average density and delegate to `CheckBuoyancyByDensity`.

## Requirements (Traps for Gradient and Bespoke Invariants)
1. File `/app/buoyancy.go`, package `buoyancy`.
2. Define constants `Tolerance` and `StandardGravity` exactly and reference `Tolerance` in logic (AST check for constant usage, not hardcoded).
3. Define `Object` and `Fluid` structs exactly — these are package-specific foundational types for frustum bucket and stratified ocean extensions.
4. All 4 functions + 3 methods with exact signatures, exported.
5. **Tolerance trap (bespoke package invariant):** hidden tests include `diff=5e-10` neutral, `diff=0.9*Tol` neutral, `1.1*Tol` float/sink, `1e-12` neutral vs `1e-5` not neutral, `±0.5*Tol`, `±25`. Simple `==` or missing `Tolerance` reference fails and is intended to create Avocado 4/5 gradient.
6. **Height validation trap (package-specific):** `Validate()` must check Height <=0 — many naïve solutions only check Mass/Volume, but Step2 requires Height for A(z) derivation.
7. **Error substring trap:** error messages must contain relevant keyword case-insensitive — generic "invalid input" fails. This enforces package error contract.
8. **Large number handling:** tests include `Mass=5e8, Volume=1e6` (density 500 float) and `Mass=1e12, Volume=1e6` (density 1e6 sink) — must not overflow, compute via division.
9. No external dependencies, `go vet` must pass, no hardcoded tables.
10. Step 2/3 compatibility: Do NOT rename fields/package. AST prevents redefinition.

## Grading Hidden Tests
- Constants values and usage via reflection/AST (must reference Tolerance constant, not hardcoded 1e-9)
- `Density()`, `Validate()` with substring and Height checks, large numbers
- `BuoyantForce`/`WeightForce` formula within 1e-6, invalid cases with substring, `g` param usage (Mars 3.7 test)
- `CheckBuoyancyByDensity` float/sink/neutral including boundaries `±5e-10`, `±0.9*Tol`, `±1.1*Tol`, `±1e-12`, `±1e-6`, `±25`
- Integration via `CheckBuoyancy` with struct validation
- AST checks for redefinition, no hardcoding
- `go vet`

## What NOT to Do
- Do NOT hardcode return values or use lookup table
- Do NOT use `==` for neutral check; must use `Tolerance` constant reference (package invariant)
- Do NOT hardcode `1e-9` without referencing `Tolerance`
- Do NOT forget Height in Validate() — package-specific required for frustum
- Do NOT return generic error without substring
- Do NOT hardcode 9.81 in force calculations — must use passed `g`
