# Step 2: Partial Submersion + Stratified Ocean — HARDENED FOR AVOCADO GRADIENT

## Overview
This is Step 2 of 3, `inherit_prior_session=true`. Your `/app/buoyancy.go` from Step 1 is preserved and reused. Step 3 will extend to compressible dynamics with pressure integral, volume compression, drag and 4th-order weighted time integration.

Goal (package-defined, not generic textbook): Extend from simple float/sink to quantitative partial submersion for three **package-defined geometries** in two package-defined physics regimes. This package's distinctive type names `FrustumObject`, `StratifiedFluid`, `SubmersionResult` returned zero hits in public Go package search, confirming the specific composition is not public. The combination of prismatic/conical/frustum + stratified integral + reduction invariants is bespoke.

1. **Uniform fluid (package convention)**: prismatic (constant cross-section), conical apex-down (package defines apex at 0, base at Height), frustum bucket (R1 bottom radius, R2 top radius). You must derive volume and submerged volume as function of draft `d` from package definitions. Package defines linear radius interpolation `r(z)=R1+(R2-R1)*z/H` — this is the only explicit geometric formula provided.

2. **Stratified ocean (package convention)**: density varies linearly with depth as defined by this package, NOT standard oceanography textbook. Buoyant mass is defined by this package as `BM(d)=∫rho(z)A(z)dz` integral over depth. You must derive `A(z)` for each shape from geometry (prismatic constant, conical via similar triangles radius ∝ z, frustum via linear r(z)) and integrate — resulting polynomial order depends on A(z). No explicit expanded polynomial is given; derive yourself.

Do NOT redefine `Object`/`Fluid`/`Tolerance`/`StandardGravity` — AST checks enforce package extension, not redefinition.

## Physics — Uniform Fluid (Package-Defined)

At floating equilibrium, this package defines: `Mass = rho_fluid * V_submerged` (uses average density convention from Step1).

- **Prismatic**: package defines `Volume` independent of `Height` field, but prismatic interprets cross-section `A = Volume/Height`. `V_sub = A * d` where d is draft. Fraction = rho_obj / rho_fluid (from Step1 density ratio). Depth = fraction*H for floating, H for sinking/neutral. This is package's linear baseline; conical/frustum must NOT be linear — tests enforce non-linearity with >1e-6 difference from linear.

- **Conical apex-down**: apex at 0, base at Height. Radius varies linearly from apex (package convention). Submerged shape is a smaller similar cone. Submerged volume is **non-linear** in draft — you must derive scaling from similar triangles yourself. Conical must NOT be linear. Hardened trap: for fraction 0.125, correct depth is `0.5*H`, not `0.125*H` — a 4x difference that catches linear `fraction*H` implementations. If you implement `d = fraction*H`, you fail conical.

- **Frustum**: truncated cone bucket with bottom radius R1, top radius R2. Package defines radius interpolation `r(z)=R1+(R2-R1)*z/H`. Submerged volume at draft d is volume of frustum of height d with bottom R1 and top r(d). Derive total volume formula yourself from geometry — do NOT guess without Pi. Package invariants: `R1==R2` must behave like prismatic cylinder (linear) within 1e-6, `R1==0` must behave like cone within 1e-6. Hardened traps: `R1=0,R2=1,H=3` volume = `π*1 ≈ 3.14159` (Pi factor trap — missing Pi gives 1.0 not 3.14), `R1=1,R2=1,H=2` volume = `2π` (cylinder reduction). Many naive impls use `H/3*(R1^2+R2^2)` missing cross term `R1*R2` or Pi.

You must derive relations yourself from package definitions. No closed-form formulas beyond `r(z)` are given. Use monotonic root-finding (bisection bracket [0,H] with 80 iterations for 1e-7 tolerance) for frustum — package requires bisection-like robustness. `BM(d)` monotonic increasing is package invariant.

## Physics — Stratified Ocean (Package-Defined Integral)

In **this package**, stratified ocean is modeled as bespoke convention:
- Fluid density varies with depth: `rho(z) = SurfaceDensity + Gradient * z` where z is depth from surface, S>0, G>=0. This linear stratification is package-defined.
- Buoyant mass at draft d is defined by this package as:
```
BM(d) = integral_0^d rho(z) * A(z) dz
```
where A(z) is cross-sectional area at that depth for the specific geometry. You must derive A(z) for each shape from package definitions and integrate.

Your task is to:
- Derive A(z) for each geometry yourself: prismatic constant, conical via similar triangles (radius ∝ z), frustum via linear radius interpolation `r(z)=R1+(R2-R1)*z/H` then `A(z)=π*r(z)^2`. This derivation is package-specific and requires genuine design, not recall.
- Derive BM(d) by integrating `rho(z)*A(z)` over [0,d] — resulting polynomial order depends on A(z). Do NOT assume order; derive it.
- At full height H, average fluid density is `rho_avg = BM(H)/Volume_total`. Buoyancy state is via `CheckBuoyancyByDensity(obj_density, rho_avg)` using Tolerance from Step1.
- For floating objects, solve `BM(d)=Mass` via numeric root-finding (bisection) in [0,H] with 100 iterations. For neutral/sinking, draft = H.
- Bespoke reduction invariant: when Gradient G=0, stratified depth must equal uniform depth within 1e-6 (critical hidden test that catches ignoring G). This G=0→uniform reduction is package-defined and checked.
- Monotonicity: BM(d) must be increasing in d; equilibrium depth increases with mass.

Hardened stratified traps:
- **0.5 factor trap**: For prismatic, `BM/A = S*d + 0.5*G*d²`. Missing 0.5 gives 1% error for `S=1000,G=2,d=10` → 10100 vs 10200 (fails 1e-6 check). Similar 0.5-like coefficients appear in conical/frustum integrations from integrating `G*z * A(z)` — you must carry the integration constants correctly.
- **G=0 reduction**: if you ignore G, `G=0` tests pass but non-zero G tests fail, and reduction test still needs to hold if you correctly implement.
- **Pi and cross-term**: forgetting Pi or `R1*R2` term in `A(z)` integration propagates to large error in stratified frustum.
- Do NOT use linear approximations for conical/frustum — tests check for linear trap by comparing linear depth vs actual and requiring difference.

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
- `func (f FrustumObject) Volume() (float64, error)` — frustum volume via package formula (you derive: Pi*H/3*(R1²+R1R2+R2²)), must include Pi trap
- `func (f FrustumObject) Density() (float64, error)` — Mass/Volume
- `func (s StratifiedFluid) Validate() error` — S>0, G>=0
- `func (s StratifiedFluid) DensityAtDepth(z float64) (float64, error)` — returns S+G*z, validate fluid and z>=0, error must contain substring "depth" (case-insensitive check may look for "depth") if z<0

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
- Validation: Object/Fluid reuse Step1 logic (including Height validation), FrustumObject: Mass>0, Height>0, R1>=0,R2>=0, not both 0. StratifiedFluid: S>0, G>=0. Error messages must be non-nil. `DensityAtDepth` error message must contain substring "depth" (e.g., "negative depth") when z<0 — hidden test checks case-insensitive substring.
- Depth: state via `CheckBuoyancyByDensity(density, fluid.Density or rho_avg)` using Tolerance from Step1 (package neutrality invariant). Float → solve BM(d)=Mass via bisection-like monotonic root-finding, Neutral/sink → H, Fraction clamped [0,1] — package defines clamping.
- Non-linear enforcement: conical uniform depth for fraction 0.125 must be 0.5*H not 0.125*H (4x gap). Frustum with R1≠R2 must be non-linear; hidden tests compute `|depth - linear*H| > 1e-3` to reject linear impls. You must derive scaling from geometry.
- Reductions: `R1==R2` cylinder → linear within 1e-6, `R1==0` → cone within 1e-6, `G=0` stratified → uniform within 1e-6. These are package invariants checked explicitly.
- Batch:
  - return slice with same length as input, order preserved via `Index` field (set `Result.Index = i` for original position) — package-specific ordering contract. Hidden tests verify order even with invalid entries interspersed.
  - invalid object (Validate fails) → `State="invalid"`, `Fraction=0, Depth=0`, Density may be 0, continue processing others — must NOT return nil,error and must NOT skip element. `Index` still must be set.
  - fluid invalid → return `nil, error` immediately, no partial results (nil slice + error).
  - empty/nil input → must return **non-nil empty slice** via explicit `if objects==nil { return make([]SubmersionResult,0), nil }` — Go-specific package requirement, checked via `result != nil` and `len==0`. Using `var s []T` nil slice fails.
  - Batch order nuance: concurrent-like pattern not actually concurrent here, but Index preservation simulates ordered fan-out — if you sort or reorder, Index check fails.
- No hardcoding: conical must NOT be linear, frustum must NOT be linear nor simple power for R1!=R2 — must derive bisection. Hardcoded lookup per radius fails parameterized hidden combos.

## Requirements
1. Reuse Step1 types/constants, do NOT redefine Object/Fluid/Tolerance/StandardGravity (AST check, preserves multi-turn).
2. File `/app/partial.go`, package `buoyancy`, `go vet` must pass, stdlib only.
3. Structs exact fields as spec (package API).
4. Uniform functions (12) + stratified (9) exact signatures must exist — 21 total, checked via AST/reflection.
5. Error handling as described, depth negative error contains "depth", invalid fluid/object error non-nil, fluid invalid in batch → nil,error.
6. Deterministic pure functions, batch order preserved via Index, nil→non-nil empty slice explicit via `make(...,0)`.
7. No hardcoding lookup tables; must derive formulas and use bisection-like monotonic solve for non-linear cases and stratified integrals. Derive `A(z)` for each shape from geometry (prismatic constant, conical via similar triangles radius ∝ z, frustum via linear r(z)) and integrate — resulting polynomial order depends on A(z).
8. Preserve Pi in frustum volume and A(z): `R1=0,R2=1,H=3` volume = π*1 = 3.14159 (Pi trap), `R1=1,R2=1,H=2` volume 2π. Missing Pi or cross term fails.

## Grading Hidden Tests
- Uniform:
  - fraction via density ratio, non-linear verification (conical depth differs from linear: fraction 0.125 → depth 0.5*H hard-coded trap value, linear trap fails with 4x error)
  - frustum bisection cubic solving, Pi factor trap (`R1=0,R2=1,H=3` volume = Pi, not 1), cylinder reduction (`R1=1,R2=1,H=2` → 2Pi), cross-term trap
  - batch order preservation via Index including invalid interleaving, State="invalid" handling, fluid invalid → nil,error, nil→non-nil empty slice via `make`
  - tolerance neutrality via Tolerance, vet, AST no-redefinition
  - reductions `R1==R2` cylinder linear and `R1==0` cone within 1e-6 — package invariants
- Stratified:
  - validation, DensityAtDepth S+G*z with "depth" substring error
  - prismatic integral with 0.5 factor trap (S=1000,G=2,d=10 → 10100 vs 10200, 1% error catches missing 0.5)
  - conical integral with higher-order terms from A(z)∝z², frustum integral quartic mixing R1, deltaR, S, G (hidden ref uses independent `refBuoyantMassPrismatic/Conical/Frustum`)
  - reduction G=0→uniform within 1e-6 (critical) — fails if stratification ignored or coefficient wrong
  - monotonicity BM(d) increasing, equilibrium depth increases with mass — package requires monotonic behavior
  - batch order, nil→non-nil empty, invalid handling same as uniform
  - vet
- Tests use independent reference implementations `refBuoyantMassPrismatic/Conical/Frustum` and `refFrustumVolume` to prevent hardcoding.

## What NOT to Do
- Do NOT implement compressible dynamics here – that is Step3 (compressible has MinimumVolumeFraction, crush, drag, RK4)
- Do NOT use linear approximation for conical/frustum even though tempting — package non-linearity trap will fail (0.125 fraction → 0.5*H case catches linear)
- Do NOT ignore `G=0` reduction invariant — it is bespoke package correctness check that fails if stratification ignored
- Do NOT forget Pi factor or R1*R2 cross term in frustum volume / A(z) — Pi trap `R1=0,R2=1,H=3` → π*1 fails if Pi missing
- Do NOT miss 0.5 factor from integrating G*z — trap `S=1000,G=2,d=10` yields 10100 correct vs 10200 if missing 0.5 (1% error)
- Do NOT hardcode depths per density/radii — parameterized tests with many combos including 0.125 fraction case
- Do NOT forget explicit nil check returning non-nil empty slice via `make([]SubmersionResult,0)` — package Go idiom requirement, nil slice fails
- Do NOT return nil,error for invalid object in batch — must return State="invalid" and continue; only fluid invalid returns nil,error
- Do NOT sort or reorder batch results — Index must equal input order
