# Step 2: Partial Submersion and Stratified Fluid

## Overview
Step 2 of 3, `inherit_prior_session=true`. Your Step1 `/app/buoyancy.go` is preserved. This step adds frustum geometry and stratified fluid with density `rho(z)=S+G*z` and buoyant mass integral `BM(d)=∫rho(z)A(z)dz`. Step3 will add compressible dynamics.

## File Location
- `/app/buoyancy.go` must stay
- New file: `/app/partial.go`, package `buoyancy`
- Go 1.23+, stdlib only: `math`, `fmt`, `errors`, `sync`
- Must compile `GO111MODULE=off go test`, `go vet` pass. Do not redefine Step1 symbols.

## Types
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
    Gradient       float64
}
```

## Functions

Uniform fluid (fluid density constant):
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

Stratified fluid (density varies with depth):
```go
func (f FrustumObject) Validate() error
func (f FrustumObject) Volume() (float64, error)
func (f FrustumObject) Density() (float64, error)
func (s StratifiedFluid) Validate() error
func (s StratifiedFluid) DensityAtDepth(z float64) (float64, error)
func BuoyantMass(obj Object, fluid StratifiedFluid, d float64) (float64, error)
func BuoyantMassConical(obj Object, fluid StratifiedFluid, d float64) (float64, error)
func (f FrustumObject) BuoyantMass(fluid StratifiedFluid, d float64) (float64, error)
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

## Behavior
- `FrustumObject.Validate()`: Mass>0, Height>0, BaseRadius>=0, TopRadius>=0, not both radii 0. `Volume()`: `π*H/3*(R1²+R1*R2+R2²)` using `math.Pi`. `StratifiedFluid.Validate()`: SurfaceDensity>0, Gradient>=0. `DensityAtDepth(z)`: `S+G*z`, z>=0.
- Uniform: At equilibrium `Mass = rho_fluid * V_submerged`. Prismatic: `A=Volume/Height`, `V_sub=A*d`, `Fraction=density/fluidDensity`, `Depth=Fraction*H` for float else H. Conical apex-down: radius varies linearly, submerged volume is smaller similar cone, depth non-linear `d=H*cbrt(Fraction)` for float. Frustum: `r(z)=R1+(R2-R1)*z/H`, `A(z)=π*r(z)²`, submerged volume is frustum of height d with radii R1 and r(d) — use bisection [0,H] 80 iterations for depth.
- Reductions: `R1==R2` → linear within 1e-6, `R1==0` → conical within 1e-6.
- Stratified: `rho(z)=S+G*z`. `BM(d)=∫_0^d rho(z)A(z)dz`. Derive A(z): prismatic constant `A=Vol/H`, conical via similar triangles radius∝z → `A(z)∝z²`, frustum `r(z)=R1+(R2-R1)z/H` → `A(z)=π*r(z)²`. Integration yields: prismatic `A*(S*d+0.5*G*d²)`, conical `π*R²/H²*(S*d³/3+G*d⁴/4)` where R²=3*Vol/(π*H), frustum quartic mixing R1, deltaR, S, G. No closed form given; derive.
- `BuoyantMass` functions return `BM(d)` directly, must match reference polynomial within 1e-6 (exposes 0.5, 1/3, 1/4, R1*R2 coefficients).
- Stratified state: `rho_avg=BM(H)/Volume_total`, state via `CheckBuoyancyByDensity(density, rho_avg)` using Tolerance. For float, solve `BM(d)=Mass` via bisection [0,H] 100 iterations. Fraction=Mass/BM(H) clamped [0,1]. Depth = solution for float else H.
- Reductions: `G=0` → uniform within 1e-6.
- Batch: validate Fluid/StratifiedFluid; if invalid return `nil, error`. If `objects==nil` return non-nil empty via `make([]SubmersionResult,0), nil`. Preserve order via `Index=i`. Invalid object → `State="invalid"` continue. Valid → compute Fraction, Depth, Density. Must be concurrent using `sync.WaitGroup` and `sync.Mutex`, preserve order via Index, race-free (`go test -race` must pass).

## Error Handling
All inputs >0 and finite except BaseRadius/TopRadius/Gradient as specified, z>=0 for DensityAtDepth. Invalid returns 0 and non-nil error containing field name: mass, volume, height, radius, density, depth, gradient. Batch fluid invalid → nil,error.

## General
- No external deps, no hardcoded tables. Reuse Step1 types.
