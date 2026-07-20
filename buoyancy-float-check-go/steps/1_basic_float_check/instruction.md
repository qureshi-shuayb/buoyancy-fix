# Step 1: Basic Buoyancy Float / Sink / Neutral Check in Go (Package-Defined Convention) - HARDENED FOR AVOCADO GRADIENT

## Overview
This is Step 1 of 3 in a multi-turn task building a bespoke Go package `buoyancy` that later extends to non-linear frustum geometries and compressible dynamics. This package defines its own conventions — it is NOT a generic tutorial for standard fluid mechanics.

Goal (package-defined): Determine floating state from mass/volume and fluid density with **package-defined** tolerance-aware neutral boundary. Step 2 reuses your types for prismatic, conical, frustum with stratified ocean integral buoyancy requiring derivation of cross-section A(z) and numeric root-finding of buoyant mass integral BM(d). Step 3 extends to compressible dynamics with pressure derived from density integral, volume compression clamped to MinimumVolumeFraction, drag opposing motion, and time integration with 4th-order weighted method.

Keep your Step 1 types clean and reusable — AST checks prevent redefinition in later steps. The distinctive type names `Object`, `Fluid`, `Tolerance`, `StandardGravity` are part of this package's bespoke API and are checked for exact spelling/values; they returned zero hits in public Go package search, confirming package novelty.

## Package Contract (Bespoke Definitions - Critical for Avocado 4/5 Gradient)
In **this package** (not textbook recall):
- Object average density is defined as `Mass/Volume` (package convention). **IMPORTANT: Density() must ONLY check Mass>0 and Volume>0, NOT Height.** Height is irrelevant for average density. Many Avocado implementations incorrectly call Validate() inside Density() which checks Height, causing Density() to fail when Height=0 — hidden test `Object{Mass:1, Volume:1, Height:0}.Density()` must succeed with density 1, not error. This is intentional package invariant to create Avocado gradient.
- Buoyant force for fully displaced volume `V` is defined by this package as `fluid.Density * V * g` (package convention, uses passed `g` not hardcoded 9.81, not StandardGravity). Hidden test uses `g=3.7` (Mars) to catch hardcoded. Must use passed `g`.
- Weight force is `mass * g` using passed `g`.
- **Neutral buoyancy is defined by this package as `|rho_obj - rho_fluid| <= Tolerance`** using the exported constant `Tolerance=1e-9`, not equality. Simple `==` fails hidden tests with diff ~1e-10 vs 1e-5. This tolerance-aware boundary is a bespoke package invariant to create gradient (Avocado 4/5 not 5/5) and must use the `Tolerance` constant via reference, not hardcoded `1e-9`. AST and reflection checks enforce this.
- `Height` field validation is a package-specific requirement for later steps (Step 2/3 use Height for prismatic/conical/frustum volume derivations) — many naïve solutions forget Height, but hidden tests include `Height=0` and `Height=-1` for Validate(). However Height must NOT be validated in Density().
- Error messages must contain relevant keyword case-insensitive — generic "invalid input" fails. This enforces package error contract and creates Avocado gradient.
  - Density() with Mass<=0 → must contain "mass"
  - Density() with Volume<=0 → must contain "volume"
  - Validate() with Mass<=0 → "mass", Volume<=0 → "volume", Height<=0 → "height"
  - Fluid Validate() Density<=0 → "density"
  - BuoyantForce invalid fluid → "density", invalid volume → "volume", invalid g → "gravity"
  - WeightForce invalid mass → "mass", invalid g → "gravity"
  - CheckBuoyancyByDensity invalid → "density"

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
`Tolerance` must be referenced in `CheckBuoyancyByDensity` logic — hardcoding `1e-9` without referencing the constant fails hidden AST and variation tests. `StandardGravity` is provided for reference; use the passed `g` param in force calculations, not hardcoded 9.81. This constant-reference requirement is a package-specific anti-hardcoding check. **AST check ensures Tolerance is referenced, not hardcoded, and StandardGravity is NOT used in BuoyantForce/WeightForce** (must use passed g).

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
- `func (o Object) Density() (float64, error)` — returns `Mass/Volume`. **Only checks Mass>0 and Volume>0, NOT Height.** Error if `Volume <=0` or `Mass <=0`. Error message must contain "volume" or "mass" (case-insensitive). **CRITICAL TRAP: If you call Validate() inside Density(), you will incorrectly reject Height=0 — hidden test expects Density() with Height=0 to succeed.**
- `func (o Object) Validate() error` — error if any of Mass, Volume, Height <=0. Must check all three. Error message must contain relevant field name: "mass" for Mass<=0, "volume" for Volume<=0, "height" for Height<=0. Many implementations forget Height — hidden tests include `Height=0` and `Height=-1`.
- `func (f Fluid) Validate() error` — error if Density <=0. Error must contain "density".

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
- Validate `fluid.Density>0`, `volume>0`, `g>0`. If invalid, return 0 and non-nil error containing relevant term: invalid fluid → must contain "density", invalid volume → "volume", invalid g → "gravity" (case-insensitive).
- Return `fluid.Density * volume * g` using passed `g` — hidden test uses `g=3.7` (Mars) to catch hardcoded 9.81. Must NOT use StandardGravity constant.

**WeightForce**:
- Validate `mass>0`, `g>0`. Else error containing "mass" for bad mass, "gravity" for bad g.
- Return `mass * g` using passed g.

**CheckBuoyancyByDensity**:
- Validate both densities >0, else error containing "density".
- Must use `Tolerance` constant to decide neutral vs float/sink. Return exactly "float", "sink", or "neutral" lower-case.
- Float when `objDensity < fluidDensity - Tol`, sink when `> +Tol`, neutral when within. Must work both directions. Use `math.Abs(diff) <= Tolerance`.
- Must not use `==` for float equality — package requires tolerance band.
- Must return exactly lower-case strings, not "Float" or "FLOAT".

**CheckBuoyancy**:
- Validate Object and Fluid via their Validate methods (so Height=0 should fail here, but NOT in Density() — this inverse is intentional trap).
- Compute average density via Density() and delegate to `CheckBuoyancyByDensity`.

## Requirements (Traps for Gradient and Bespoke Invariants - HARDENED)

1. File `/app/buoyancy.go`, package `buoyancy`.
2. Define constants `Tolerance` and `StandardGravity` exactly and reference `Tolerance` in logic (AST check for constant usage, not hardcoded). `StandardGravity` must NOT be used in force calculations.
3. Define `Object` and `Fluid` structs exactly — these are package-specific foundational types for frustum bucket and stratified ocean extensions.
4. All 4 functions + 3 methods with exact signatures, exported.
5. **Tolerance trap (bespoke package invariant):** hidden tests include `diff=5e-10` neutral, `diff=0.9*Tol` neutral, `1.1*Tol` float/sink, `1e-12` neutral vs `1e-5` not neutral, `±0.5*Tol`, `±25`. Simple `==` or missing `Tolerance` reference fails and is intended to create Avocado 4/5 gradient.
6. **Height validation trap (package-specific):** `Validate()` must check Height <=0 with error containing "height" — many naïve solutions only check Mass/Volume, but Step2 requires Height for A(z) derivation. **Inverse trap: Density() must NOT check Height** — `Object{Mass:1, Volume:1, Height:0}.Density()` must succeed with density 1, while `Validate()` must fail. Many Avocado impls call Validate() inside Density() and fail this.
7. **Error substring trap (hard):** error messages must contain relevant keyword case-insensitive — generic "invalid input" fails. Must contain: Density() mass/volume, Validate() mass/volume/height depending which field invalid, Fluid Validate() density, BuoyantForce density/volume/gravity, WeightForce mass/gravity, CheckBuoyancyByDensity density. This enforces package error contract and creates Avocado gradient (Avocado often returns generic errors).
8. **Large/small number handling:** tests include `Mass=5e8, Volume=1e6` (density 500 float), `Mass=1e12, Volume=1e6` (density 1e6 sink), `Mass=1e-9, Volume=1e-9` (density 1, no underflow), `Mass=1e-12, Volume=1e-6` (density 1e-6 float). Must not overflow/underflow, compute via division.
9. **g param trap:** hidden tests use `g=3.7` for Mars to catch hardcoded 9.81. Must use passed g param in BuoyantForce and WeightForce, not StandardGravity constant. Also test with `g=0.1` small and `g=1e6` large volume `1e6` to check no overflow.
10. No external dependencies, `go vet` must pass, no hardcoded tables.
11. Step 2/3 compatibility: Do NOT rename fields/package. AST prevents redefinition.

## Grading Hidden Tests

- Constants values and usage via reflection/AST (must reference Tolerance constant, not hardcoded 1e-9, and must NOT reference StandardGravity in force funcs)
- `Density()` must NOT validate Height: test with Height=0 should succeed, Height=-1 should succeed for Density() but fail for Validate()
- `Density()`, `Validate()` with substring checks: Validate Mass=0 must contain "mass", Volume=0 "volume", Height=0 "height"; Fluid Validate 0 "density"; Density Mass=0 "mass", Volume=0 "volume"
- `BuoyantForce`/`WeightForce` formula within 1e-6, invalid cases with substring checks (density/volume/gravity/mass), `g` param usage with Mars 3.7 and small 0.1 and large 1e6*0.1
- `CheckBuoyancyByDensity` float/sink/neutral including boundaries `±5e-10`, `±0.9*Tol`, `±1.1*Tol`, `±1e-12`, `±1e-6`, `±25`, exact lower-case return, error substring "density"
- Integration via `CheckBuoyancy` with struct validation: Height=0 should fail (Validate), but Density with Height=0 should succeed (inverse trap)
- AST checks for redefinition, no hardcoding, Tolerance usage, StandardGravity not used in force calcs
- `go vet`

## What NOT to Do

- Do NOT hardcode return values or use lookup table
- Do NOT use `==` for neutral check; must use `Tolerance` constant reference (package invariant) via `math.Abs(diff) <= Tolerance`
- Do NOT hardcode `1e-9` without referencing `Tolerance`
- Do NOT forget Height in Validate() — package-specific required for frustum
- Do NOT call Validate() inside Density() — Height trap: Density() with Height=0 must succeed, Validate() must fail
- Do NOT return generic error without substring containing relevant field name (mass/volume/height/density/gravity)
- Do NOT hardcode 9.81 or use StandardGravity in force calculations — must use passed `g` param, hidden Mars 3.7 test
