# Step 2: Partial Submersion - Submerged Fraction, Equilibrium Depth & Batch Processing

## Overview
This is **Step 2 of 2** in the buoyancy task. It builds directly on **Step 1**.

In Step 1 you implemented `/app/buoyancy.go` package `buoyancy` with:
- `const Tolerance = 1e-9`, `const StandardGravity = 9.81`
- `type Object struct { Mass, Volume, Height float64 }`
- `type Fluid struct { Density float64 }`
- Methods `Density()`, `Validate()`, and functions `BuoyantForce`, `WeightForce`, `CheckBuoyancyByDensity`, `CheckBuoyancy`

**In this step the entire `/app` directory from Step 1 is preserved** (`inherit_prior_session = true`). You MUST inspect `/app/buoyancy.go` to confirm exact field names and reuse them. Do NOT redefine `Object`, `Fluid`, `Tolerance`, or `StandardGravity` — Go will fail to compile with duplicate definitions if you do. Add new logic in a **new file** `/app/partial.go` (same package `buoyancy`) that imports/uses the existing types.

Goal for this step: extend from simple float/sink/neutral decision to quantitative partial submersion: how much volume is submerged and how deep does a floating body sit (draft), plus batch analyzing many objects against one fluid.

## Physics - Partial Submersion

For an object floating at equilibrium (not sinking, not rising), weight equals buoyant force:

```
Weight = Mass * g = rho_obj * V_total * g
Buoyant = rho_fluid * V_submerged * g
At equilibrium: Weight = Buoyant
=> rho_obj * V_total = rho_fluid * V_submerged
=> V_submerged / V_total = rho_obj / rho_fluid = Submerged Fraction
```

Where:
- `rho_obj` = `Mass / Volume` (object density)
- `rho_fluid` = fluid density
- `V_total` = object total volume
- `V_submerged` = volume below fluid surface

For a prismatic/cylindrical body with uniform cross-section floating upright, depth of submergence (draft) is linear with volume fraction:

```
EquilibriumDepth (Draft) = Fraction * Height
```

Interpretation by state (reuse Step 1's `CheckBuoyancy` logic with `Tolerance`):

- **"float"** (`rho_obj < rho_fluid - Tolerance`): `0 < Fraction < 1`, `Depth = Fraction * Height` where `0 < Depth < Height`. Object partially submerged.
- **"neutral"** (`|rho_obj - rho_fluid| <= Tolerance`): `Fraction = 1.0`, `Depth = Height`. Just submerged, equilibrium at any depth (we report Height as nominal draft).
- **"sink"** (`rho_obj > rho_fluid + Tolerance`): Object wants to displace more than its volume. Physically it sinks to bottom, but we report `Fraction = 1.0` (fully submerged) and `Depth = Height` as the submerged extent (no floating equilibrium). Tests check state string to distinguish sink vs neutral, not depth alone.

**Edge:** If object density > fluid density, raw ratio `rho_obj/rho_fluid > 1`. You MUST clamp to `1.0` for reported fraction. Do NOT return >1.

## File Location

- **Reuse**: `/app/buoyancy.go` MUST stay, do not delete or rename package. You may read it, but do not redefine its types/constants.
- **New file**: `/app/partial.go`, `package buoyancy`, stdlib only.
- Both files compile together as `package buoyancy`. Tests import `buoyancy` package.
- Do NOT create `Object` or `Fluid` again in `partial.go`. Use the ones from `buoyancy.go`.

## Types to Define in `/app/partial.go`

Define exactly this result type (field names exact):

```go
// SubmersionResult captures per-object analysis for batch.
type SubmersionResult struct {
    Index    int     // position in input slice for batch
    State    string  // "float", "sink", "neutral"
    Fraction float64 // V_submerged / V_total in [0,1], clamped
    Depth    float64 // equilibrium depth / draft in meters: Fraction * Height
    Density  float64 // object density Mass/Volume for convenience
}
```

You may also define helper types if needed, but this struct name and fields must exist with exact JSON-equivalent case.

## Functions to Implement (Exact Signatures)

All exported in package `buoyancy`, in `/app/partial.go`:

```go
// SubmergedFraction returns V_submerged / V_total for an object in fluid.
// For float: rho_obj / rho_fluid (in (0,1))
// For neutral or sink: 1.0 (clamped)
// Error if inputs invalid (reuse Validate() logic from Step 1)
func SubmergedFraction(obj Object, fluid Fluid) (float64, error)

// EquilibriumDepth returns draft = Fraction * Height
// For float: Fraction*Height (<Height), neutral: Height, sink: Height (fully submerged)
// Error if inputs invalid
func EquilibriumDepth(obj Object, fluid Fluid) (float64, error)

// AnalyzeObject is convenience combining State, Fraction, Depth in one call
func AnalyzeObject(obj Object, fluid Fluid) (SubmersionResult, error)

// BatchAnalyze analyzes many objects in same fluid, preserving input order
// Returns slice length == len(objects). If fluid invalid, returns error and nil slice.
// If individual object invalid, its result should have State="invalid" (or leave empty) and Fraction=0, Depth=0 and error returned per object? Spec below:
func BatchAnalyze(objects []Object, fluid Fluid) ([]SubmersionResult, error)
```

### Detailed Behavior

**SubmergedFraction**:
1. Validate `obj` via `obj.Validate()` and `fluid` via `fluid.Validate()` ( reuse from Step 1). If invalid, return 0, error.
2. Compute `objDensity` via `obj.Density()`; propagate error.
3. Reuse `CheckBuoyancyByDensity` or same tolerance logic to get state. You MUST use `Tolerance` constant from `buoyancy.go`, not a hardcoded new tolerance.
4. If state == "float": `fraction = objDensity / fluid.Density`. Clamp: if fraction <0 => 0, if >1 =>1 (shouldn't happen for float but clamp defensively). Ensure fraction in `(0,1)` exclusive within floating error; tests allow epsilon 1e-9 around boundaries.
5. If state == "neutral" or "sink": `fraction = 1.0`.
6. Return fraction.

**EquilibriumDepth**:
1. Same validation as above.
2. Call `SubmergedFraction` (or recalc) to get fraction.
3. Depth = fraction * obj.Height.
4. Return depth. Unit meters. For sink/neutral, depth == Height (since fraction 1).

**AnalyzeObject**:
1. Validate inputs.
2. Compute density via `obj.Density()`.
3. State via `CheckBuoyancyByDensity(density, fluid.Density)` — must reuse Step 1 function, not duplicate logic with different tolerance.
4. Fraction via `SubmergedFraction`.
5. Depth = fraction * obj.Height (or via `EquilibriumDepth`).
6. Return `SubmersionResult{ State, Fraction, Depth, Density: density, Index:0 }` . For non-batch, Index may be 0 (tests ignore Index for single analyze). If any validation fails, return zero-value result and error.

**BatchAnalyze**:
- First validate fluid (`fluid.Validate()`). If invalid, return nil, error.
- If `objects` is nil or empty, return empty slice `[]SubmersionResult{}` and nil error (not error).
- For each object `i`, produce `SubmersionResult` with `Index: i`.
  - If object `i` invalid (`Validate()` fails), set `State: "invalid"`, `Fraction: 0`, `Depth: 0`, `Density: 0` (or attempted density if possible) and continue. Do NOT fail entire batch for one bad object. Tests expect batch to skip invalid with State="invalid" and still return other valid results.
  - Else compute as in `AnalyzeObject` and set `Index=i`, `Density`.
- Return slice in same order as input.
- Never return `>1` fraction; always clamped to [0,1].
- Must be deterministic; no goroutines needed (sequential OK).

### Example Usage

```go
// after Step 1 files still present at /app/buoyancy.go
// your new file /app/partial.go implements below:

obj1 := buoyancy.Object{Mass: 600, Volume: 1.0, Height: 2.0} // rho=600
obj2 := buoyancy.Object{Mass: 1200, Volume: 1.0, Height: 2.0} // rho=1200 sink
obj3 := buoyancy.Object{Mass: 1000, Volume: 1.0, Height: 2.0} // rho=1000 neutral in water
water := buoyancy.Fluid{Density: 1000}

f1, _ := buoyancy.SubmergedFraction(obj1, water) // 0.6
d1, _ := buoyancy.EquilibriumDepth(obj1, water)   // 1.2 = 0.6*2.0
// state float, partially submerged 60%, draft 1.2m of 2m total

res, _ := buoyancy.AnalyzeObject(obj1, water)
// res.State=="float", res.Fraction==0.6, res.Depth==1.2, res.Density==600

batch := []buoyancy.Object{obj1, obj2, obj3}
results, _ := buoyancy.BatchAnalyze(batch, water)
// results[0]: float, 0.6, 1.2
// results[1]: sink, 1.0, 2.0
// results[2]: neutral, 1.0, 2.0

// invalid handling
bad := buoyancy.Object{Mass: -5, Volume: 1.0, Height: 1.0}
resBad, err := buoyancy.AnalyzeObject(bad, water) // err != nil
results2, _ := buoyancy.BatchAnalyze([]buoyancy.Object{obj1, bad, obj3}, water)
// results2[1].State=="invalid", Fraction 0
```

## Requirements

1. **Context-following**: File `/app/buoyancy.go` from Step 1 exists. Read it with `cat /app/buoyancy.go` if needed (don't assume field names). Reuse `Object`, `Fluid`, `Tolerance`, `StandardGravity`, `CheckBuoyancyByDensity`, `Validate()`, `Density()`. Do NOT redefine them in `partial.go`.
2. **File location**: New file `/app/partial.go`, package `buoyancy`. Both files must pass `go vet ./...`.
3. **Struct** `SubmersionResult` must exist with exact fields `Index int`, `State string`, `Fraction float64`, `Depth float64`, `Density float64`.
4. **Functions** with exact signatures listed must exist and be exported. Tests will call them directly.
5. **Physics**: Fraction = `rho_obj / rho_fluid` for float, clamped to [0,1], 1.0 for neutral/sink. Depth = Fraction * Height.
6. **Tolerance**: Must use existing `Tolerance` constant for neutral detection; do not define new tolerance variable or hardcode 1e-6. Import/reuse.
7. **Error handling**: Return non-nil error for non-positive mass/volume/height/density or g inconsistencies. For `BatchAnalyze`, fluid invalid = whole batch error, individual object invalid = State "invalid" with zeros, not whole-batch error.
8. **Deterministic pure functions**, stdlib only, no network, no file I/O.
9. **Batch order**: Output slice preserves input order, indices match.
10. **No hardcoding**: Must compute via formulas, not lookup table of densities.
11. **Go module**: Keep same module (if `go.mod` created in Step 1). Ensure `go test ./...` works from /app.

## Grading (Hidden)

Tests not in `/app` will verify:
- `SubmergedFraction` for many combos: wood 600/1000 => 0.6, 500/1000 =>0.5, 200/1025 seawater => ~0.195, neutral exactly 1000/1000 =>1.0, sink 1200/1000 =>1.0 clamped.
- `EquilibriumDepth` = fraction * height within 1e-6 absolute or 1e-4 relative tolerance.
- `AnalyzeObject` returns correct State matching Step 1, Fraction, Depth, Density.
- `BatchAnalyze` for mixed float/sink/neutral + invalid entry handling, order preservation, index field correct, fluid invalid error, empty input.
- Reuse check: AST or compile test ensures `partial.go` does NOT contain `type Object struct` nor `type Fluid struct` nor `const Tolerance` redefinition. If duplicates exist, tests fail or `go vet` duplicate error.
- Tolerance reuse: neutral boundary cases where densities differ by 5e-10 vs 1e-5 — same cases as Step 1 must behave consistently via `Tolerance`.
- No external deps, `go vet` passes, both files in package buoyancy compile together.

## What NOT to Do

- Do NOT duplicate `Object`/`Fluid` types or `Tolerance` constant; will cause compile failure `redeclared`.
- Do NOT assume height is 1.0; use `obj.Height` field provided.
- Do NOT return fraction >1.0 for sink; clamp to 1.0.
- Do NOT ignore invalid objects in batch by dropping them; keep slice length same and mark as "invalid".
- Do NOT modify `/app/buoyancy.go` to break Step 1 tests — you may read it, but keep its Step 1 functions passing. (Cascade grading: Step 2 verifier will also run Step 1 tests implicitly to ensure you didn't regress).
- Do NOT change package name from `buoyancy` or file locations.

## Notes for Multi-Turn

- This step explicitly tests **context-following**: you must remember struct conventions from prior session (Mass, Volume, Height) and constant name `Tolerance`.
- If you forgot field names, inspect `/app/buoyancy.go` first: `cat /app/buoyancy.go`
- Keep solution extensible; final verifier runs `go test ./...` from `/app`.

Good luck!

