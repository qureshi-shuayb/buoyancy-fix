# Step 2: Partial Submersion and Stratified Fluid

## Overview
Step 2 of 3, `inherit_prior_session=true`. Step1 `/app/buoyancy.go` preserved. Adds frustum bucket and stratified fluid `rho(z)=S+G*z` with `BM(d)=∫rho(z)A(z)dz`. Step3 adds compressible.

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

- `Object`: Mass>0, Volume>0, Height>0 finite (must reject NaN/Inf).
- `Fluid`: Density>0 finite.
- `FrustumObject`: Mass>0, Height>0, BaseRadius>=0, TopRadius>=0, not both 0, all finite.
- `StratifiedFluid`: SurfaceDensity>0 finite, Gradient>=0 finite.
- `FrustumObject.Volume()`: validates radii and Height only (geometry-only), NOT Mass. Must allow Mass=0, Mass negative, Mass=NaN still returning volume if radii/height finite. Height>0 finite, BaseRadius>=0 finite, TopRadius>=0 finite, not both zero. Must reject NaN/Inf for radii/height and overflow to Inf.
- `StratifiedFluid.DensityAtDepth(z)`: validates fluid finite, z>=0 finite.

## Functions
```go
func (f FrustumObject) Validate() error
func (f FrustumObject) Volume() (float64, error)
func (f FrustumObject) Density() (float64, error)
func (s StratifiedFluid) Validate() error
func (s StratifiedFluid) DensityAtDepth(z float64) (float64, error)
func BuoyantMass(obj Object, fluid StratifiedFluid, d float64) (float64, error)
func BuoyantMassConical(obj Object, fluid StratifiedFluid, d float64) (float64, error)
func (f FrustumObject) BuoyantMass(fluid StratifiedFluid, d float64) (float64, error)
func SubmergedVolumeAtDepthFrustum(obj FrustumObject, d float64) (float64, error)
func WaterlineAreaAtDepthFrustum(obj FrustumObject, d float64) (float64, error)
func EquilibriumDepthStratifiedWithTol(obj Object, fluid StratifiedFluid, tol float64) (float64, error)
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

- `FrustumObject.Volume()`: `π*H/3*(R1²+R1*R2+R2²)` via `math.Pi`. Geometry-only — must NOT check Mass. Overflow to Inf/NaN must error.
- `SubmergedVolumeAtDepthFrustum`: `V_sub(d)=π*d/3*(R1²+R1*rd+rd²)`, `rd=R1+(R2-R1)*d/H`, within 1e-9.
- `WaterlineAreaAtDepthFrustum`: `A(d)=π*r(d)²`, `r(d)=R1+(R2-R1)*d/H`, within 1e-9.
- Uniform: `Mass=rho*V_sub`. Prismatic `A=Vol/H`, `V_sub=A*d`, `Fraction=clamp(density/fluidDensity,0,1)`, `Depth=Fraction*H` else H. **Clarification:** For sinking objects (density ratio >1, e.g., raw ratio 1.2), `Fraction` must be clamped to `1.0` (not 1.2). The raw ratio 1.2 is not valid; grader expects `1.0`. Conical `d=H*cbrt(Fraction)` where Fraction clamped. Frustum bisection [0,H] 80 iters.
- Reductions: `R1==R2` linear 1e-9, `R1==0` cone 1e-9.
- Stratified: `rho(z)=S+G*z`. `BM(d)=∫rho(z)A(z)dz`. Prismatic `A(Sd+0.5Gd²)`, conical `πR²/H²(Sd³/3+Gd⁴/4)`, frustum `π[SR1²d+(S2R1ΔR/H+GR1²)d²/2+(SΔR²/H²+G2R1ΔR/H)d³/3+GΔR²/H² d⁴/4]`.
- `BuoyantMass` returns `BM(d)` within **1e-12 absolute** (super hard) and must be closed-form polynomial not numeric loop. Must error on overflow.
- `EquilibriumDepthStratifiedWithTol`: same as `EquilibriumDepthStratified` but uses passed `tol` for bisection termination, must use tol param.
- Stratified state: `rho_avg=BM(H)/Vol`, state via `CheckBuoyancyByDensity` with Tolerance. Float → bisection [0,H] 100 iters. Fraction=Mass/BM(H) clamped [0,1]. `G=0`→uniform 1e-9.
- Batch: validate fluid else nil,error; if `objects==nil`→`make(...,0),nil`; order via `Index=i`; invalid→State="invalid" continue; concurrent with `WaitGroup`+`Mutex`, race-free.

## Error Handling

Explicit: invalid Mass→error contains "mass", Volume→"volume", Height→"height", BaseRadius/TopRadius→"radius", SurfaceDensity→"density", Gradient→"gradient", depth/d→"depth", tol→"tol". Return 0 and non-nil error.

## Overflow Handling

After any multiplication/division that can overflow, if result Inf or NaN return error.
Example: `BuoyantMass` with `SurfaceDensity=1e200, Gradient=1e200, d=1e100, Height=1e100` must error not return Inf.
Example: `FrustumObject{BaseRadius=1e150,TopRadius=1e150,Height=1e150}.Volume()` must error.
Example: `SubmergedVolumeAtDepthFrustum` with `R1=1e150` must error if intermediate Inf.

## General
- No external deps, no hardcoded tables, reuse Step1 types.
