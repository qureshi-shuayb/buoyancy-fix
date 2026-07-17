# Step 2: Partial Submersion - Prismatic & Conical Equilibrium, Depth & Batch Processing

## Overview
This is **Step 2 of 2**. It builds directly on **Step 1**.

In Step 1 you implemented `/app/buoyancy.go` package `buoyancy` with:
- `const Tolerance`, `const StandardGravity`
- `type Object struct { Mass, Volume, Height float64 }`
- `type Fluid struct { Density float64 }`
- Methods `Density()`, `Validate()`, and functions `BuoyantForce`, `WeightForce`, `CheckBuoyancyByDensity`, `CheckBuoyancy`

**The entire `/app` from Step 1 is preserved** (`inherit_prior_session = true`). Inspect `/app/buoyancy.go` to confirm field names and reuse them. Do NOT redefine `Object`, `Fluid`, `Tolerance`, or `StandardGravity` — Go will fail with duplicate definitions. Add new logic in new file `/app/partial.go` (same package `buoyancy`).

Goal: extend from simple float/sink/neutral decision to quantitative partial submersion for two geometries:
1. **Prismatic/cylindrical** uniform cross-section (linear volume vs depth)
2. **Conical** right circular cone apex-down (non-linear cubic volume vs depth)

Plus batch processing that preserves order and handles invalid entries.

## Physics - Derive, Don't Copy

For an object floating at equilibrium, weight equals buoyant force:

```
Weight = Mass * g
Buoyant = rho_fluid * V_submerged * g
At equilibrium: Weight = Buoyant
```

You must derive `V_submerged` from this equality. `rho_obj = Mass / Volume`.

**Prismatic body:** Uniform cross-section floating upright. Submerged volume scales linearly with draft `d`:
- Derive relationship between `d`, `Height`, `V_submerged`, `V_total` yourself from geometry of constant area.

**Conical body (apex-down):** Right circular cone floating point-down. Geometry:
- Total cone volume `V_total = (1/3) * baseArea * Height`
- At draft `d` (submerged depth), submerged shape is a smaller similar cone with height `d` and radius `r = R * d / Height` by similar triangles, where `R` is base radius
- So `V_submerged(d) = (1/3) * π * r² * d`. Express in terms of `V_total`, `d`, `Height` to get non-linear relation `V_sub/V_total = (d/Height)³`
- Derive equilibrium draft `d` as function of density ratio. Requires cubic root (`math.Cbrt`).

Interpretation by state (reuse Step 1 tolerance logic):
- **float**: object partially submerged, `0 < V_sub/V_total < 1`, draft `0 < d < Height`
- **neutral**: just submerged, `V_sub/V_total = 1.0`, draft `= Height` (reported as nominal)
- **sink**: wants to displace more than its volume, physically sinks to bottom; report `fraction=1.0`, `depth=Height` as submerged extent, distinguish by State string

**Clamping:** Never return fraction >1 or depth >Height or <0. Clamp to [0,1] and [0,Height].

## File Location

- **Reuse**: `/app/buoyancy.go` MUST stay
- **New file**: `/app/partial.go`, `package buoyancy`, stdlib only
- Both files compile together. Tests import `buoyancy` package.
- Do NOT redefine `Object`/`Fluid`/`Tolerance`/`StandardGravity` in `partial.go`.

## Types to Define in `/app/partial.go`

Define exactly:

```go
type SubmersionResult struct {
    Index    int
    State    string
    Fraction float64 // V_submerged / V_total clamped [0,1]
    Depth    float64 // prismatic draft: derived from fraction, linear; for conical variant see below
    Density  float64 // object density
}
```

## Functions to Implement (Exact Signatures)

All exported in package `buoyancy`, in `/app/partial.go`:

```go
// Prismatic/cylindrical

// SubmergedFraction returns V_submerged / V_total derived from equilibrium.
// For float: in (0,1), for neutral/sink: 1.0 clamped. Error if invalid inputs.
func SubmergedFraction(obj Object, fluid Fluid) (float64, error)

// EquilibriumDepth returns draft for prismatic body (linear scaling).
// For float: <Height, neutral/sink: Height.
func EquilibriumDepth(obj Object, fluid Fluid) (float64, error)

// AnalyzeObject combines State, Fraction, Depth (prismatic)
func AnalyzeObject(obj Object, fluid Fluid) (SubmersionResult, error)

// BatchAnalyze preserves input order, handles invalid objects as State="invalid"
func BatchAnalyze(objects []Object, fluid Fluid) ([]SubmersionResult, error)

// Conical apex-down (non-linear cubic root)

// SubmergedFractionConical returns fraction (same density ratio result as prismatic, but kept for symmetry)
func SubmergedFractionConical(obj Object, fluid Fluid) (float64, error)

// EquilibriumDepthConical returns draft for conical body: Height * cbrt(fraction) for float, Height for neutral/sink.
// Must use math.Cbrt; not linear.
func EquilibriumDepthConical(obj Object, fluid Fluid) (float64, error)

// AnalyzeConicalObject combines State, Fraction, Depth using conical depth
func AnalyzeConicalObject(obj Object, fluid Fluid) (SubmersionResult, error)

// BatchAnalyzeConical same semantics as BatchAnalyze but using conical depth
func BatchAnalyzeConical(objects []Object, fluid Fluid) ([]SubmersionResult, error)
```

### Detailed Behavior (You Must Derive Formulas)

**Common validation** for all functions:
- Validate `obj` via `obj.Validate()` and `fluid` via `fluid.Validate()`. If invalid, return 0/error.
- Compute density via `obj.Density()`.
- Get state via `CheckBuoyancyByDensity(density, fluid.Density)` — reuse Step 1 constant `Tolerance`, do not hardcode new tolerance.

**Prismatic:**
- Derive fraction from `Weight=Buoyant`: `rho_obj*V_total = rho_fluid*V_sub` → relation you must solve.
- For float: fraction in (0,1). For neutral/sink: 1.0 clamped. Clamp defensively to [0,1].
- EquilibriumDepth: derive from geometry constant cross-section: volume fraction equals depth fraction. So depth = function(fraction, Height) linear.
- Return depth in meters.

**Conical apex-down:**
- Fraction from equilibrium is same density ratio as prismatic (shape independent for volume fraction): `rho_obj/rho_fluid` clamped to 1 for neutral/sink.
- Depth derivation: Total volume `V_total = (1/3)*baseArea*Height`. At draft `d`, `V_sub = (1/3)*π*r²*d` with `r = R*d/Height`. So `V_sub = V_total*(d/Height)³`. Set `V_sub/V_total = densityRatio` → `d = Height * cbrt(densityRatio)`.
- For float: `d = Height * cbrt(fraction)` where `fraction = rho_obj/rho_fluid`, in (0,Height). For neutral/sink: `d=Height`.
- Must use `math.Cbrt`, not `Pow(x,1/3)` (Pow fails for edge). Tests check non-linear vs linear difference.
- Clamp depth to [0,Height].

**AnalyzeObject / AnalyzeConicalObject:**
- Validate inputs
- Density, State via `CheckBuoyancyByDensity`
- Fraction via respective SubmergedFraction func
- Depth via respective EquilibriumDepth func
- Return `SubmersionResult{State, Fraction, Depth, Density, Index:0}`. Zero-value + error on validation fail.

**BatchAnalyze / BatchAnalyzeConical:**
- First validate fluid. If invalid, return nil, error.
- If `objects` nil or empty, return empty slice non-nil `[]SubmersionResult{}` and nil error.
- For each `i`, `Index=i`
  - If object invalid: `State="invalid"`, `Fraction=0`, `Depth=0`, `Density=0`, continue (do not fail whole batch)
  - Else compute via Analyze* and set Index=i
- Preserve order, never return fraction>1 or depth>Height.

## Requirements

1. **Context-following:** Reuse `Object`, `Fluid`, `Tolerance`, `CheckBuoyancyByDensity`, `Validate()`, `Density()` from `/app/buoyancy.go`. Do NOT redefine them.
2. **File location:** `/app/partial.go`, package `buoyancy`, `go vet ./...` must pass.
3. **Struct** `SubmersionResult` exact fields.
4. **Functions** exact signatures listed (8 functions total) must exist and be exported.
5. **Error handling:** non-positive inputs → non-nil error. Batch fluid invalid → whole batch error; individual invalid → State "invalid".
6. **Deterministic pure functions**, stdlib only.
7. **Clamping:** fraction [0,1], depth [0,Height].
8. **No hardcoding** lookup tables; must compute via formulas you derive.
9. **Conical requires cbrt** — tests will fail if you use linear `fraction*Height` for conical.

## Grading (Hidden)

Tests will verify:
- Constants still exist from Step1
- `SubmergedFraction` correct for many combos within tolerance
- `EquilibriumDepth` prismatic = linear within 1e-6 abs or 1e-4 rel
- `EquilibriumDepthConical` = `Height * cbrt(fraction)` for float, e.g., fraction 0.6 → depth ≈ Height*0.843432... not 0.6*Height. Strongly distinguishes from naive linear implementation.
- `SubmergedFraction` vs `SubmergedFractionConical` both equal density ratio (fraction same) but depths differ — tests check this.
- `AnalyzeObject` and `AnalyzeConicalObject` produce correct State (matching Step1 tolerance), Fraction, Depth, Density
- Batch order, index, invalid handling, empty/nil, fluid invalid error
- Reuse check: AST ensures `partial.go` does NOT contain `type Object struct`, `type Fluid struct`, `const Tolerance`, `const StandardGravity`
- Tolerance reuse: near-boundary cases 5e-10 vs 1e-5 behave consistently
- `go vet` passes

## What NOT to Do

- Do NOT redefine Object/Fluid/Tolerance
- Do NOT return fraction>1 or depth>Height
- Do NOT drop invalid batch entries; keep length same and mark "invalid"
- Do NOT modify `/app/buoyancy.go` to break Step1
- Do NOT use `fraction*Height` for conical depth (will fail conical tests)
- Do NOT hardcode results per density
