# Step 2: Partial Submersion and Stratified Fluid

## Overview
Step 2 of 3, `inherit_prior_session=true`. Step1 `/app/buoyancy.go` preserved. Adds frustum bucket and stratified fluid `rho(z)=S+G*z` with `BM(d)=∫rho(z)A(z)dz`. Step3 adds compressible dynamics.

## File Location
- `/app/buoyancy.go` must stay, `/app/partial.go` new, package `buoyancy`
- Go 1.23+, stdlib only: `math`, `fmt`, `errors`, `sync`
- Must compile `GO111MODULE=off`, `go vet` and `go test -race` pass. Do not redefine Step1 symbols.

## Types
```go
type SubmersionResult struct { Index int; State string; Fraction, Depth, Density float64 }
type FrustumObject struct { Mass, BaseRadius, TopRadius, Height float64 }
type StratifiedFluid struct { SurfaceDensity, Gradient float64 }
```

## Validation Rules

- `Object`: Mass>0, Volume>0, Height>0 finite.
- `Fluid`: Density>0 finite.
- `FrustumObject.Validate()`: Mass>0, Height>0, BaseRadius>=0, TopRadius>=0, not both radii 0.
- `StratifiedFluid.Validate()`: SurfaceDensity>0, Gradient>=0.
- `StratifiedFluid.DensityAtDepth(z)`: validates fluid, z>=0 finite; **Does NOT validate Object**.

## Functions
```go
func (f FrustumObject) Volume() (float64, error)
func (f FrustumObject) Density() (float64, error)
func (s StratifiedFluid) DensityAtDepth(z float64) (float64, error)
func BuoyantMass(obj Object, fluid StratifiedFluid, d float64) (float64, error)
func BuoyantMassConical(obj Object, fluid StratifiedFluid, d float64) (float64, error)
func (f FrustumObject) BuoyantMass(fluid StratifiedFluid, d float64) (float64, error)
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

- `FrustumObject.Volume()`: `π*H/3*(R1²+R1*R2+R2²)` via `math.Pi`.
- Uniform: `Mass = rho_fluid * V_sub`. Prismatic `A=Vol/H`, `V_sub=A*d`, `Fraction=density/fluidDensity`, `Depth=Fraction*H` for float else H. Conical apex-down radius∝z → `d=H*cbrt(Fraction)`. Frustum `r(z)=R1+(R2-R1)z/H`, `A(z)=π*r(z)²`, submerged volume frustum of height d with radii R1,r(d), depth via bisection [0,H] 80 iters.
- Reductions: `R1==R2` linear within 1e-6, `R1==0` cone within 1e-6.
- Stratified: `rho(z)=S+G*z`. `BM(d)=∫_0^d rho(z)A(z)dz`. Derived: prismatic `A(Sd+0.5Gd²)`, conical `πR²/H²(Sd³/3+Gd⁴/4)`, frustum `π[ S R1² d + (S2R1ΔR/H+GR1²)d²/2 + (SΔR²/H²+G2R1ΔR/H)d³/3 + GΔR²/H² d⁴/4 ]`.
- `BuoyantMass` methods return `BM(d)` directly, must match reference within **1e-9 absolute** (super hard, exposes 0.5,1/3,1/4,R1*R2 coefficients) and must error on overflow post-op.
- Stratified state: `rho_avg=BM(H)/Vol`, state via `CheckBuoyancyByDensity` with Tolerance. Float → solve `BM(d)=Mass` via bisection [0,H] 100 iters. Fraction=Mass/BM(H) clamped [0,1]. `G=0` → uniform within 1e-9.
- Batch: validate fluid; if invalid → nil,error; if `objects==nil` → `make(...,0),nil` non-nil empty; preserve order via `Index=i`; invalid object → State="invalid" continue; must be concurrent with `WaitGroup`+`Mutex`, race-free.

## Error Handling
All inputs >0 finite except radii and Gradient as specified, z/d>=0. After any multiplication/division that can overflow, if Inf or NaN return error. Error contains field name: mass, volume, height, radius, density, depth, gradient.

## General
- No external deps, no hardcoded tables, reuse Step1 types.
