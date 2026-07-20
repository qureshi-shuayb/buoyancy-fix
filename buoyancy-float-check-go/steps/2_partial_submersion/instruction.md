# Step 2: Partial Submersion + Stratified Ocean

## Overview
This is Step 2 of 3, `inherit_prior_session=true`. Your `/app/buoyancy.go` from Step 1 is preserved and reused. Step 3 will extend to compressible dynamics with pressure integral, volume compression, drag and RK4 time integration.

Goal: Extend from simple float/sink to quantitative partial submersion for three geometries in two physics regimes:

1. **Uniform fluid**: prismatic (constant cross-section), conical apex-down, frustum bucket (R1 bottom radius, R2 top radius). You must derive volume and submerged volume as function of draft.
2. **Stratified ocean**: density varies linearly with depth. Buoyant mass is an integral over depth that depends on cross-sectional area variation. You must derive the cross-section function and integrate it. Reduction property: when gradient G=0, stratified results must equal uniform within 1e-6.

Do NOT redefine `Object`/`Fluid`/`Tolerance`/`StandardGravity`.

## Physics — Uniform Fluid

At floating equilibrium: `Mass = rho_fluid * V_submerged`

- **Prismatic**: constant cross-section A = Volume/Height. `V_sub = A * d` where d is draft. Fraction = rho_obj / rho_fluid. Depth = fraction*H for floating, H for sinking/neutral.
- **Conical apex-down**: apex at 0, base at Height. Radius varies linearly from apex. Submerged shape is a smaller similar cone. Submerged volume is non-linear in draft — you must derive the scaling. Tests verify it is NOT linear. Derive the relation and solve for equilibrium draft.
- **Frustum**: truncated cone bucket with bottom radius R1, top radius R2. Radius varies linearly `r(z)=R1+(R2-R1)*z/H`. Submerged volume at draft d is the volume of a frustum of height d with bottom R1 and top r(d). Derive total volume formula and solve cubic `V_sub(d)=target` via bisection. Reductions: R1==R2 should behave like prismatic cylinder (linear), R1==0 should behave like cone.

You must derive these relations yourself. No closed-form formulas are given. Use bisection with sufficient iterations for 1e-7 tolerance.

## Physics — Stratified Ocean

Density profile: `rho(z) = SurfaceDensity + Gradient * z` where z is depth from surface downward, S>0, G>=0, z>=0.

Buoyant mass at draft d is defined as:
```
BM(d) = ∫_0^d rho(z) * A(z) dz
```
where A(z) is cross-sectional area at depth z for the given geometry.

Your task is to:
- Derive A(z) for each geometry (prismatic constant, conical via similar triangles, frustum via linear radius interpolation)
- Derive BM(d) by integrating rho(z)*A(z). This will involve quadratic terms for prismatic, higher-order terms for conical and frustum due to z-dependent area.
- At full height H, average fluid density is rho_avg = BM(H)/Volume_total. Buoyancy state is via `CheckBuoyancyByDensity(obj_density, rho_avg)` using Tolerance from Step 1.
- For floating objects, solve BM(d)=Mass via bisection. For neutral/sinking, draft = H.
- Reduction: when Gradient G=0, stratified depth must equal uniform depth within 1e-6 (critical hidden test).
- Monotonicity: BM(d) must be increasing in d; equilibrium depth increases with mass.

Do NOT use linear approximations for conical/frustum — tests check for linear trap.

## File Location
- `/app/buoyancy.go` MUST stay (Step1)
- New file `/app/partial.go` contains uniform+stratified, package `buoyancy`, stdlib only
- Step3 will add `/app/dive.go`
- Do NOT redefine Step1 symbols (AST check). Define new types below.

## Types to Define

In `/app/partial.go`:

```go
type SubmersionResult struct {
    Index    int     // for batch order
    State    string  // "float","sink","neutral","invalid"
    Fraction float64 // [0,1] submerged volume fraction
    Depth    float64 // equilibrium depth
    Density  float64 // object average density
}

type FrustumObject struct {
    Mass       float64 // >0
    BaseRadius float64 // R1 bottom, >=0
    TopRadius  float64 // R2 top, >=0, cannot both 0
    Height     float64 // >0
}

type StratifiedFluid struct {
    SurfaceDensity float64 // S >0
    Gradient       float64 // G >=0
}
```

Methods:
- `func (f FrustumObject) Validate() error`
- `func (f FrustumObject) Volume() (float64, error)` — frustum volume
- `func (f FrustumObject) Density() (float64, error)`
- `func (s StratifiedFluid) Validate() error`
- `func (s StratifiedFluid) DensityAtDepth(z float64) (float64, error)` — returns S+G*z, validate fluid and z>=0

Functions for uniform (exact signatures):

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

Functions for stratified (exact signatures):

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

Total 12 uniform + 9 stratified = 21 functions.

## Detailed Behavior
- Validation: Object/Fluid reuse Step1 logic, FrustumObject: Mass>0, Height>0, R1>=0,R2>=0, not both 0. StratifiedFluid: S>0, G>=0.
- Depth: state via `CheckBuoyancyByDensity(density, fluid.Density or rho_avg)` using Tolerance from Step1.
- Float → solve BM(d)=Mass via bisection, Neutral/sink → H, Fraction clamped [0,1]
- Batch: return slice with same length as input, order preserved via Index field, invalid object → State="invalid", fluid invalid → nil,error, empty/nil input → non-nil empty slice
- No hardcoding: conical must NOT be linear (tests compare linear vs non-linear), frustum must NOT be linear nor simple power for R1!=R2.

## Requirements
1. Reuse Step1 types/constants, do NOT redefine Object/Fluid/Tolerance/StandardGravity (AST check).
2. File `/app/partial.go`, package `buoyancy`, `go vet` must pass, stdlib only.
3. Structs exact fields as spec.
4. Uniform functions (12) + stratified (9) exact signatures must exist.
5. Error handling as described, depth negative error, invalid fluid/object error.
6. Deterministic pure functions, batch order preserved.
7. No hardcoding lookup tables; must derive formulas and use bisection for non-linear solves.

## Grading Hidden Tests
- Uniform: fraction, non-linear verification (conical depth differs from linear), frustum bisection, batch order, tolerance, vet, AST, reductions R1==R2 cylinder and R1==0 cone
- Stratified: validation, DensityAtDepth, prismatic integral, conical integral, frustum integral, reduction G=0→uniform within 1e-6, monotonicity, batch order, vet

## What NOT to Do
- Do NOT implement compressible dynamics here – that is Step3
- Do NOT use linear approximation for conical/frustum even though it is tempting
- Do NOT ignore `G=0` reduction property — it is a critical correctness check
- Do NOT hardcode depths per density/radius
