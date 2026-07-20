# Step 3: Compressible Dynamics + Drag + RK4 + Concurrent Batch

## Overview
This is Step 3 of 3, `inherit_prior_session=true`. Your `/app/buoyancy.go` (Step1) and `/app/partial.go` (Step2) are preserved. You now implement the compressible regime with pressure derived from density profile, bulk-modulus compression with clamping, drag opposing motion, terminal velocity, equilibrium depth, time-to-depth integration, and concurrent batch processing.

Do NOT redefine `Object`, `Fluid`, `Tolerance`, `StandardGravity`, `SubmersionResult`, `FrustumObject`, `StratifiedFluid`.

## Physics — Compressible + Drag + Dynamics

### Hydrostatic pressure
In this package, hydrostatic pressure is defined via:
```
P(z) = integral_0^z rho(z') * g dz'  where rho(z') = SurfaceDensity + Gradient*z'
```
You must derive the closed-form expression from this integral. A common mistake is to multiply density at a single depth by g*z without integrating the varying component — hidden tests discriminate >1% error from such shortcut.

`g` is `StandardGravity` or passed param. Validate fluid, depth>=0, g>0 else error.

### Compressible volume
Bulk modulus K (Pa) >0 defines this package's compression model:
- Surface volume V0
- Volume at depth compresses proportionally to pressure over bulk modulus, clamped to minimum fraction
- V_min = MinVolumeFraction * V0, MinimumVolumeFraction is 0.1
- If compressed volume would be below V_min, clamp to V_min
- If depth exceeds CrushDepth, return error containing "crush" (case-insensitive)

Use linear clamped model, not exponential.

### Buoyant force, net force
In this package:
```
Buoyant mass at depth: rho(z) * V(z)
Fb(z) = rho(z) * V(z) * g
Fw = Mass * g
Net down force: Fnet(z,v) = Fw - Fb(z) - Fd(z,v)
```
Drag for this package:
- Opposes motion, proportional to local fluid density, drag coefficient Cd, reference area Ad(z), and velocity squared
- This package defines Ad(z) = V(z)/Height for consistency with stratified area definition
- Drag direction must oppose velocity: positive v (down) → drag reduces net down force; negative v (up) → drag acts down. Using v² without handling sign fails hidden sign tests.
- Cd>=0, Cd==0 means no drag, but TerminalVelocity must error if Cd<=0 with message containing "drag".

### Terminal velocity at fixed depth
At terminal velocity, net force is zero. Solve Fw - Fb(z) - Fd(z,v) = 0 for v. Sign of v should match sign of (Fw-Fb): sinking positive, rising negative, near neutral zero.

If |Fw-Fb| < 1e-12, terminal velocity is 0. If Cd<=0, error containing "drag". If Ad<=0, error.

### Equilibrium depth (compressible)
Fully submerged neutral depth where Fw=Fb(z), i.e., Mass = rho(z)*V(z). Define f(z)=M - rho(z)*V(z) and find root via bisection in [0, maxDepth].

This involves pressure-dependent volume, so no simple closed form — use bisection with sufficient iterations and tolerance parameter.

Reductions for grading:
- K→∞ (very large bulk modulus): volume stays approx V0, so equilibrium approaches stratified incompressible result
- G=0 and K→∞: approaches uniform case
Tests check reductions within 1e-6.

### Time-to-depth via integration
Integrate ODE from rest z=0, v=0:
```
dz/dt = v
dv/dt = Fnet(z,v)/M
```
Use 4th-order integration with step dt that is more accurate than Euler. Loop until z >= target depth, returning interpolated time between last two steps (linear interpolation for accuracy). Validate inputs: target>0, g>0, dt>0, maxTime>0, target<=CrushDepth else error containing "crush". If never reaches within maxTime, error.

Accuracy requirement: simple first-order Euler with same dt has >25% error vs reference with dt/10 on pre-selected case. Tests enforce accuracy within ±15% vs reference run with dt/10, so Euler fails.

Edge handling:
- Depth must not become negative during integration (clamp)
- If object floats upward and cannot reach deeper target, should error appropriately

### Concurrent batch
`BatchFindEquilibrium` and `BatchTimeToDepthConcurrent` must:
- Preserve input order via Index field
- Invalid object → State="invalid", continue processing others
- Fluid invalid → return nil,error immediately
- Empty/nil input → return non-nil empty slice (not nil) — explicit check `if objs==nil { return make(...,0), nil }`
- Race-free: `go test -race` must pass — use sync.WaitGroup + sync.Mutex
- Crush handling: if target > CrushDepth → State="crush" with CrushRisk=true (not invalid), and when equilibrium depth >=0.9*CrushDepth, CrushRisk=true and State may become "crush"

## File Location
- `/app/buoyancy.go` (Step1) MUST stay
- `/app/partial.go` (Step2) MUST stay
- New file `/app/dive.go` package `buoyancy`, stdlib only
- Do NOT redefine Step1/2 symbols (AST check)

## Types to Define

In `/app/dive.go`:

```go
const MinimumVolumeFraction = 0.1

type CompressibleObject struct {
    Mass float64
    Volume0 float64
    Height float64
    BulkModulus float64
    DragCoefficient float64
    CrushDepth float64
    MinVolumeFraction float64
}

type DiveResult struct {
    Index int
    State string
    EquilibriumDepth float64
    TerminalVelocity float64
    TimeToDepth float64
    VolumeAtDepth float64
    MaxPressure float64
    CrushRisk bool
}
```

Methods:
```
func (c CompressibleObject) Validate() error
```

Functions for compressible (all exported):

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

All exact signatures.

## Detailed Behavior

**Validation:**
- CompressibleObject: Mass>0, Volume0>0, Height>0, BulkModulus>0, DragCoefficient>=0 (0 allowed but Terminal errors), CrushDepth>0, MinVolumeFraction>0 and <1 (expected 0.1). Else error.
- StratifiedFluid: SurfaceDensity>0, Gradient>=0
- Depth params: >=0 else error containing "depth", g<=0 error containing "gravity", dt<=0 error "dt", maxTime<=0 error "maxTime", target<=0 error "target", tol<=0 error "tol"
- PressureAtDepth: derived from integral, error if fluid invalid, depth<0, g<=0
- VolumeAtDepth: compressed volume clamped to MinVol, if depth>CrushDepth → error contains "crush"
- BuoyantForceAtDepth, NetForceAtDepth, etc. per physics section

**BatchFindEquilibrium:**
- Validate fluid, g>0, maxDepth>0, tol>0 else nil,error
- Empty/nil → non-nil empty slice explicitly
- For each obj: if invalid → State="invalid", else compute equilibrium depth, terminal velocity, volume, pressure, crush risk
- Preserve order via Index, race-free
- If depth >=0.9*CrushDepth → CrushRisk=true, State may be "crush"

**BatchTimeToDepthConcurrent:**
- Validate fluid, g>0, dt>0, maxTime>0, len(objs)==len(targets) else error
- Goroutines with WaitGroup, order preserved, race-free, explicit nil handling

## Requirements
1. Reuse Step1/2 types/constants, do NOT redefine (AST check).
2. Files `/app/partial.go` and `/app/dive.go` must exist, package `buoyancy`, `go vet` and `go test -race` must pass, stdlib only.
3. Structs exact fields as spec.
4. Compressible functions (8+2 batch) exact signatures must exist.
5. Error handling: crush contains "crush", drag contains "drag", depth contains "depth" (case-insensitive).
6. No hardcoding; must implement pressure integral via derivation, drag with proper sign handling, 4th-order integration for time.
7. Reduction checks: K→∞ and G=0 must match expectations within 1e-6.

## Grading Hidden Tests
- Pressure: correct integration vs naive multiplication >1% error, S=0? no, S>0
- Volume: clamping to min fraction, crush error handling, 90% crush risk threshold
- BuoyantForce, NetForce with drag sign correctness (positive vs negative velocity)
- TerminalVelocity sign and Cd<=0 error, near-neutral zero
- FindEquilibriumDepth via bisection, reduction K→∞
- TimeToDepth: reference dt/10 tolerance ±15%, Euler fails >25%
- Batch order preservation, invalid handling, nil → non-nil empty, race detector with `go test -race`
- vet and race pass
