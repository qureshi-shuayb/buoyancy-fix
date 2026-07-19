# Step 2: Partial Submersion + Stratified + Compressible Dynamics (Uniform → Stratified → Compressible + Drag + RK4)

## Overview
This is **Step 2 of 2**, `inherit_prior_session=true`. Your `/app/buoyancy.go` from Step 1 is preserved.

Goal: Extend from simple float/sink to quantitative partial submersion for **three geometries** in **three physics regimes** increasing difficulty:
1. **Uniform fluid** baseline: prismatic (constant cross-section), conical apex-down (similar cones), frustum truncated cone bucket (R1 bottom, R2 top). Must derive volume and submerged volume vs draft yourself, no formulas given. Cubic relation → numeric bisection.
2. **Stratified ocean**: density varies linearly with depth `rho(z)=SurfaceDensity+Gradient*z`. Buoyant mass is **integral** `BM(d)=∫_0^d rho(z)A(z)dz` where `A(z)` is cross-sectional area at depth z. Must derive `A(z)` for each geometry. Quadratic for prismatic, quartic for conical/frustum. Requires bisection. Reduction `G=0 → uniform` must hold within 1e-6.
3. **Compressible + Drag + Dynamics (hardest)**: Ocean stratification + hydrostatic pressure + bulk-modulus volume compression + quadratic drag + time-to-depth via RK4 + concurrent batch. This is non-textbook combination where no single StackOverflow snippet exists.

Uniform + stratified from previous hardening are kept for backward compat; hardest part is compressible dynamics.

Do NOT redefine `Object`/`Fluid`/`Tolerance`/`StandardGravity`.

## Physics – Uniform (derive, no formula given)
- `Mass = rho_fluid * V_submerged` at equilibrium
- Prismatic: `A` constant, derive relation between `d`, `Height`, `V_sub`, `V_total`
- Conical apex-down: radius varies linearly from apex, submerged shape smaller similar cone, derive non-linear relation (must NOT be linear). Tests fail if linear.
- Frustum: bottom R1 top R2, radius varies linearly, submerged frustum, derive total volume and `V_sub(d)` yourself, cubic in d → bisection. `R1==R2` → cylinder, `R1==0` → cone reductions.

## Physics – Stratified (derive A(z) and integral, no formula given)
- `rho(z)=S+G*z`, `S>0, G>=0`, `z` depth from surface down
- `BM(d)=∫_0^d rho(z)A(z)dz`, `A(z)` cross-section at depth z:
  - Prismatic: constant `A=Vol/H`
  - Conical: derive R from V and H, `r(z)` linear, `A=pi r²`
  - Frustum: `r(z)=R1+(R2-R1)z/H`, `A=pi r²` quadratic
- Total volume `∫_0^H A(z)dz` must match uniform volume
- `BM(H)/Vol = rho_avg`, state via `CheckBuoyancyByDensity(rho_obj, rho_avg)` using Tolerance
- Float → `BM(d)=Mass` solve via bisection 80-100 iter, Neutral/sink → H
- Reduction `G=0` must equal uniform depth within 1e-6

## Physics – Compressible + Drag + Dynamics (ultra-hard, novel)

### Hydrostatic pressure
Pressure at depth `z` is integral of weight of overlying fluid:
```
P(z) = ∫_0^z rho(z') g dz'
```
You must derive integral yourself from `rho(z)=S+G*z`. No 0.5 factor given. `g` is StandardGravity or passed `g` param (validate >0).

### Compressible volume
Bulk modulus `K` (Pa) >0. Linear clamped model (testable):
```
V(z) = V0 * (1 - P(z)/K)   clamped to V_min = f_min*V0, f_min = MinimumVolumeFraction (0.1)
If P(z)/K >= 1-f_min → V=V_min
If depth > CrushDepth → must return error containing "crush" (case-insensitive check)
V0 = surface volume (Object.Volume or FrustumObject.Volume())
```
Exp variant `V0*exp(-P/K)` also plausible but tests use linear clamped model – use linear.

### Buoyant force, net force
```
Fb(z) = rho(z) * V(z) * g
Fw = Mass * g
Buoyant mass = rho(z)*V(z)
Net down force: Fnet(z,v) = Fw - Fb(z) - Fd(z,v)
Fd(z,v) = 0.5 * rho(z) * Cd * Ad(z) * v*|v|   opposes motion, sign trap: must use v*|v| not v²
Ad(z): reference area for drag – for simplicity use cross-sectional area at depth for drag: 
  Prismatic: Ad = A (constant) or V(z)/Height? Choose one consistently: use V(z)/Height for prismatic to account for compression, for conical/frustum use pi*r(z)² where r(z) from current compressed geometry? Simplest: Ad = A(z) as defined for stratified (pi r(z)²) – but must account for compression scaling of radius as (V(z)/V0)^(1/3) if isotropic? To keep testable, define Ad = cross-sectional area at depth z (same as A(z) for prismatic/conical/frustum) – i.e., Ad does NOT include compression scaling beyond what A(z) already includes, except for volume compression reducing A? For simplicity: Ad(z) = A(z) as derived for incompressible geometry, ignoring compression for drag area (or include if you want) – but document and be consistent. We will define Ad(z)=A(z) (prismatic constant, conical pi r(z)², frustum pi r(z)²). Tests will use same definition.
```
`Cd>=0`, `Cd==0` → no drag, but TerminalVelocity must error if Cd<=0 (contains "drag").

### Terminal velocity at fixed depth
Set `Fnet=0` ignoring acceleration: `Fw - Fb(z) - 0.5 rho Cd Ad v² * sign(v) =0`
```
v_term(z) = sign(Fw-Fb) * sqrt(2*|Fw-Fb|/(rho(z)*Cd*Ad(z)))
If |Fw-Fb|<1e-12 → 0, Cd<=0 → error containing "drag", Ad<=0 → error
```

### Equilibrium depth (compressible)
Fully submerged neutral depth where `Fw=Fb(z)` i.e. `M = rho(z)*V(z)`:
```
f(z)=M - rho(z)*V(z)=0
     =M - (S+Gz)*V0*(1 - P(z)/K)
With P(z)=g(Sz+0.5 Gz²) → cubic/quadratic in z with g/K coupling, no closed form → bisection 100 iter in [0,maxDepth]
```
Reductions:
- `K→∞` (incompressible): `f(z)=M-(S+Gz)V0` → stratified incompressible
- `G=0, K→∞`: `M-S V0` → uniform
Tests check reductions within 1e-6.

### Time-to-depth via RK4
Integrate ODE from rest `z=0,v=0`:
```
dz/dt = v
dv/dt = Fnet(z,v)/M
```
Use classic RK4 with step `dt`:
```
k1_z=v, k1_v=Fnet(z,v)/M
k2_z=v+0.5 dt k1_v, k2_v=Fnet(z+0.5 dt k1_z, v+0.5 dt k1_v)/M
k3_z=v+0.5 dt k2_v, k3_v=Fnet(z+0.5 dt k2_z, v+0.5 dt k2_v)/M
k4_z=v+dt k3_v, k4_v=Fnet(z+dt k3_z, v+dt k3_v)/M
z+=dt/6*(k1_z+2k2_z+2k3_z+k4_z)
v+=dt/6*(k1_v+2k2_v+2k3_v+k4_v)
t+=dt
Loop until z>=target, return interpolated time between last two steps (linear interpolation for time) – required for accuracy.
Validate: target>0,g>0,dt>0,maxTime>0,target<=CrushDepth else crush error, if never reaches within maxTime → error, if Fnet becomes upward (object floats) before target → unreachable error.

Pre-select case where Euler with same dt has >25% error vs RK4 reference dt/10, so tests enforce RK4 not Euler, tolerance ±15% vs reference dt/10 run.

### Concurrent batch
`BatchFindEquilibrium` and `BatchTimeToDepthConcurrent` must:
- Preserve input order via Index
- Invalid object → State="invalid" Fraction=0 Depth=0 etc, continue
- Fluid invalid → nil,error
- Empty/nil → non-nil empty slice
- Race-free `go test -race` must pass – use WaitGroup + mutex or channel, not shared slice without sync
- Crush handling: if target > CrushDepth → State="crush" or error marked? For batch, mark invalid? Spec: return result with State="crush" and 0 values? We define: if depth>CrushDepth, return result with State="crush" (not invalid) to distinguish. Tests will check State contains "crush".

## File Location
- `/app/buoyancy.go` MUST stay
- `/app/partial.go` contains uniform+stratified (existing)
- New file `/app/dive.go` (or extend partial.go, but keep manageable) package `buoyancy`, stdlib only
- Do NOT redefine Step1 symbols, but can add new types

## Types to Define

In `/app/partial.go` already:
```
SubmersionResult, FrustumObject, StratifiedFluid
```
Keep them.

In `/app/dive.go` (or partial.go) add:

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
```

If you keep in partial.go, ensure no duplicate. We will use separate file dive.go.

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

func BatchFindEquilibrium(objs []CompressibleObject, fluid StratifiedFluid, g, maxDepth, tol float64) ([]DiveResult, error)
func BatchTimeToDepthConcurrent(objs []CompressibleObject, fluid StratifiedFluid, targets []float64, g, dt, maxTime float64) ([]DiveResult, error)
```

All exact signatures.

## Detailed Behavior

**Validation:**
- CompressibleObject: Mass>0, Volume0>0, Height>0, BulkModulus>0, DragCoefficient>=0 (0 allowed but Terminal errors), CrushDepth>0, MinVolumeFraction>0 and <1 (0.1). Else error.
- StratifiedFluid: SurfaceDensity>0, Gradient>=0
- Depth: >=0 else error containing "depth", g<=0 error containing "gravity", dt<=0 error "dt", maxTime<=0 error "maxTime", target<=0 error "target", tol<=0 error "tol" but allow small
- DensityAtDepth negative z → error "depth"
- PressureAtDepth: P = g*(S*depth+0.5*G*depth²) → must derive 0.5 factor, error if fluid invalid, depth<0, g<=0
- VolumeAtDepth: V=V0*(1-P/K) clamped to MinVol = f_min*V0, if depth>CrushDepth → error contains "crush" (case-insensitive)
- BuoyantForceAtDepth: rho(z)*V(z)*g, error if fluid/obj invalid
- NetForceAtDepth: Fw - Fb - Fd, Fd=0.5*rho*Cd*Ad*v*|v|, Ad = cross-sectional area at depth (for compressible, use compressed? Simplify Ad = VolumeAtDepth/Height for prismatic reference – but for generic compressible object we don't have R1,R2, so define Ad = VolumeAtDepth/Height (prismatic reference). This keeps testable.)
- TerminalVelocity: sign(Fw-Fb)*sqrt(2*|Fw-Fb|/(rho*Cd*Ad)), Cd<=0→error "drag", |Fnet|<1e-12→0, Ad<=0→error
- FindEquilibriumDepth: bisection 100 iter in [0,maxDepth] solving M - rho(z)*V(z)=0, if no sign change (always positive → sink to maxDepth? Actually if M>rho*V at all depths up to maxDepth → sink, return maxDepth and state sink? But function returns depth only, error if no equilibrium? For simplicity: if mass > buoyant at maxDepth → return maxDepth with no error but caller can detect sink via comparison? Better: if no root, return maxDepth and no error if sink, but tests will check depth==maxDepth. For float case where buoyant > weight at surface (object floats), f(0)=M - S*V0 <0 → no root in [0,maxDepth] with f negative at 0 → should return 0? Actually floating object equilibrium depth for fully submerged is 0? But for fully submerged compressible, float means it wants to go up, so equilibrium at surface 0. We'll define: if f(0)<=0 → equilibrium 0 (floats at surface). If f(maxDepth)>=0? Actually if mass > buoyant even at maxDepth, it sinks to maxDepth. Else bisection finds root where f crosses 0. Need to handle sign.
- TimeToDepthRK4: integrate from 0,0, validate inputs, if target>CrushDepth → crush error, loop until z>=target or t>maxTime, return interpolated time. If Fnet becomes upward before target (object starts floating up) → unreachable error. If never reaches within maxTime → error.

**BatchFindEquilibrium:**
- Validate fluid, g>0, maxDepth>0, tol>0 else nil,error
- Empty/nil → non-nil empty slice
- For each obj index i:
  - If invalid → DiveResult{Index:i, State:"invalid"}
  - Else compute equilibrium depth via FindEquilibriumDepth, terminal velocity at that depth, volume at that depth, max pressure = PressureAtDepth at equilibrium, crush risk = depth>=CrushDepth*0.9?
  - Preserve order, race-free

**BatchTimeToDepthConcurrent:**
- Validate fluid, g>0, dt>0, maxTime>0, len(objs)==len(targets) else error
- For each i, launch goroutine with WaitGroup, compute TimeToDepthRK4 for target, store result at index i with mutex
- Invalid obj → State="invalid", preserve order
- Must pass `go test -race`

**Clamping:** Fraction [0,1], Depth [0,maxDepth or Height], Volume [MinVol, V0]

**No hardcoding:** Must derive P(z) integral with 0.5 factor, not `g*S*z` alone; must implement v*|v| sign handling not v²; must implement RK4 not Euler; must handle crush.

## Requirements

1. Reuse Step1 types/constants, do NOT redefine Object/Fluid/Tolerance/StandardGravity (AST check).
2. Files `/app/partial.go` and `/app/dive.go`, package `buoyancy`, `go vet` and `go test -race` must pass, stdlib only.
3. Structs exact fields as spec.
4. Uniform functions (12) + stratified (9) + compressible (8+2 batch) exact signatures must exist.
5. Error handling as described, crush error contains "crush", drag error contains "drag", depth error contains "depth", etc (case-insensitive checks).
6. Deterministic pure functions except concurrent batch order preserved.
7. No hardcoding lookup tables; must derive formulas.
8. Conical uniform must NOT be linear, frustum uniform must NOT be linear nor simple cbrt for R1!=R2.
9. Stratified must use integral buoyancy, not simple rho*V_sub.
10. Compressible must use pressure integral with 0.5 factor, volume clamped, crush handling, drag sign, RK4 not Euler.

## Grading Hidden Tests

- Old uniform: fraction, linear, cbrt vs linear, frustum cubic, batch, tolerance, vet, AST
- Stratified: validation, DensityAtDepth, prismatic quadratic, conical quartic, frustum quartic, reduction G=0→uniform, monotonicity, batch, vet
- Compressible:
  - PressureAtDepth: S=1000 G=2 g=9.81 depth10 → 99081 (with 0.5) vs naive 100062 without 0.5 → must catch 0.5
  - VolumeAtDepth: V0=1 K=1e8 S=1025 G=0.5 depth100 g=9.81 → P≈..., V≈V0*(1-P/K)
  - BuoyantForceAtDepth: rho*V*g
  - NetForceAtDepth: includes drag sign
  - TerminalVelocity: sign handling, Cd<=0 error
  - FindEquilibriumDepth: S=1025 G=0.5 V0=1 M=1026*1 (slightly heavy) → equilibrium depth via bisection solving cubic, not trivial; reduction K→∞ → stratified depth, G=0 K→∞ → uniform
  - TimeToDepthRK4: target 50m dt0.1, reference RK4 dt/10, tolerance ±15%, Euler same dt fails >25% → must use RK4
  - CrushDepth: target>CrushDepth → error contains "crush"
  - BatchFindEquilibrium and BatchTimeToDepthConcurrent: order, invalid, race-free (go test -race)
  - vet and race pass

## What NOT to Do

- Do NOT give explicit P(z) formula with 0.5 factor in solution comments? Comments allowed but tests check you derived
- Do NOT use v² instead of v*|v| for drag – sign will be wrong for upward motion
- Do NOT use Euler instead of RK4 – accuracy test will fail
- Do NOT ignore compression or gradient in reductions
- Do NOT hardcode depths per density/radius
