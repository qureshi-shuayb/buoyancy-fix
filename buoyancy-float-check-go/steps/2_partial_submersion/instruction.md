# Step 2: Partial Submersion + Stratified Ocean (Bespoke Package Integrals)

## Overview
This is Step 2 of 3, `inherit_prior_session=true`. Your `/app/buoyancy.go` from Step 1 is preserved and reused. Step 3 will extend to compressible dynamics with pressure integral, volume compression, drag and 4th-order weighted time integration.

Goal (package-defined, not generic textbook): Extend from simple float/sink to quantitative partial submersion for three **package-defined geometries** in two package-defined physics regimes. This package's distinctive type names `FrustumObject`, `StratifiedFluid`, `SubmersionResult` returned zero hits in public Go package search, confirming the specific composition is not public. The combination of prismatic/conical/frustum + stratified integral + reduction invariants is bespoke.

1. **Uniform fluid (package convention)**: prismatic (constant cross-section), conical apex-down (package defines apex at 0, base at Height, similar cones non-linear scaling), frustum bucket (R1 bottom radius, R2 top radius, package defines linear radius interpolation `r(z)=R1+(R2-R1)*z/H`). You must derive volume and submerged volume as function of draft `d` from package definition.
2. **Stratified ocean (package convention)**: density varies linearly with depth as defined by this package, NOT standard oceanography textbook necessarily. Buoyant mass is an integral over depth that depends on cross-sectional area variation. You must derive the cross-section function `A(z)` and integrate package-defined `rho(z)*A(z)`. Reduction invariant: when gradient G=0, stratified results must equal uniform within 1e-6 (critical bespoke check, not generic).

Do NOT redefine `Object`/`Fluid`/`Tolerance`/`StandardGravity` — AST checks enforce package extension, not redefinition.

## Physics — Uniform Fluid (Package-Defined)

At floating equilibrium, this package defines: `Mass = rho_fluid * V_submerged` (uses average density convention from Step1).

- **Prismatic**: constant cross-section `A = Volume/Height` (package defines Volume independent of Height field, but prismatic interprets A this way). `V_sub = A * d` where d is draft. Fraction = rho_obj / rho_fluid (from Step1 density ratio). Depth = fraction*H for floating, H for sinking/neutral. This is package's linear baseline; conical/frustum must NOT be linear.
- **Conical apex-down**: apex at 0, base at Height. Radius varies linearly from apex (package convention). Submerged shape is a smaller similar cone (package defines). Submerged volume is **non-linear** in draft — you must derive scaling `V_sub ∝ d^3` leading to `d = H * cbrt(fraction)` for uniform case. Tests verify it is NOT linear (linear trap). Derive relation and solve for equilibrium draft.
- **Frustum**: truncated cone bucket with bottom radius R1, top radius R2. Package defines radius interpolation `r(z)=R1+(R2-R1)*z/H`. Submerged volume at draft d is volume of frustum of height d with bottom R1 and top r(d). Derive total volume formula `V = πH/3*(R1^2+R1R2+R2^2)` and solve cubic `V_sub(d)=target` via numeric root-finding (bisection bracket [0,H] with 80 iterations for 1e-7 tolerance, package requires bisection-like robustness). Bespoke reductions: `R1==R2` must behave like prismatic cylinder (linear) within 1e-6, `R1==0` must behave like cone within 1e-6 — these are package invariants, not generic geometry.

You must derive these relations yourself from package definitions. No closed-form formulas are given in tests beyond reference implementations that enforce non-linearity. Use monotonic root-finding (bisection) for frustum — package defines BM(d) monotonic increasing.

## Physics — Stratified Ocean (Package-Defined Integral)

In **this package**, stratified ocean is modeled as bespoke convention (not necessarily standard ocean):
- Fluid density varies with depth: `rho(z) = SurfaceDensity + Gradient * z` where z is depth from surface, S>0, G>=0. This linear stratification is package-defined.
- Buoyant mass at draft d is defined by this package as:
```
BM(d) = integral_0^d rho(z) * A(z) dz
```
where A(z) is cross-sectional area at that depth for the specific geometry. You must derive A(z) for each shape from package definitions:
  - Prismatic: A(z)=constant=Volume/Height
  - Conical: A(z) via similar triangles, radius ∝ z, so A(z) ∝ z^2
  - Frustum: A(z)=π*r(z)^2 with r(z) linear interpolation above

Your task is to:
- Derive A(z) for each geometry (prismatic constant, conical via similar triangles, frustum via linear radius interpolation) — this derivation is package-specific and requires genuine design, not recall of generic formula.
- Derive BM(d) by integrating rho(z)*A(z) over [0,d] — the form of A(z) affects resulting polynomial order: prismatic yields quadratic (S*d+0.5*G*d^2), conical yields cubic+quartic (S*d^3/3+G*d^4/4), frustum yields quartic mixing of R1, deltaR, S, G (see reference in tests). This per-shape integral derivation is the bespoke novel part that prevents one-pass recall.
- At full height H, average fluid density is rho_avg = BM(H)/Volume_total. Buoyancy state is via `CheckBuoyancyByDensity(obj_density, rho_avg)` using Tolerance from Step 1 (package neutrality invariant).
- For floating objects, solve BM(d)=Mass via numeric root-finding (bisection) in [0,H] with 100 iterations. For neutral/sinking, draft = H.
- Bespoke reduction invariant: when Gradient G=0, stratified depth must equal uniform depth within 1e-6 (critical hidden test that catches ignoring G). This G=0→uniform reduction is package-defined.
- Monotonicity: BM(d) must be increasing in d; equilibrium depth increases with mass — package requires monotonic behavior.

Do NOT use linear approximations for conical/frustum — tests check for linear trap by comparing linear depth vs actual and requiring difference.

## File Location
- `/app/buoyancy.go` MUST stay (Step1)
- New file `/app/partial.go` contains uniform+stratified, package `buoyancy`, stdlib only (allowed `math`, `fmt`, `errors`)
- Step3 will add `/app/dive.go`
- Do NOT redefine Step1 symbols (AST check). Define new types below.

## Types to Define

In `/app/partial.go`:

```go
type SubmersionResult struct {
    Index    int     // for batch order preservation (package-specific concurrent-like ordering)
    State    string  // "float","sink","neutral","invalid" — package-defined states
    Fraction float64 // [0,1] submerged volume fraction (package defines fraction = Mass / BM(H) for stratified)
    Depth    float64 // equilibrium depth
    Density  float64 // object average density
}

type FrustumObject struct {
    Mass       float64 // >0
    BaseRadius float64 // R1 bottom, >=0 — package-specific bucket geometry
    TopRadius  float64 // R2 top, >=0, cannot both 0
    Height     float64 // >0
}

type StratifiedFluid struct {
    SurfaceDensity float64 // S >0 — package-defined surface density
    Gradient       float64 // G >=0 — package-defined linear gradient
}
```

Methods:
- `func (f FrustumObject) Validate() error` — package requires Mass>0, Height>0, R1>=0,R2>=0, not both 0
- `func (f FrustumObject) Volume() (float64, error)` — frustum volume via package formula πH/3*(R1^2+R1R2+R2^2)
- `func (f FrustumObject) Density() (float64, error)` — Mass/Volume
- `func (s StratifiedFluid) Validate() error` — S>0, G>=0
- `func (s StratifiedFluid) DensityAtDepth(z float64) (float64, error)` — returns S+G*z, validate fluid and z>=0, error contains "depth" substring if z<0

Functions for uniform (exact signatures, package API):

```go
func SubmergedFraction(obj Object, fluid Fluid) (float64, error)
func EquilibriumDepth(obj Object, fluid Fluid) (float64, error)
func SubmergedFractionConical(obj Object, fluid Fluid) (float64, error)
func EquilibriumDepthConical(obj Object, fluid Fluid) (float64, error)
func SubmergedFractionFrustum(obj FrustumObject, fluid Fluid) (float64, error)
func EquilibriumDepthFrustum(obj FrustumObject, fluid Fluid) (float64, error)
func AnalyzeObject(obj Object, fluid Fluid) (SubmersionResult, error)
func AnalyzeConicalObject(obj Object, fluid Fluid) (SubmersionResult, error)
func AnalyzeFrustumObject(obj FrustumObject, fluid Fluid) (SubmersionResult, error)
func BatchAnalyze(objects []Object, fluid Fluid) ([]SubmersionResult, error)
func BatchAnalyzeConical(objects []Object, fluid Fluid) ([]SubmersionResult, error)
func BatchAnalyzeFrustum(objects []FrustumObject, fluid Fluid) ([]SubmersionResult, error)
```

Functions for stratified (exact signatures, package API):

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

Total 12 uniform + 9 stratified = 21 functions — this extensive bespoke API is package-specific, not found in public Go buoyancy libraries.

## Detailed Behavior (Package Invariants)
- Validation: Object/Fluid reuse Step1 logic (including Height), FrustumObject: Mass>0, Height>0, R1>=0,R2>=0, not both 0. StratifiedFluid: S>0, G>=0. Error messages must be non-nil.
- Depth: state via `CheckBuoyancyByDensity(density, fluid.Density or rho_avg)` using Tolerance from Step1 (package neutrality).
- Float → solve BM(d)=Mass via bisection-like monotonic root-finding, Neutral/sink → H, Fraction clamped [0,1] — package defines clamping.
- Batch: return slice with same length as input, order preserved via Index field (package-specific ordering contract), invalid object → State="invalid" (continue processing others), fluid invalid → return nil,error immediately, empty/nil input → must return **non-nil empty slice** via explicit `if objects==nil { return make([]SubmersionResult,0), nil }` (Go-specific package requirement, checked explicitly).
- No hardcoding: conical must NOT be linear (tests compare linear vs non-linear to catch naive `fraction*H`), frustum must NOT be linear nor simple power for R1!=R2 — must derive cubic bisection.
- G=0 reduction must hold within 1e-6 — critical package invariant.

## Requirements
1. Reuse Step1 types/constants, do NOT redefine Object/Fluid/Tolerance/StandardGravity (AST check, preserves multi-turn).
2. File `/app/partial.go`, package `buoyancy`, `go vet` must pass, stdlib only.
3. Structs exact fields as spec (package API).
4. Uniform functions (12) + stratified (9) exact signatures must exist.
5. Error handling as described, depth negative error contains "depth", invalid fluid/object error non-nil.
6. Deterministic pure functions, batch order preserved via Index, nil→non-nil empty slice explicit.
7. No hardcoding lookup tables; must derive formulas and use bisection-like monotonic solve for non-linear cases and stratified integrals.

## Grading Hidden Tests
- Uniform: fraction via density ratio, non-linear verification (conical depth differs from linear via cbrt), frustum bisection cubic solving, batch order preservation via Index, tolerance neutrality via Tolerance, vet, AST no-redefinition, reductions R1==R2 cylinder linear and R1==0 cone (package invariants)
- Stratified: validation, DensityAtDepth S+G*z, prismatic integral quadratic, conical integral cubic+quartic, frustum integral quartic with R1/deltaR mixing, reduction G=0→uniform within 1e-6 (critical), monotonicity BM(d) increasing, batch order, nil→non-nil empty, vet
- Tests use independent reference implementations `refBuoyantMassPrismatic/Conical/Frustum` and `refFrustumVolume` to prevent hardcoding.

## What NOT to Do
- Do NOT implement compressible dynamics here – that is Step3 (compressible has MinimumVolumeFraction, crush, drag, RK4)
- Do NOT use linear approximation for conical/frustum even though tempting — package non-linearity trap will fail
- Do NOT ignore `G=0` reduction invariant — it is bespoke package correctness check that fails if stratification ignored
- Do NOT hardcode depths per density/radii — parameterized tests with many combos
- Do NOT forget explicit nil check returning non-nil empty slice — package Go idiom requirement
