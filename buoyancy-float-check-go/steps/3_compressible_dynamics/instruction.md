# Step 3: Compressible Dynamics + Drag + RK4 + Concurrent Batch (Hardest)

## Overview
This is **Step 3 of 3**, `inherit_prior_session=true`. Your `/app/buoyancy.go` (Step1) and `/app/partial.go` (Step2 uniform+stratified) are preserved. You now implement the final compressible regime.

Goal: Ocean stratification + hydrostatic pressure + bulk-modulus volume compression + quadratic drag + time-to-depth via RK4 + concurrent batch. This is the ultra-hard tier that was previously bundled into Step2, now isolated so Opus can still solve Step2 but be tested on Step3.

Your task passes only if it implements compressible dynamics on top of stratified ocean.

Do NOT redefine `Object`/`Fluid`/`Tolerance`/`StandardGravity`/`SubmersionResult`/`FrustumObject`/`StratifiedFluid`.

## Physics – Compressible + Drag + Dynamics (ultra-hard, novel)

### Hydrostatic pressure
Pressure at depth `z` is integral of weight of overlying fluid:
```
P(z) = ∫_0^z rho(z') g dz'
     = g * ∫_0^z (S + G*z') dz'
     = g * (S*z + 0.5*G*z²)
```
You must derive the 0.5 factor: `∫0^z G*z' dz' = 0.5*G*z²`. Tests check `S=1000 G=2 depth10 => 99081 Pa` not `100062 Pa` (0.5 missing). `g` is `StandardGravity` or passed param.

### Compressible volume
Bulk modulus `K` (Pa) >0. Linear clamped model (testable):
```
V(z) = V0 * (1 - P(z)/K)   clamped to V_min = f_min*V0, f_min = MinimumVolumeFraction (0.1)
If P(z)/K >= 1-f_min → V=V_min
If depth > CrushDepth → error containing "crush" (case-insensitive)
V0 = surface volume (Object.Volume or FrustumObject.Volume())
```
Use linear clamped model, not exp.

### Buoyant force, net force
```
Fb(z) = rho(z) * V(z) * g
Fw = Mass * g
Buoyant mass = rho(z)*V(z)
Net down force: Fnet(z,v) = Fw - Fb(z) - Fd(z,v)
Fd(z,v) = 0.5 * rho(z) * Cd * Ad(z) * v*|v|   opposes motion, sign trap: must use v*|v| not v²
Ad(z): reference area for drag – for simplicity use cross-sectional area at depth: `Ad = V(z)/Height` for prismatic reference (consistent with stratified `A(z)`). For generic compressible object we define Ad = VolumeAtDepth/Height.
```
`Cd>=0`, `Cd==0` → no drag, but TerminalVelocity must error if Cd<=0 containing "drag".
`Fd` sign: down positive. `v positive down` => `Fd positive` subtract, `v negative up` => `Fd negative` subtract -> net down increases (drag pushes down when rising). Must use `v*|v|`.

### Terminal velocity at fixed depth
Set `Fnet=0` ignoring acceleration: `Fw - Fb(z) - 0.5 rho Cd Ad v²*sign(v)=0`
```
v_term(z) = sign(Fw-Fb) * sqrt(2*|Fw-Fb|/(rho(z)*Cd*Ad(z)))
If |Fw-Fb|<1e-12 → 0, Cd<=0 → error containing "drag", Ad<=0 → error
```

### Equilibrium depth (compressible)
Fully submerged neutral depth where `Fw=Fb(z)` i.e. `M = rho(z)*V(z)`:
```
f(z)=M - rho(z)*V(z)=0
     =M - (S+Gz)*V0*(1 - P(z)/K)
With P(z)=g(Sz+0.5 Gz²) → cubic/quadratic in z, no closed form → bisection 100 iter in [0,maxDepth]
```
Reductions for grading:
- `K→∞` (incompressible): `f(z)=M-(S+Gz)V0` → stratified incompressible, so `(M/V0-S)/G`
- `G=0, K→∞`: `M-S V0` → uniform
Tests check reductions within 1e-6.

### Time-to-depth via RK4
Integrate ODE from rest `z=0,v=0`:
```
dz/dt = v
dv/dt = Fnet(z,v)/M
```
Classic RK4 with step `dt`:
```
k1_z=v, k1_v=Fnet(z,v)/M
k2_z=v+0.5 dt k1_v, k2_v=Fnet(z+0.5 dt k1_z, v+0.5 dt k1_v)/M
k3_z=v+0.5 dt k2_v, k3_v=Fnet(z+0.5 dt k2_z, v+0.5 dt k2_v)/M
k4_z=v+dt k3_v, k4_v=Fnet(z+dt k3_z, v+dt k3_v)/M
z+=dt/6*(k1_z+2k2_z+2k3_z+k4_z)
v+=dt/6*(k1_v+2k2_v+2k3_v+k4_v)
t+=dt
Loop until z>=target, return interpolated time between last two steps (linear interpolation). Required for accuracy.
Validate: target>0,g>0,dt>0,maxTime>0,target<=CrushDepth else crush error, if never reaches within maxTime → error, if Fw-Fb negative and object floats before target → may be unreachable.

Pre-selected case where Euler with same dt has >25% error vs RK4 reference dt/10, so tests enforce RK4 not Euler, tolerance ±15% vs reference dt/10 run.

### Concurrent batch
`BatchFindEquilibrium` and `BatchTimeToDepthConcurrent` must:
- Preserve input order via Index
- Invalid object → State="invalid" Fraction=0 Depth=0 etc, continue
- Fluid invalid → nil,error
- Empty/nil → non-nil empty slice
- Race-free `go test -race` must pass – use WaitGroup + mutex
- Crush handling: if target>CrushDepth → State="crush" (not invalid)

## File Location
- `/app/buoyancy.go` (Step1) MUST stay
- `/app/partial.go` (Step2) MUST stay
- New file `/app/dive.go` package `buoyancy`, stdlib only, contains compressible
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
- CompressibleObject: Mass>0, Volume0>0, Height>0, BulkModulus>0, DragCoefficient>=0 (0 allowed but Terminal errors), CrushDepth>0, MinVolumeFraction>0 and <1 (0.1). Else error.
- StratifiedFluid: SurfaceDensity>0, Gradient>=0
- Depth: >=0 else error containing "depth", g<=0 error containing "gravity", dt<=0 error "dt", maxTime<=0 error "maxTime", target<=0 error "target", tol<=0 error "tol"
- PressureAtDepth: `P = g*(S*depth+0.5*G*depth²)`, error if fluid invalid, depth<0, g<=0
- VolumeAtDepth: `V=V0*(1-P/K)` clamped to `MinVol`, if depth>CrushDepth → error contains "crush"
- BuoyantForceAtDepth, NetForceAtDepth, TerminalVelocity, FindEquilibriumDepth, TimeToDepthRK4 as spec in overview.

**BatchFindEquilibrium:**
- Validate fluid, g>0, maxDepth>0, tol>0 else nil,error
- Empty/nil → non-nil empty slice
- For each obj: if invalid → State="invalid", else compute equilibrium, terminal velocity, volume, pressure, crush risk
- Preserve order, race-free

**BatchTimeToDepthConcurrent:**
- Validate fluid, g>0, dt>0, maxTime>0, len(objs)==len(targets) else error
- Goroutines with WaitGroup, order preserved, race-free.

## Requirements
1. Reuse Step1/2 types/constants, do NOT redefine (AST check).
2. Files `/app/partial.go` and `/app/dive.go`, package `buoyancy`, `go vet` and `go test -race` must pass, stdlib only.
3. Structs exact fields as spec.
4. Compressible functions (8+2 batch) exact signatures.
5. Error handling: crush contains "crush", drag contains "drag", depth contains "depth" (case-insensitive).
6. No hardcoding; must implement pressure integral with 0.5 factor, drag sign `v|v|`, RK4 not Euler.
7. Reduction checks: K→∞ and G=0 must match.

## Grading Hidden Tests
- Pressure: S=1000 G=2 depth10 → 99081 (with 0.5) vs naive 100062 without 0.5
- Volume: V0=1 K=1e8 S=1025 G=0.5 depth100 g=9.81 → V≈V0*(1-P/K), clamp to min
- BuoyantForce, NetForce with drag sign
- TerminalVelocity sign, Cd<=0 error
- FindEquilibriumDepth via bisection, reduction K→∞ → (M/V0-S)/G
- TimeToDepthRK4: reference dt/10 tolerance ±15%, Euler fails >25%
- Batch order, invalid, race-free
- vet and race pass
