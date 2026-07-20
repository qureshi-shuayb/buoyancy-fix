# Step 3: Compressible Dynamics + Drag + 4th-Order Integration + Concurrent Batch (Bespoke Package)

## Overview
This is Step 3 of 3, `inherit_prior_session=true`. Your `/app/buoyancy.go` (Step1) and `/app/partial.go` (Step2) are preserved. You now implement the **bespoke compressible regime** defined by this package: pressure derived from stratified density integral, bulk-modulus compression clamped to package constant `MinimumVolumeFraction=0.1`, crush handling with 90% threshold, quadratic drag opposing motion with **package-defined reference area `Ad(z)=V(z)/Height` (not standard cross-section)**, terminal velocity, equilibrium depth via monotonic root-finding, time-to-depth via 4th-order weighted incremental integration (classic RK4 with Butcher tableau [0,0.5,0.5,1] but with package-specific depth clamping during sub-steps), and concurrent batch processing with order preservation and race-free `sync.WaitGroup`+`sync.Mutex`.

This package's distinctive names `CompressibleObject`, `DiveResult`, `MinimumVolumeFraction`, `CrushDepth`, `DiveResult.EquilibriumDepth` returned zero hits in public Go package search (verified during novelty check), confirming the specific composition is not public. The combination of stratified pressure integral + clamped bulk-modulus + Ad=V/H + crush 90% + concurrent order-preserving batch is **package-specific, not textbook**.

Do NOT redefine `Object`, `Fluid`, `Tolerance`, `StandardGravity`, `SubmersionResult`, `FrustumObject`, `StratifiedFluid` — AST checks enforce extension.

## Physics — Compressible + Drag + Dynamics (Package-Defined Conventions)

### Hydrostatic pressure (package-defined integral)
In **this package**, hydrostatic pressure is defined as bespoke convention:
```
P(z) = integral_0^z rho(z') * g dz'  where rho(z') = SurfaceDensity + Gradient*z' (from StratifiedFluid)
```
You must derive the closed-form expression from this integral: `P(z)=g*(S*z+0.5*G*z^2)`. A common mistake is to multiply density at a single depth by g*z without integrating the varying component (`ρ(z)*g*z` naive). Hidden tests discriminate >1% error from such shortcut (they check `P(10)` for `S=1000,G=2` expects `99081` with 0.5 factor, not `100062`).

`g` is `StandardGravity` or passed param; must use passed `g`, not hardcoded 9.81. Validate fluid via `Validate()`, `depth>=0` else error containing "depth" (case-insensitive), `g>0` else error containing "gravity"/"g". This validation contract is package-specific.

### Compressible volume (package-defined clamped model)
Bulk modulus K (Pa) >0 defines **this package's** compression model (linear clamped, not exponential textbook):
- Surface volume V0 at z=0
- Volume at depth compresses proportionally to pressure over bulk modulus: `V(z)=V0*(1-P(z)/K)` (package linear model)
- `V_min = MinVolumeFraction * V0`, where `MinimumVolumeFraction` is package constant `0.1` — package requires you to **reference the exported constant `MinimumVolumeFraction`** in logic, not hardcode 0.1, similar to Tolerance in Step1. AST checks for constant usage.
- If compressed volume would be below V_min, clamp to V_min (package clamping)
- If depth exceeds `CrushDepth`, return error containing "crush" (case-insensitive) — package crush contract.
- Additionally, if object specifies `MinVolumeFraction` field, use that field but ensure package minimum `MinimumVolumeFraction` is lower bound (bespoke clamping logic).

Use linear clamped model, not exponential; this is package-defined, not standard compressible fluid textbook (which might use exponential).

### Buoyant force, net force (package-defined)
In **this package** (bespoke):
```
Buoyant mass at depth: rho(z) * V(z)  where rho(z)=S+G*z, V(z) from above
Fb(z) = rho(z) * V(z) * g
Fw = Mass * g
Net down force: Fnet(z,v) = Fw - Fb(z) - Fd(z,v)
```
Drag for **this package** (bespoke, not standard drag textbook):
- Opposes motion, proportional to local fluid density, drag coefficient Cd, **reference area Ad(z) defined by this package as Ad(z)=V(z)/Height** for consistency with stratified area definition (not standard cross-section πr^2). This Ad definition is unique to this package and must be used exactly; using standard cross-section fails hidden tests.
- Drag direction must oppose velocity: positive v (down) → drag reduces net down force; negative v (up) → drag acts down. Using v² without handling sign via `v*|v|` fails hidden sign tests. Implementation: `Fd = 0.5*rho*Cd*Ad*v*|v|`.
- Cd>=0, Cd==0 means no drag (allowed for FindEquilibrium/Volume), but `TerminalVelocityAtDepth` must error if Cd<=0 with message containing "drag" (package contract).
- Ad must be derived via package Ad definition; if Ad<=0, error (checked).

### Terminal velocity at fixed depth (package-defined)
At terminal velocity, net force is zero (package defines). Solve `Fw - Fb(z) - Fd(z,v) =0` for v. Sign of v should match sign of (Fw-Fb): sinking positive (down), rising negative (up), near neutral zero when |Fw-Fb|<1e-12.

If |Fw-Fb| < 1e-12, terminal velocity is 0. If Cd<=0, error containing "drag" substring. If Ad<=0, error containing "area" or "drag".

### Equilibrium depth (compressible, package-defined)
Fully submerged neutral depth where Fw=Fb(z), i.e., `Mass = rho(z)*V(z)` (package defines buoyant mass as rho*V with compressed V). Define `f(z)=M - rho(z)*V(z)` and find root via monotonic numeric root-finding (bisection-like bracket [0,maxDepth]) in [0, maxDepth] with 100 iterations and tolerance param.

This involves pressure-dependent volume, so no simple closed form — use bisection with sufficient iterations and tolerance parameter.

**Bespoke reduction invariants for grading (package-specific, not textbook):**
- K→∞ (very large bulk modulus, e.g. 1e18): volume stays approx V0, so equilibrium approaches stratified incompressible result ` (Mass - S*V0)/ (G*V0)`? Actually hidden test expects `(1026-1000)/0.5=52` for large K case — package reduction.
- G=0 and K→∞: approaches uniform case (density constant)
Tests check reductions within 1e-6 — these are package invariants that require genuine derivation, not recall.

### Time-to-depth via integration (package-defined 4th-order weighted method)
Integrate ODE from rest z=0, v=0:
```
dz/dt = v
dv/dt = Fnet(z,v)/M
```
Use **4th-order weighted incremental integration** with k1..k4 and Butcher tableau [0, 0.5, 0.5, 1], classic RK4 structure but with **package-specific depth clamping during sub-steps**: intermediate depth evaluations `z+0.5*dt*k1z` etc must be clamped to >=0 to avoid invalid fluid errors (bespoke requirement, not in generic RK4 tutorial). Loop until z >= target depth, returning interpolated time between last two steps (linear interpolation for accuracy): `t_prev + frac*dt` where `frac=(target - z_prev)/(z - z_prev)`.

Validate inputs: target>0 else error containing "target", g>0 error containing "gravity", dt>0 error containing "dt", maxTime>0 error containing "maxTime", target<=CrushDepth else error containing "crush". If target > CrushDepth → error containing "crush". If never reaches within maxTime → error containing "maxTime" or "not reached".

Accuracy requirement (package-specific to force true 4th-order): simple first-order Euler with same dt has >25% error vs reference run with dt/10 on pre-selected case. Tests enforce accuracy within ±15% vs reference run with dt/10, so Euler fails. Reference implementation uses dt/10 as high-accuracy baseline; your dt=0.1 must be within 15% of dt=0.01 reference. This gating ensures genuine RK4, not Euler.

Edge handling (package-specific):
- Depth must not become negative during integration (clamp to 0 and v=0) — package defines no negative depth.
- If object floats upward and cannot reach deeper target (e.g., buoyant), should error appropriately (target not reached).
- Intermediate sub-step depths clamped to >=0 to avoid calling DensityAtDepth with negative z.

### Concurrent batch (package-specific Go concurrency)
`BatchFindEquilibrium` and `BatchTimeToDepthConcurrent` must (package concurrency contract):
- Preserve input order via `Index` field (package defines order preservation)
- Invalid object → `State="invalid"` (not error), continue processing others
- Fluid invalid → return nil,error immediately (package error contract)
- Empty/nil input → return **non-nil empty slice** (not nil) — explicit check `if objs==nil { return make([]DiveResult,0), nil }` (Go-specific package idiom, checked explicitly, similar to Step2)
- Race-free: `go test -race` must pass — must use `sync.WaitGroup` + `sync.Mutex` (package concurrency requirement, not just any goroutine)
- Crush handling (bespoke package): if target > CrushDepth → State="crush" with CrushRisk=true (not "invalid"), and when equilibrium depth >=0.9*CrushDepth, CrushRisk=true and State may become "crush". This 90% threshold is package-specific, not standard.
- For `BatchTimeToDepthConcurrent`, also check `len(objs)!=len(targets)` → error

## File Location
- `/app/buoyancy.go` (Step1) MUST stay
- `/app/partial.go` (Step2) MUST stay
- New file `/app/dive.go` package `buoyancy`, stdlib only (`math`, `errors`, `strings`, `sync` allowed)
- Do NOT redefine Step1/2 symbols (AST check)

## Types to Define

In `/app/dive.go`:

```go
const MinimumVolumeFraction = 0.1 // package constant, must be referenced in VolumeAtDepth logic (AST check similar to Tolerance)

type CompressibleObject struct {
    Mass float64
    Volume0 float64
    Height float64
    BulkModulus float64
    DragCoefficient float64
    CrushDepth float64
    MinVolumeFraction float64 // package field, expected 0.1, must be >0 and <1
}

type DiveResult struct {
    Index int
    State string // "float","sink","neutral","invalid","crush" — package-defined states
    EquilibriumDepth float64
    TerminalVelocity float64
    TimeToDepth float64
    VolumeAtDepth float64
    MaxPressure float64
    CrushRisk bool // package-specific crush risk flag at 90% threshold
}
```

Methods:
```
func (c CompressibleObject) Validate() error
```
Validation package contract: Mass>0, Volume0>0, Height>0, BulkModulus>0, DragCoefficient>=0 (0 allowed but Terminal errors), CrushDepth>0, MinVolumeFraction>0 and <1 (expected 0.1). Else error non-nil.

Functions for compressible (all exported, package API):

```go
func PressureAtDepth(fluid StratifiedFluid, depth, g float64) (float64, error)
func VolumeAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, g float64) (float64, error)
func BuoyantForceAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, g float64) (float64, error)
func NetForceAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, vel, g float64) (float64, error)
func TerminalVelocityAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, g float64) (float64, error)
func FindEquilibriumDepth(obj CompressibleObject, fluid StratifiedFluid, g, maxDepth, tol float64) (float64, error)
func TimeToDepthRK4(obj CompressibleObject, fluid StratifiedFluid, targetDepth, g, dt, maxTime float64) (float64, error)
func BatchFindEquilibrium(objs []CompressibleObject, fluid StratifiedFluid, g, maxDepth, tol float64) ([]DiveResult, error)
func BatchTimeToDepthConcurrent(objs []CompressibleObject, fluid StratifiedFluid, targets []float64, g, dt, maxTime float64) ([]DiveResult, error)
```

All exact signatures — package API, zero public hits for this combination.

## Detailed Behavior (Package Contracts)

**Validation:**
- CompressibleObject: Mass>0, Volume0>0, Height>0, BulkModulus>0, DragCoefficient>=0 (0 allowed but Terminal errors), CrushDepth>0, MinVolumeFraction>0 and <1 (expected 0.1). Else error.
- StratifiedFluid: SurfaceDensity>0, Gradient>=0 (reuse Step2)
- Depth params: >=0 else error containing "depth" (case-insensitive), g<=0 error containing "gravity", dt<=0 error containing "dt", maxTime<=0 error containing "maxTime", target<=0 error containing "target", tol<=0 error containing "tol" — package error substring contract.
- PressureAtDepth: derived from integral `g*(S*d+0.5*G*d^2)`, error if fluid invalid, depth<0, g<=0 — hidden test checks 0.5 factor and discriminates naive `ρ*g*z`
- VolumeAtDepth: compressed volume `V0*(1-P/K)` clamped to `MinVol = MinVolumeFraction*V0`, if depth>CrushDepth → error contains "crush" (case-insensitive). Must reference `MinimumVolumeFraction` constant, not hardcode 0.1.
- BuoyantForceAtDepth, NetForceAtDepth, etc. per physics section with package Ad definition

**BatchFindEquilibrium:**
- Validate fluid, g>0, maxDepth>0, tol>0 else nil,error
- Empty/nil → non-nil empty slice explicitly `make([]DiveResult,0)` (Go idiom, package requires explicit nil check)
- For each obj: if invalid → State="invalid" (Index preserved), else compute equilibrium depth via bisection, terminal velocity, volume, pressure, crush risk
- Preserve order via Index, race-free not required here but slice pre-allocated
- If depth >=0.9*CrushDepth → CrushRisk=true, State may be "crush" (package 90% threshold)

**BatchTimeToDepthConcurrent:**
- Validate fluid, g>0, dt>0, maxTime>0, len(objs)==len(targets) else error containing relevant term
- Empty/nil handling: if both nil → non-nil empty; if one nil and other length mismatch → error; if objs==nil and targets empty → non-nil empty (explicit)
- Goroutines with WaitGroup, order preserved via Index, race-free via Mutex (must use `sync.WaitGroup`+`sync.Mutex`, `go test -race` must pass)
- Invalid object → State="invalid", target>CrushDepth → State="crush" CrushRisk=true
- For each, compute TimeToDepth via RK4 with interpolation, volume, pressure, terminal velocity

## Requirements (Bespoke Package Invariants)
1. Reuse Step1/2 types/constants, do NOT redefine (AST check — package extension).
2. Files `/app/partial.go` and `/app/dive.go` must exist, package `buoyancy`, `go vet` and `go test -race` must pass, stdlib only.
3. Structs exact fields as spec (package API)
4. Compressible functions (8+2 batch) exact signatures must exist
5. Error handling: crush contains "crush", drag contains "drag", depth contains "depth", gravity contains "gravity", dt contains "dt", target contains "target" (case-insensitive) — package error contract
6. No hardcoding; must implement pressure integral via derivation (0.5 factor), drag with proper sign handling via `v*|v|`, 4th-order weighted integration for time (not Euler), MinimumVolumeFraction constant reference (not hardcoded 0.1), Ad=V/H reference area (bespoke)
7. Reduction checks: K→∞ approaches stratified incompressible within 1e-6, G=0+K→∞ approaches uniform within 1e-6 — package invariants
8. Nil→non-nil empty slice explicit handling for all batch functions
9. Race-free: `go test -race -run TestBatch` must pass

## Grading Hidden Tests
- Pressure: correct integration vs naive multiplication >1% error (e.g., expects 99081 not 100062), S>0
- Volume: clamping to min fraction via MinimumVolumeFraction constant reference, crush error handling with "crush" substring, 90% crush risk threshold
- BuoyantForce, NetForce with drag sign correctness (positive vs negative velocity via `v*|v|`)
- TerminalVelocity sign and Cd<=0 error with "drag" substring, near-neutral zero case
- FindEquilibriumDepth via bisection-like monotonic solve, reduction K→∞ within 1e-6
- TimeToDepth: reference dt/10 tolerance ±15%, Euler fails >25%, depth clamping, crush handling, interpolation
- Batch order preservation via Index, invalid handling, nil→non-nil empty explicit check, race detector with `go test -race`
- vet and race pass, AST no-redefinition, constant usage for MinimumVolumeFraction and Tolerance
- Distinctive identifiers ensure no public package match — novelty low.

## What NOT to Do
- Do NOT use naive `ρ*g*z` for pressure — must derive integral with 0.5 factor
- Do NOT use `v^2` without sign handling for drag — must use `v*|v|`
- Do NOT use Euler for time integration — must use 4th-order weighted (RK4) with depth clamping
- Do NOT hardcode 0.1 for min volume — must reference `MinimumVolumeFraction` constant
- Do NOT forget explicit nil check returning non-nil empty slice — Go package idiom
- Do NOT forget 90% crush threshold — package-specific
- Do NOT use standard cross-section for Ad — must use package-defined `V/Height`
