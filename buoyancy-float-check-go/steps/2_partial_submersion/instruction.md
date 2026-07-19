# Step 2: Partial Submersion + Stratified Ocean (Uniform → Stratified)

## Overview
This is **Step 2 of 3**, `inherit_prior_session=true`. Your `/app/buoyancy.go` from Step 1 is preserved and reused. Step 3 will extend to compressible dynamics with pressure integral, volume compression, drag and RK4.

Goal: Extend from simple float/sink to quantitative partial submersion for **three geometries** in **two physics regimes**:
1. **Uniform fluid** baseline: prismatic (constant cross-section), conical apex-down (similar cones), frustum truncated cone bucket (R1 bottom, R2 top) in uniform density ocean. Must derive volume and submerged volume vs draft yourself, no formulas given. Cubic relation → numeric bisection.
2. **Stratified ocean**: density varies linearly with depth `rho(z)=SurfaceDensity+Gradient*z`. Buoyant mass is **integral** `BM(d)=∫_0^d rho(z)A(z)dz` where `A(z)` is cross-sectional area at depth z. Must derive `A(z)` for each geometry. Quadratic for prismatic, quartic for conical/frustum. Requires bisection. Reduction `G=0 → uniform` must hold within 1e-6.

This task is split from previous ultra-hard 2-step to make gradient achievable: Step2 alone should be solvable by Opus (5/5), while Avocado may have 3/4.

Do NOT redefine `Object`/`Fluid`/`Tolerance`/`StandardGravity`. Step 3 will reuse `SubmersionResult`, `FrustumObject`, `StratifiedFluid` you define here.

## Physics – Uniform (derive, no formula given)
- At equilibrium floating: `Mass = rho_fluid * V_submerged`
- Total volume `V_total`: prismatic `A*H`, conical `π R² H /3`, frustum `π H/3 (R1²+R1R2+R2²)` – derive yourself, don't hardcode.
- Prismatic: `A` constant, `V_sub = A*d`, `fraction = rho_obj/rho_fluid`, `depth = fraction*H` for float, `H` for sink/neutral.
- Conical apex-down: radius varies linearly from apex, submerged shape is smaller similar cone. Submerged volume non-linear: `V_sub = V_total * (d/H)³` for cone pointing down? Actually similar cones: `fraction = (d/H)³`. Derive non-linear relation (must NOT be linear). Tests fail if linear. Float depth `d = H * cbrt(fraction)` for cones.
- Frustum: bottom R1 top R2, radius varies linearly `r(z)=R1+(R2-R1)z/H`, submerged frustum volume `V_sub(d)= π d/3 (R1²+R1*r(d)+r(d)²)`. Derive total volume and solve cubic `V_sub(d)=target` via bisection. `R1==R2` → cylinder (linear), `R1==0` → cone (cbrt) reductions must hold.

Methods to derive: bisection 80 iterations.

## Physics – Stratified (derive A(z) and integral, no formula given)

- `rho(z)=S+G*z`, `S>0, G>=0`, `z` depth from surface down
- `BM(d)=∫_0^d rho(z)A(z)dz`, `A(z)` cross-section at depth z:
  - Prismatic: constant `A=Vol/H`, `BM = A*(S*d+0.5*G*d²)`
  - Conical: derive `R` from `V` and `H`, `r(z)` linear, `A=π r²`, `BM = π*R²/(H²)*(S*d³/3+G*d⁴/4)`
  - Frustum: `r(z)=R1+(R2-R1)z/H`, `A=π r²` quadratic, `BM` quartic: `π*( S*R1² d + (S*2R1ΔR/H+G R1²)d²/2 + (SΔR²/H²+G 2R1ΔR/H)d³/3 + GΔR²/H² d⁴/4 )`
- Total volume `∫_0^H A(z)dz` must match uniform volume
- `BM(H)/Vol = rho_avg`, state via `CheckBuoyancyByDensity(rho_obj, rho_avg)` using Tolerance from Step1
- Float → `BM(d)=Mass` solve via bisection 80-100 iter, Neutral/sink → H
- Reduction `G=0` must equal uniform depth within 1e-6 (critical test)
- Monotonicity: `BM(d)` increasing, equilibrium depth increases with mass

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
- `func (f FrustumObject) Volume() (float64, error)` — frustum volume formula
- `func (f FrustumObject) Density() (float64, error)`
- `func (s StratifiedFluid) Validate() error`
- `func (s StratifiedFluid) DensityAtDepth(z float64) (float64, error)` — `S+G*z`, validate fluid and z>=0

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
- Float → `BM(d)=Mass` via bisection, Neutral/sink → H, Fraction clamped [0,1]
- Batch: return slice with same length, Order preserved via Index, invalid object → State="invalid", fluid invalid → nil,error, empty/nil → non-nil empty slice
- No hardcoding: conical must NOT be linear (tests compare linear vs cbrt), frustum must NOT be linear nor simple cbrt for R1!=R2.

## Requirements
1. Reuse Step1 types/constants, do NOT redefine Object/Fluid/Tolerance/StandardGravity (AST check).
2. File `/app/partial.go`, package `buoyancy`, `go vet` must pass, stdlib only.
3. Structs exact fields as spec.
4. Uniform functions (12) + stratified (9) exact signatures must exist.
5. Error handling as described, depth negative error, invalid fluid/object error.
6. Deterministic pure functions, batch order preserved.
7. No hardcoding lookup tables; must derive formulas via bisection.

## Grading Hidden Tests
- Uniform: fraction, linear trap, cbrt vs linear, frustum cubic bisection, batch, tolerance, vet, AST, reductions R1==R2 cylinder and R1==0 cone
- Stratified: validation, DensityAtDepth, prismatic quadratic, conical quartic, frustum quartic, reduction G=0→uniform, monotonicity, batch, vet

## What NOT to Do
- Do NOT implement compressible dynamics here – that is Step3
- Do NOT use linear for conical/frustum
- Do NOT ignore `G=0` reduction property
- Do NOT hardcode depths per density/radius
