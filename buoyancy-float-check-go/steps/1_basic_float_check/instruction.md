# Step 1: Basic Buoyancy + Cylindrical/Spherical Geometry + Ballast + Batch (Package-Defined, HARDENED)

## Overview
This is Step 1 of 3 in a multi-turn task building a bespoke Go package `buoyancy` that later extends to non-linear frustum geometries and compressible dynamics. This package defines its own conventions — it is NOT a generic tutorial for standard fluid mechanics.

Goal (package-defined): Step 1 now includes **four intertwined physics concerns** with bespoke package invariants:

1. Prismatic float/sink/neutral with tolerance-aware neutral boundary (existing)
2. **Cylindrical and spherical geometries** with Pi-factor traps requiring derivation of `V=πr²h` and `V=4/3πr³` (package convention, not textbook recall of generic volume)
3. **Apparent weight and required ballast** with package-defined tolerance-zeroing: when density difference is within Tolerance, apparent weight is exactly 0 and required ballast is exactly 0 (not small epsilon). This introduces a second usage of Tolerance constant beyond CheckBuoyancyByDensity.
4. **Batch ordering with Go idiom** `nil→non-nil empty slice` and order preservation via Index, plus overflow detection after multiplication/division (package requires post-op Inf/NaN check, not just pre-check).

Step 2 reuses your types for prismatic, conical, frustum with stratified ocean integral buoyancy requiring derivation of cross-section A(z) and numeric root-finding of buoyant mass integral BM(d). Step 3 extends to compressible dynamics with pressure derived from density integral, volume compression clamped to MinimumVolumeFraction, drag opposing motion, and time integration with 4th-order weighted method.

Keep your Step 1 types clean and reusable — AST checks prevent redefinition in later steps. The distinctive type names `Object`, `Fluid`, `Tolerance`, `StandardGravity`, `CylinderObject`, `SphereObject`, `BuoyancyReport` are part of this package's bespoke API and are checked for exact spelling/values. `CylinderObject`/`SphereObject` introduce Pi and 4/3 factor traps that are package-specific.

## Package Contract (Bespoke Definitions)
In **this package** (not textbook recall):

- Object average density is defined as `Mass/Volume` (package convention).
- Cylinder geometric volume is defined as `V = π * R² * H` using `math.Pi`, where R is Radius, H is Height. This is package convention. Missing Pi gives factor ~3.14 error. Diameter vs Radius confusion gives factor 4x error (using diameter as radius → volume 4x larger). Package requires `math.Pi` reference.
- Sphere geometric volume is defined as `V = 4/3 * π * R³` using `math.Pi`. Missing 4/3 gives ~0.75x error (3.14 vs 4.188). Missing Pi gives ~0.239x error. Both trapped.
- Buoyant force for fully displaced volume `V` is defined by this package as `fluid.Density * V * g` using the passed `g` parameter (package convention). Must use passed g, not `StandardGravity`.
- Weight force is `mass * g` using passed `g`.
- Neutral buoyancy is defined by this package as `|rho_obj - rho_fluid| <= Tolerance` using exported constant `Tolerance=1e-9`. This tolerance must be referenced via constant, not hardcoded 1e-9, in multiple functions: `CheckBuoyancyByDensity`, `ApparentWeight`, `RequiredBallastMass` (AST checks).
- Apparent weight (package-defined) is `Weight - Buoyant = (Mass - rho_fluid*Volume)*g`, BUT with bespoke tolerance-zeroing: if `|rho_obj - rho_fluid| <= Tolerance`, apparent weight is defined as exactly `0` (not small residual). This prevents floating-point epsilon leak and requires Tolerance usage in ApparentWeight.
- Required ballast for neutral (package-defined) is `ballast = rho_fluid*Volume - Mass` mass to add (positive = add, negative = remove), BUT with same tolerance-zeroing: if already neutral within Tolerance, ballast is exactly `0`. Must use Tolerance constant.
- `Height` field is required for later A(z) derivations in Step 2/3 for prismatic/conical/frustum volume.
- All numeric inputs must be >0 and finite (not NaN/Inf) AND post-operation results must be finite (overflow detection). Package requires overflow check: after computing `Mass/Volume`, `πR²H`, `4/3πr³`, `rho*V*g`, `mass*g`, `(Mass - rhoV)*g`, `rhoV - Mass`, if result is `Inf` or `NaN`, must return error with relevant substring (e.g. "volume", "mass", "gravity", "radius", "overflow"). Pre-check only misses cases like `1e200 * 1e200 = +Inf` with finite inputs.
- Object validation is central — idiomatic Go often reuses Validate() everywhere for DRY. However this package defines **inverse validation traps**: `Object.Density()` must NOT validate Height (Height irrelevant for average density), `CylinderObject.Volume()` must NOT validate Mass (geometry independent of mass), `SphereObject.Volume()` must NOT validate Mass. Consider DRY but be careful — blindly calling Validate() inside these methods fails hidden tests.
- Error messages must contain relevant keyword case-insensitive — generic "invalid input" fails. This enforces package error contract.
  - Object Density() invalid → must contain "mass" or "volume" depending which field, plus finite handling
  - Object Validate() invalid → "mass", "volume", "height" depending which field
  - Fluid Validate() invalid → "density"
  - CylinderObject Validate() invalid → "mass" for Mass, "radius" for Radius, "height" for Height
  - CylinderObject Volume() invalid → "radius" or "height" (since it must NOT check Mass, radius/height only)
  - SphereObject Validate() → "mass", "radius"
  - SphereObject Volume() → "radius" (must NOT check Mass)
  - BuoyantForce invalid → "density", "volume", "gravity" depending which param
  - WeightForce invalid → "mass", "gravity"
  - CheckBuoyancyByDensity invalid → "density"
  - ApparentWeight invalid → "density", "mass", "volume", "gravity" depending which param invalid, must chain object/fluid validation
  - RequiredBallastMass invalid → "density", "mass", "volume" etc.
  - BatchCheckBuoyancy invalid g → "gravity", fluid invalid → "density", result State="invalid" for bad object not nil,error

## File Location and Package
- Implement in single file: `/app/buoyancy.go`
- Package: `buoyancy`
- Go 1.23+, standard library only. Allowed imports: `math`, `fmt`, `errors`.
- File must compile with `GO111MODULE=off go test`, `go vet` must pass.
- This file will be preserved and checked by AST in Step 2/3 — do NOT redefine `Object`, `Fluid`, `Tolerance`, `StandardGravity` in later steps (enforced), but you define them now.
- Must handle overflow post-op: after any multiplication/division that could overflow (πR²H, 4/3πr³, rho*V*g, mass*g, Mass/Volume, (Mass - rhoV)*g, rhoV - Mass), check `math.IsInf(result,0) || math.IsNaN(result)` and return error.

## Constants to Define
You MUST define these exported constants with exact values:
```go
const Tolerance = 1e-9
const StandardGravity = 9.81
```
Use the constants where appropriate in your logic. You must reference `Tolerance` in `CheckBuoyancyByDensity`, `ApparentWeight`, `RequiredBallastMass` (AST checks for substring "Tolerance" inside those func bodies). You must NOT reference `StandardGravity` inside `BuoyantForce`, `WeightForce`, `ApparentWeight`, `RequiredBallastMass`, `BatchCheckBuoyancy` — must use passed g param (AST + behavior check with g=3.7 Mars).

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

type CylinderObject struct {
    Mass   float64 // kg, >0 finite
    Radius float64 // m, >0 finite — package uses radius, not diameter
    Height float64 // m, >0 finite
}

type SphereObject struct {
    Mass   float64 // kg, >0 finite
    Radius float64 // m, >0 finite
}

type BuoyancyReport struct {
    Index        int     // original position for order preservation
    State        string  // "float","sink","neutral","invalid" — package states
    Density      float64 // object average density (0 if invalid)
    BuoyantForce float64 // rho*V*g using passed g (0 if invalid)
    WeightForce  float64 // mass*g using passed g (0 if invalid)
}
```

Methods with exact signatures:
- `func (o Object) Density() (float64, error)` — returns `Mass/Volume`, **must NOT validate Height** (inverse trap). Error if Mass or Volume <=0 or not finite. Must check post-division overflow: if result is Inf/NaN, return error containing relevant term. Error message must contain "volume" or "mass".
- `func (o Object) Validate() error` — error if any of Mass, Volume, Height <=0 or not finite. Error must contain relevant field name.
- `func (f Fluid) Validate() error` — error if Density <=0 or not finite. Error must contain "density".
- `func (c CylinderObject) Validate() error` — error if Mass, Radius, Height <=0 or not finite. Substring: "mass" for Mass, "radius" for Radius, "height" for Height.
- `func (c CylinderObject) Volume() (float64, error)` — returns `π*R²*H` using `math.Pi`, **must NOT validate Mass** (inverse trap: geometry independent of mass). Validate Radius>0 finite, Height>0 finite, else error containing "radius" or "height". Must detect overflow after multiplication: if result IsInf, error. Pi factor required: R=1,H=1 → π, not 1. Diameter confusion: if you use diameter, R=1 gives 4π fail.
- `func (c CylinderObject) Density() (float64, error)` — returns Mass/Volume, using Volume() for geometry. Validate Mass>0 finite + call Volume() internally (which validates R,H). Must handle overflow after division.
- `func (s SphereObject) Validate() error` — Mass>0 finite, Radius>0 finite, substrings "mass","radius".
- `func (s SphereObject) Volume() (float64, error)` — returns `4/3 * π * R³` using `math.Pi`, **must NOT validate Mass**. Validate Radius>0 finite error contains "radius". Overflow check. 4/3 factor trap: R=1 → 4.18879 not 3.14159.
- `func (s SphereObject) Density() (float64, error)` — Mass / Volume, overflow check.

Use `errors.New` or `fmt.Errorf`; exact wording not checked beyond substring requirements, but must be non-nil and not panic.

## Functions to Implement (Exact Signatures)
```go
func BuoyantForce(fluid Fluid, volume float64, g float64) (float64, error)
func WeightForce(mass float64, g float64) (float64, error)
func CheckBuoyancyByDensity(objDensity, fluidDensity float64) (string, error)
func CheckBuoyancy(obj Object, fluid Fluid) (string, error)
func ApparentWeight(obj Object, fluid Fluid, g float64) (float64, error)
func RequiredBallastMass(obj Object, fluid Fluid) (float64, error)
func BatchCheckBuoyancy(objs []Object, fluid Fluid, g float64) ([]BuoyancyReport, error)
```

### Detailed Behavior

**BuoyantForce**:
- Validate `fluid.Density>0 finite` via Fluid.Validate(), `volume>0 finite`, `g>0 finite`. Must treat NaN/Inf as invalid. If invalid, return 0 and non-nil error containing relevant term: invalid fluid → must contain "density", invalid volume → "volume", invalid g → "gravity" (case-insensitive).
- Compute `fluid.Density * volume * g` using passed g. Check overflow: if result IsInf or IsNaN → error containing relevant term (e.g., "volume" or "overflow" substring still must contain keyword per param? For overflow of product, at least "volume" or "gravity" should appear, but safest return error containing "volume" or "gravity" for product overflow).
- Must NOT use `StandardGravity` constant (AST + behavior check with g=3.7).

**WeightForce**:
- Validate `mass>0 finite`, `g>0 finite`. Else error containing "mass" for bad mass, "gravity" for bad g. Overflow check after multiplication: if result Inf/NaN → error containing "mass" or "gravity".
- Return `mass * g` using passed g, not StandardGravity.

**CheckBuoyancyByDensity**:
- Validate both densities >0 finite, else error containing "density", must handle NaN/Inf.
- Must use `Tolerance` constant to decide neutral vs float/sink. Return exactly "float", "sink", or "neutral" lower-case.
- Float when `objDensity < fluidDensity - Tolerance`, sink when `> +Tolerance`, neutral when within inclusive `<= Tolerance`. Must work both directions.
- Must not use `==` for float equality — package requires tolerance band inclusive.
- Must reference `Tolerance` constant via AST (body contains "Tolerance").

**CheckBuoyancy**:
- Validate Object and Fluid via their Validate methods.
- Compute average density via Density() and delegate to `CheckBuoyancyByDensity`.

**ApparentWeight** (new, package-defined):
- Validate Object (via Validate()), Fluid, g>0 finite. If any invalid, return error with relevant substring.
- Compute object density via Object.Density() (which itself checks Mass/Volume>0 finite and overflow). Compute fluid density.
- Compute density diff = objDensity - fluidDensity. If `math.Abs(diff) <= Tolerance` → return exactly `0` (package-defined neutral apparent weight zeroing). Must use Tolerance constant (AST).
- Else compute `Buoyant = fluid.Density * obj.Volume * g`, `Weight = obj.Mass * g` using passed g (must call BuoyantForce/WeightForce or compute same formula but must use g param, not StandardGravity). Check overflow for intermediate: if Buoyant or Weight is Inf → error.
- Return `Weight - Buoyant` = `(Mass - rho*V)*g`. Overflow check final result IsInf → error containing "mass" or "gravity" etc.
- Must NOT use StandardGravity. Must use g param. Trap g=3.7 Mars: obj Mass 500, Vol 1, fluid 1000, g=3.7 → weight 1850, buoyant 3700, apparent -1850, not 9.81 based.
- Error substring: fluid invalid → "density", volume invalid → "volume", mass invalid → "mass", g invalid → "gravity".
- Must handle NaN/Inf via IsNaN/IsInf checks.

**RequiredBallastMass** (new):
- Validate Object and Fluid. Error contains relevant keyword.
- Compute object density. If `|density - fluid.Density| <= Tolerance` → return exactly `0` (package-defined ballast zeroing when already neutral within tolerance). Must use Tolerance constant (AST). This catches implementations that compute `rho*V - Mass` = `0.9*Tol*V` ≠0.
- Else compute targetMass = fluid.Density * Volume (overflow check), ballast = targetMass - Mass (overflow check). Positive means need to add mass, negative means need to remove.
- Check overflow: if targetMass or ballast is Inf/NaN → error.
- Error substring: "mass", "volume", "density" as appropriate.
- Must NOT use StandardGravity.

**BatchCheckBuoyancy** (new, Go idiom hardened):
- Validate Fluid via Validate(), g>0 finite (IsNaN/IsInf). If fluid invalid → return `nil, error` immediately (nil slice + error, not partially filled). Error must contain "density". If g invalid → return `nil, error` containing "gravity".
- If `objs == nil` → must return **non-nil empty slice** via explicit `make([]BuoyancyReport,0)` or `make(...,0)` and nil error (package Go idiom, checked via `res != nil && len==0`). Using `var s []BuoyancyReport` nil slice or returning nil, nil fails. Same for empty but non-nil slice? Must handle nil case explicitly.
- If objs is empty slice (non-nil, len 0) → return non-nil empty slice (can be same make).
- Results slice length must equal len(objs), order preserved via `Index` field = original position `i`. Even with invalid entries, do NOT skip, do NOT reorder.
- For each object: if Validate() fails → `State="invalid"`, `Density=0, BuoyantForce=0, WeightForce=0`, `Index=i`, continue to next (must NOT return nil,error).
- If valid: compute Density via Density(), Buoyant via BuoyantForce(fluid, obj.Volume, g), Weight via WeightForce(obj.Mass, g) using passed g (not StandardGravity), State via CheckBuoyancyByDensity(Density, fluid.Density) or CheckBuoyancy. Set Report fields accordingly and Index=i.
- Must use passed g, not StandardGravity (AST + behavior).
- Deterministic pure function, no sorting.
- `go vet` must pass.

**CylinderObject.Volume() inverse trap detail**:
- Must NOT check Mass. So `CylinderObject{Mass:0, Radius:1, Height:1}.Volume()` should succeed returning π, not error about mass. Many DRY implementations call Validate() inside Volume() which checks Mass and thus incorrectly fails on Mass=0. Hidden test checks this.
- Similarly `SphereObject.Volume()` must NOT check Mass: Mass=0, Radius=1 → should return 4.18879, not error.

**Object.Density() inverse trap** (kept):
- `Object{Mass:1, Volume:1, Height:0}.Density()` should succeed returning 1, not error about height. Many DRY impls call Validate() inside Density() which checks Height and fails.

## Requirements

1. File `/app/buoyancy.go`, package `buoyancy`, stdlib only (math, fmt, errors).
2. Define constants `Tolerance` and `StandardGravity` exactly, with exact values 1e-9 and 9.81.
3. Define `Object`, `Fluid`, `CylinderObject`, `SphereObject`, `BuoyancyReport` structs exactly as spec (fields, spelling).
4. All old methods (Object.Density, Object.Validate, Fluid.Validate) + new methods (Cylinder/Sphere Validate/Volume/Density) with exact signatures, exported.
5. All 7 functions with exact signatures: BuoyantForce, WeightForce, CheckBuoyancyByDensity, CheckBuoyancy, ApparentWeight, RequiredBallastMass, BatchCheckBuoyancy.
6. Tolerance-aware neutral boundary in three places: CheckBuoyancyByDensity, ApparentWeight zeroing, RequiredBallastMass zeroing must all reference `Tolerance` constant (AST).
7. g param must be used in BuoyantForce, WeightForce, ApparentWeight, BatchCheckBuoyancy (must NOT contain StandardGravity in those function bodies, AST + behavior with g=3.7).
8. Overflow handling: after any multiplication/division that could overflow, check `math.IsInf` or `math.IsNaN` and return error with relevant substring. Must handle tiny valid values (1e-12 etc) correctly, only large Inf-triggering combos error.
9. Pi factor: Cylinder Volume must be πR²H, Sphere Volume 4/3πr³ using `math.Pi`, not hardcoded 3.14 (AST checks for "math.Pi" or "Pi" presence, and behavior Pi trap).
10. 4/3 factor trap for sphere, diameter vs radius trap for cylinder (hidden tests compare expected vs diameter-based volume diff).
11. Inverse validation traps: Density() for Object must NOT check Height, Cylinder/Sphere Volume() must NOT check Mass. Tests explicitly check zero Mass/Height cases.
12. Error substring contract: all invalid cases must return error containing relevant keyword case-insensitive (mass, volume, height, radius, density, gravity, ballast? ballast errors must still contain mass/volume/density as appropriate). Generic "invalid input" fails.
13. Batch: nil→non-nil empty slice via `make`, order preservation via Index, invalid handling State="invalid" not nil,error, fluid/g invalid → nil,error immediate, g param usage, valid/invalid interleaving.
14. No external dependencies, `go vet` must pass, no hardcoded tables, handling of large numbers up to 1e12 not overflow, tiny 1e-12 not underflow.
15. Must handle non-finite values as invalid: all validation must reject NaN and Inf as invalid via `math.IsNaN`/`IsInf`, error contains relevant keyword. AST checks that IsNaN/IsInf appear at least twice overall to enforce proper handling not just <=0.
16. Step 2/3 compatibility: Do NOT rename fields/package, keep Object/Fluid.

## Grading Hidden Tests

- Constants values and usage: Tolerance exact, StandardGravity exact, Tolerance referenced in CheckBuoyancyByDensity, ApparentWeight, RequiredBallastMass via AST substring check.
- Object Density() and Validate() with substring checks, Height inverse trap, NaN/Inf handling with substring.
- CylinderObject: Volume Pi trap R=1,H=1 → π, R=0.5,H=2 → 0.5π (diameter trap would give 2π), invalid radius 0,-1,NaN,Inf contains "radius", Height invalid contains "height", Volume() with Mass=0 must succeed (inverse trap), Volume overflow detection 1e150 radius.
- SphereObject: Volume 4/3πr³ factor trap R=1 → 4.18879, R=2 → 33.5103, invalid radius, Volume() with Mass=0 must succeed, overflow.
- Cylinder/Sphere Density: Mass/Volume overflow, Mass 0 error contains "mass".
- Forces: formula within 1e-6, invalid cases substring, g param with Mars 3.7, overflow detection with 1e200*1e200*g must error not return Inf.
- CheckBuoyancyByDensity: boundaries 0.9*Tol vs 1.1*Tol, exact tolerance inclusive <=, lower-case return, error substring.
- ApparentWeight: neutral within tolerance → 0 exactly, float negative, sink positive, g=3.7 trap, NaN/Inf, overflow, tolerance zeroing, AST StandardGravity not used and Tolerance used, error substrings.
- RequiredBallastMass: neutral within 0.9*Tol → 0, not epsilon; float positive, sink negative; large numbers; tolerance usage; overflow; no StandardGravity.
- CheckBuoyancy integration.
- BatchCheckBuoyancy: nil input → non-nil empty slice, fluid invalid → nil,error, g invalid → nil,error containing "gravity", order preservation via Index with invalid interleaving, g param usage (Buoyant 1000*1*3.7=3700 etc), State invalid handling, tolerance neutral State, `go vet`.
- Overflow suite: BuoyantForce 1e200*1e200*1e10 → error, WeightForce 1e308*2 → error, Cylinder Radius 1e200 Height 1e200 → error, etc., tiny values succeed.
- AST: Tolerance constant used in 3 funcs, StandardGravity not used in 5 funcs, math.Pi used in Volume methods, IsNaN/IsInf used at least 2 times.
- Import allowlist only math, fmt, errors.
- Fuzz random for CheckBuoyancyByDensity, Forces, ApparentWeight, Ballast with deterministic seed 100 cases.
- Vet.

## What NOT to Do

- Do NOT hardcode return values or lookup table
- Do NOT use `==` for neutral check; must use `Tolerance` constant via `math.Abs(diff) <= Tolerance`
- Do NOT hardcode `1e-9` without referencing `Tolerance` in CheckBuoyancyByDensity, ApparentWeight, RequiredBallastMass
- Do NOT forget Height in Validate() but DO forget it in Density() (inverse trap) – Density() must NOT check Height
- Do NOT make Cylinder/Sphere Volume() call Validate() that checks Mass – must NOT check Mass (inverse trap)
- Do NOT return generic error without substring containing relevant field name
- Do NOT hardcode gravity constant in force calculations or ApparentWeight/Batch – must use passed g param
- Do NOT rely solely on `<=0` to validate – must handle non-finite via IsNaN/IsInf and overflow via post-op IsInf check
- Do NOT forget Pi factor: Cylinder must be πR²H, Sphere 4/3πr³ using math.Pi – using 3.14 or missing 4/3 fails Pi/4/3 traps
- Do NOT confuse radius with diameter: Volume with diameter gives 4x error for cylinder, 8x for sphere
- Do NOT return nil slice for nil input in Batch – must return `make([]BuoyancyReport,0), nil` non-nil empty
- Do NOT skip invalid objects in batch – must return State="invalid" and continue, with Index preserved
- Do NOT sort or reorder batch results – Index must equal input order
- Do NOT implement ApparentWeight as simply Weight - Buoyant without tolerance zeroing – neutral within tolerance must return exactly 0
- Do NOT implement RequiredBallastMass as rhoV - Mass without tolerance zeroing – neutral within tolerance must return exactly 0
- Do NOT ignore overflow: returning +Inf from finite inputs must be error, not Inf
