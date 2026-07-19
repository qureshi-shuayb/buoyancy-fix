# Step 2: Partial Submersion - Prismatic, Conical, Frustum (Uniform + Stratified Ocean)

## Overview
This is **Step 2 of 2**. It builds directly on **Step 1**. `inherit_prior_session=true` – your `/app/buoyancy.go` from Step 1 is preserved.

Goal: Extend from simple float/sink/neutral decision to quantitative partial submersion for **three geometries** in **uniform fluid** (baseline) PLUS hardest extension to **stratified ocean** where fluid density varies with depth, requiring integral buoyancy and numeric root-finding. This pushes far beyond textbook `fraction = density ratio`.

Uniform fluid part is still required (backward compat) but must be derived without formula spoilers. Stratified part is the novel hard part that raises difficulty from MEDIUM to HARD.

In Step 1 you implemented:
- `const Tolerance`, `const StandardGravity`
- `type Object struct { Mass, Volume, Height }`
- `type Fluid struct { Density }`
- `Density()`, `Validate()`, `BuoyantForce`, `WeightForce`, `CheckBuoyancyByDensity`, `CheckBuoyancy`

Do NOT redefine those symbols in `/app/partial.go` – Go will fail duplicate. Add new logic in `/app/partial.go`, same package `buoyancy`, stdlib only.

## Physics – Uniform Fluid (Baseline, you must derive, no formula given)

For uniform fluid, equilibrium floating satisfies:

```
Weight = Mass * g = Buoyant = rho_fluid * V_submerged * g
=> Mass = rho_fluid * V_submerged
```

You must derive `V_submerged` as function of draft `d` for each geometry yourself.

- **Prismatic/cylindrical uniform cross-section upright:** Submerged volume scales with draft. Derive relation between `d`, `Height`, `V_sub`, `V_total` from constant area. Do NOT assume linear without proof – derive it. No formula given here.

- **Conical apex-down:** Right circular cone floating point-down. Submerged portion is a smaller similar cone. Derive how volume depends on draft using similar triangles and cone volume. The relation is non-linear and not linear. You must derive exponent yourself. Tests will explicitly fail if you use linear `fraction*Height` for conical float case.

- **Frustum truncated cone (bucket/buoy):** Bottom radius `R1`, top radius `R2`, height `H`. This is not standard textbook. You must derive total volume and submerged volume at draft `d` yourself from first principles (difference of cones or integration). At draft `d`, radius at waterline varies between `R1` and `R2` – you must derive that variation. Submerged shape is itself a frustum. Total volume and `V_sub(d)` must be derived; no formula given. The resulting relation is cubic in `d`. Requires numeric root-finding (bisection/Newton) in general, but you must derive it. Edge: `R1==R2` → cylinder, `R1==0` → cone – your generic solver should naturally handle those without hardcoding special cases (reduction tests will check).

Clamping uniform: Fraction `[0,1]`, Depth `[0,Height]`.

## Physics – Stratified Fluid (Hardest, Novel)

This is the non-canonical extension that makes task novel. Ocean stratification: density increases with depth.

Define fluid density as linear function of depth `z` (0 at free surface, positive downward):

```
rho(z) = SurfaceDensity + Gradient * z
SurfaceDensity >0, Gradient >=0
Units: kg/m³, kg/m⁴
```

Uniform fluid is special case `Gradient=0`, `SurfaceDensity = Density`.

Buoyant mass (mass of displaced fluid) is **integral** over submerged depth, not simple `rho*V_sub`:

```
BuoyantMass(d) = ∫_{0}^{d} rho(z) * A_obj(z) dz
where A_obj(z) is cross-sectional area of object at depth z (horizontal slice)
Weight mass = Object Mass (constant)
Equilibrium when BuoyantMass(d) = Mass
```

You must derive `A(z)` for each geometry yourself:

- **Prismatic:** Cross-section constant: `A = Volume/Height`. Derive this.
- **Conical apex-down:** Radius varies linearly from apex. You have Object Mass, Volume, Height but NOT radius – you must derive radius R from volume and height, then derive `r(z)` and `A(z)=pi*r(z)²`. No formula given.
- **Frustum:** `R1` bottom, `R2` top, radius varies linearly between them – you must derive `r(z)`, `A(z)`. Then `A(z)` is quadratic in `z`. Multiply by `rho(z)` (linear) gives cubic integrand; integral is quartic in `d`.

Then:

- Total geometric volume is integral `∫_0^H A(z) dz` – you must derive and it must match your uniform volume implementation.
- Total displaced mass at full submergence `BuoyantMass(H)` divided by total volume gives **average fluid density** over object's extent: `rho_avg_fluid = BuoyantMass(H)/Volume`. This is used for state decision:
  - Compare object average density `rho_obj = Mass/Volume` vs `rho_avg_fluid` using `Tolerance` constant from Step 1 via `CheckBuoyancyByDensity(rho_obj, rho_avg_fluid)` to get float/neutral/sink.
  - Float → equilibrium depth `d < H` solving `BuoyantMass(d)=Mass`
  - Neutral/sink → depth `H` (fully submerged extent), state distinguishes

Solving for `d`:

- Prismatic stratified: integral gives `A*(S*d + 0.5*G*d²)` → quadratic equation in `d`. Solve via quadratic formula or numeric bisection.
- Conical stratified: integral `pi*R²/H² * (S*d³/3 + G*d⁴/4)` → quartic (d³ and d⁴) – requires numeric root-finding (bisection) because closed form messy.
- Frustum stratified: integral of `pi*(R1+(R2-R1)z/H)²*(S+G*z)` → quartic polynomial with coefficients depending on R1,R2,H,S,G. Requires bisection.

**You must implement numeric solver yourself (bisection for 80-100 iterations or Newton). No analytic formula is given and you must not hardcode polynomial degrees.**

**Reduction property (mandatory):** When `Gradient=0`, your stratified solver must reproduce uniform-fluid depths within tolerance (`1e-6`). Tests will check:
- Prismatic stratified G=0 depth == prismatic uniform `fraction*H`
- Conical stratified G=0 depth == conical uniform non-linear depth
- Frustum stratified G=0 depth == frustum uniform depth

This prevents cheating by implementing only uniform case and ignoring gradient – if you ignore gradient, stratified tests with G>0 will fail; if you hardcode uniform formulas for stratified with G>0, those will fail.

## File Location

- Reuse `/app/buoyancy.go` MUST stay
- New file `/app/partial.go`, package `buoyancy`, stdlib only (`math`, `errors`, `fmt` allowed)
- Do NOT redefine `Object`/`Fluid`/`Tolerance`/`StandardGravity`

## Types to Define in `/app/partial.go`

Define exactly (order matters):

```go
type SubmersionResult struct {
    Index    int
    State    string
    Fraction float64
    Depth    float64
    Density  float64
}

type FrustumObject struct {
    Mass       float64
    BaseRadius float64
    TopRadius  float64
    Height     float64
}

type StratifiedFluid struct {
    SurfaceDensity float64
    Gradient float64
}
```

Methods:

```go
func (f FrustumObject) Volume() (float64, error)
func (f FrustumObject) Density() (float64, error)
func (f FrustumObject) Validate() error

func (s StratifiedFluid) Validate() error
func (s StratifiedFluid) DensityAtDepth(z float64) (float64, error)
```

All exported, exact signatures.

## Functions to Implement – Uniform Fluid (keep for backward compat, 12 functions)

All in `/app/partial.go`, package `buoyancy`:

```go
func SubmergedFraction(obj Object, fluid Fluid) (float64, error)
func EquilibriumDepth(obj Object, fluid Fluid) (float64, error)
func AnalyzeObject(obj Object, fluid Fluid) (SubmersionResult, error)
func BatchAnalyze(objects []Object, fluid Fluid) ([]SubmersionResult, error)

func SubmergedFractionConical(obj Object, fluid Fluid) (float64, error)
func EquilibriumDepthConical(obj Object, fluid Fluid) (float64, error)
func AnalyzeConicalObject(obj Object, fluid Fluid) (SubmersionResult, error)
func BatchAnalyzeConical(objects []Object, fluid Fluid) ([]SubmersionResult, error)

func SubmergedFractionFrustum(obj FrustumObject, fluid Fluid) (float64, error)
func EquilibriumDepthFrustum(obj FrustumObject, fluid Fluid) (float64, error)
func AnalyzeFrustumObject(obj FrustumObject, fluid Fluid) (SubmersionResult, error)
func BatchAnalyzeFrustum(objects []FrustumObject, fluid Fluid) ([]SubmersionResult, error)
```

Uniform detailed behavior: as described in previous version but without formula spoiler – you must derive yourself. Fraction = rho_obj/rho_fluid clamped for float, 1 for neutral/sink. Depth: prismatic fraction*Height, conical non-linear derived from similar triangles (must NOT be linear), frustum via numeric solving cubic. Batch preserves order, invalid → State="invalid" Fraction=0 Depth=0 Density=0, nil/empty → non-nil empty slice, invalid fluid → nil+error. `go vet` must pass. AST forbids redefinition.

## Functions to Implement – Stratified Fluid (hard part, 9 functions)

```go
func EquilibriumDepthStratified(obj Object, fluid StratifiedFluid) (float64, error)
func EquilibriumDepthConicalStratified(obj Object, fluid StratifiedFluid) (float64, error)
func EquilibriumDepthFrustumStratified(obj FrustumObject, fluid StratifiedFluid) (float64, error)

func AnalyzeStratifiedObject(obj Object, fluid StratifiedFluid) (SubmersionResult, error)
func AnalyzeConicalStratifiedObject(obj Object, fluid StratifiedFluid) (SubmersionResult, error)
func AnalyzeFrustumStratifiedObject(obj FrustumObject, fluid StratifiedFluid) (SubmersionResult, error)

func BatchAnalyzeStratified(objects []Object, fluid StratifiedFluid) ([]SubmersionResult, error)
func BatchAnalyzeConicalStratified(objects []Object, fluid StratifiedFluid) ([]SubmersionResult, error)
func BatchAnalyzeFrustumStratified(objects []FrustumObject, fluid StratifiedFluid) ([]SubmersionResult, error)
```

All exported, exact signatures.

### Stratified Detailed Behavior

- Validate fluid via `Validate()`, object via `Validate()`, error if invalid → return 0/error.
- Compute object average density `rho_obj = Mass/Volume` via `Density()` (or `FrustumObject.Density()`).
- Compute total geometric volume `Vol_total` (for Object, Vol_total = Object.Volume; for Frustum, via Volume()).
- Compute buoyant mass at full depth `BM_full = ∫_0^H rho(z)*A(z) dz` – you must derive `A(z)` yourself.
  - For **prismatic**: `A = Vol/H` constant.
  - For **conical**: derive `R` from Volume and Height, then `r(z)` linear from apex, `A(z)=pi*r(z)²`
  - For **frustum**: `r(z)=R1+(R2-R1)*z/H`, `A(z)=pi*r(z)²`
  - Integral must be derived analytically or via exact polynomial integration (no numeric integration needed if you derive polynomial, but numeric integration with Simpson also acceptable if accurate to 1e-7). Do NOT use external library.
- Compute average fluid density `rho_avg = BM_full / Vol_total`
- State via `CheckBuoyancyByDensity(rho_obj, rho_avg)` – reuse Tolerance constant.
- If state != float (neutral/sink) → depth = Height.
- Else bisection to find `d` in [0,H] where `BM(d)=Mass`:
  - `BM(d)=∫_0^d rho(z)*A(z) dz`
  - Monotonic increasing because rho>0, A>0
  - Implement bisection 80-100 iterations: lo=0 hi=H, mid=(lo+hi)/2, compute BM(mid), if BM(mid) < Mass → lo=mid else hi=mid. Return (lo+hi)/2.
  - Clamp depth to [0,Height]
- For Analyze*:
  - Return `SubmersionResult{State, Fraction, Depth, Density}`
  - For stratified, define `Fraction = Mass / BM_full` clamped [0,1] (so 1 for neutral/sink), Depth as equilibrium depth, Density = rho_obj, Index 0
  - Error if invalid inputs
- For Batch*Stratified:
  - Validate fluid first, nil/empty → non-nil empty slice
  - For each object index i, if invalid → State="invalid" Fraction=0 Depth=0 Density=0, continue
  - Else compute via Analyze* and set Index=i, preserve order

**Clamping stratified:** Fraction [0,1], Depth [0,Height].

**No hardcoding:** Must compute via derived formulas, not lookup tables. Tests will check that stratified depth != uniform linear for G>0, and that stratified with G=0 matches uniform within 1e-6 (reduction). Hardcoding uniform cbrt for stratified with G>0 will fail because depth differs.

## Requirements

1. Reuse Step1 types/constants, do NOT redefine `Object`/`Fluid`/`Tolerance`/`StandardGravity` (AST check).
2. File `/app/partial.go`, package `buoyancy`, `go vet` must pass, stdlib only.
3. Structs exact fields as spec.
4. Uniform functions (12) exact signatures must exist and pass old tests (fraction = density ratio clamped, prismatic linear, conical non-linear cbrt not linear, frustum cubic via numeric).
5. StratifiedFluid struct and methods exact signatures must exist, plus 9 stratified functions exact signatures.
6. Error handling: non-positive inputs → non-nil error, Gradient<0 → error, SurfaceDensity<=0 → error, Batch fluid invalid → nil+error, individual invalid → State="invalid".
7. Deterministic pure functions.
8. No hardcoding lookup tables; must derive formulas.
9. Conical uniform must NOT be linear, frustum uniform must NOT be linear nor simple cbrt for R1!=R2.
10. Stratified must use integral buoyancy, not simple `rho*V_sub`, and must implement numeric solver – tests will fail if you return `fraction*H` or `H*cbrt(fraction)` for stratified with G>0.

## Grading Hidden Tests

Tests will verify:
- Old uniform: fraction correct, prismatic linear, conical `H*cbrt(fraction)` vs linear distinction, frustum volume `pi*H/3*(R1²+R1R2+R2²)` and depth cubic via bisection precomputed, batch order/index/invalid, tolerance 5e-10 neutral vs 1e-5 sink, `go vet`, AST no redefinition
- New stratified:
  - Validation: SurfaceDensity<=0 error, Gradient<0 error, DensityAtDepth negative z error
  - DensityAtDepth: S+G*z
  - Prismatic stratified: quadratic solving e.g., S=1000 G=0.5, A=0.5, Mass=600 → expected depth ~1.194... (precomputed) not 1.2 linear; tests check != linear
  - Conical stratified: S=1000 G=2, Volume 1 Height 2 → expected depth via quartic ~1.65 vs uniform cbrt 1.587... – must differ, tests check not equal to uniform cbrt and not equal to linear
  - Frustum stratified: R1=0.5 R2=1.5 H2 S=1025 G=0.8 Mass chosen to give depth 1.2m → expected depth computed via reference Python bisection using analytic integral – hardcoded in Go tests
  - Reduction: G=0 depth must equal uniform depth within 1e-6 for prismatic, conical, frustum
  - Monotonicity: larger Mass → larger depth (when float)
  - Analyze* and Batch* stratified order/index/invalid/empty/nil handling
  - State via avg fluid density: if Mass < BM_full - tolerance*Volume → float, near equal → neutral, greater → sink
  - `go vet` passes

## What NOT to Do

- Do NOT redefine Step1 symbols
- Do NOT return fraction>1 or depth>Height
- Do NOT drop batch entries – mark invalid
- Do NOT modify buoyancy.go to break Step1
- Do NOT use `fraction*H` for conical uniform or frustum uniform with R1!=R2
- Do NOT use simple `H*cbrt(fraction)` for frustum uniform nor for stratified with G>0
- Do NOT hardcode depths per density/radius – must compute via derived integral + numeric solver
- Do NOT give explicit volume formulas in comments that spoil derivation? Comments allowed but tests check you derived, not that you hid formula – however final task must have removed spoilers from instruction, not solution
