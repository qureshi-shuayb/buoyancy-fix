# Step 2: Moderate Dive Dynamics - Simple Re Table Drag, Fixed RK4 & Fleet

## Overview
Step 2 of 2, `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 — you MUST reuse its types, constants, methods without redefining them. Inspect with `cat /app/submarine.go`. It contains ultra-hard triple pycnocline + halocline + thermocline + cabbeling cross-coupling `Cc*(S-35)*(15-T)` with mixed scale 24m, sound speed with quadratic pressure term and gradient + SOFAR axis finder, potential density with cabbeling, potential temperature second-order `T*(1 -P/K*1e-3 -ThermobaricCoeff*(P/K*1e-3)^2)`, second derivative with product rule, spiciness, steric height, double-diffusive regime, hydrostatic pressure analytic including mixed scale, volume with quadratic thermal term.

Goal: dive dynamics with simple Re table drag, terminal bisection, multi-root equilibrium scanning, fixed RK4 time-to-depth, bounded fleet worker-pool.

**You must NOT redefine:** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `PycnoclineDelta`, `PycnoclineScale`, `DeepPycnoclineDelta`, `DeepPycnoclineScale`, `MidPycnoclineDelta`, `MidPycnoclineScale`, `HaloclineDelta`, `HaloclineScale`, `ThermoclineScale`, `HullThermalExpansionCoeff`, `SeawaterViscosity`, `SalinityDensityCoeff`, `BulkModulus`, `CabbelingCoeff`, `HullThermalExpansionQuadCoeff`, `SoundSpeedPressureQuadCoeff`, `ThermobaricCoeff`.

Additional available methods from Step1 (you should reuse, not reimplement): `CabbelingParameterAtDepth`, `SpicinessAtDepth`, `SoundSpeedGradientAtDepth`, `FindSOFARAxis`, `StericHeightAtDepth`, `DoubleDiffusiveRegimeAtDepth`, plus all previous depth methods.

## Ocean & Hull Recap (Reuse Step1)
- S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale))
- T(z)=15-12*(1-exp(-z/ThermoclineScale)), tAnom=15-T=12*(1-exp(-z/Ts)), sAnom=HaloclineDelta*(1-exp(-z/Hs))
- rho(z)=rho0+grad*z+D1(1-exp(-z/S1))+D2(1-exp(-z/S2))+D3(1-exp(-z/S3))+beta*sAnom+0.15*tAnom + CabbelingCoeff*sAnom*tAnom, where sAnom*tAnom expands with mixed scale Smix=Hs*Ts/(Hs+Ts)=24m via term exp(-z*(1/Hs+1/Ts)). 5+1 mixed distinct scales, beta=0.8, gamma=0.15, Cc=0.06
- Gradient with product rule: drho/dz = grad+ Σ Di/Si*exp +beta*dS/dz+gamma*dtAnom/dz +Cc*(dS*tAnom+sAnom*dtAnom), second derivative with second product rule
- Cabbeling parameter `cab=Cc*sAnom*tAnom`, Spiciness `spice=beta*(S-35)+0.15*(T-15)` zero at surface
- Sound speed `c=1449.2+4.6T-0.055T²+1.34(S-35)+0.016z+SoundSpeedPressureQuadCoeff*z^2` with gradient `dc/dz=4.6*dT/dz-0.11*T*dT/dz+1.34*dS/dz+0.016+2*quad*z`, SOFAR axis via scanning 1000+ bisection
- Potential density without grad*z but includes cabbeling, steric height `(P/g -rho0*z)/rho0` analytic includes mixed
- Potential temperature `theta=T*(1 -P/Bulk*1e-3 -ThermobaricCoeff*(P/K*1e-3)^2)` second-order tiny but required uses BulkModulus twice
- N²=g/rho*drho/dz, Turner `atan2(gamma*dT+beta*dS, beta*dS - gamma*dT)*180/pi`, DoubleDiffusiveRegime classification of Turner angle
- Pressure analytic quadratic+5 exps+mixed Smix term: integral of sAnom*tAnom yields `HD*12*[z+Hs*(expH-1)+Ts*(expT-1)+Smix*(1-exp_mix)]`
- Volume `V0*exp(-kP)*(1+alpha*(T-15)+alpha2*(T-15)^2)` with alpha2=HullThermalExpansionQuadCoeff=1.2e-6, clamped 0.1*V0

## New Physics

**Effective mass:** `m=DryMass+BallastLevel`. Area `A(z)=V(z)/Length`.

**Simple Re table drag:**
`mu=SeawaterViscosity=0.001`, `Re=rho(z)*|v|*Length/mu`
```
Cd(Re)=1.2 if Re<1e5 else 0.5 if Re<5e5 else 0.2
```
For Re->0 use 1.2. Drag `0.5*rho*Cd*A*v*|v|`. Up-positive: `Fnet=Fb-Fw-drag`, v up. At depth with velocity v, same. For TimeToDepth down-positive: `Fnet_down=Fw-Fb-0.5*rho*Cd*A*v*|v|`, v down.

**Terminal velocity (implicit bisection):**
Find v where `Fnet=0`. Equation `|Fb-Fw|=0.5*rho*Cd(Re(v))*A*v²` no closed form, drag vs v monotonic, bisection after upper bound doubling works.
- If |Fb-Fw|<=1e-12 => 0
- If DragCoefficient field <=0 => error "drag"
- Find hi doubling from 1 m/s until drag(hi)>=|delta| or hi 1e4, bisect magnitude up to 100 iter until |drag-|delta||<1e-6 or interval<1e-6. Signed `sign(Fb-Fw)*v_mag` positive up.
- Validate depth>=0,g>0,depth<=CrushDepth else "crush".

**Equilibrium depth (multi-root scanning + bisection):**
Zero-velocity net `f(z)=Fb(z)-Fw`. Due to rho inc but V dec exponential, product rho*V hump gives 0-2 roots. Naive bisection fails when both ends same sign but interior root exists, must scan.

Structured parameters:

| Parameter | Value | Notes |
|-----------|-------|-------|
| scan points | >=1000 equally spaced in [0,maxDepth] | bracket search |
| tolerance arg | e.g. 1e-3 | bisection width target |
| bisection max iter | 100 | for each bracket |
| dedup threshold | tolerance*10 | merge close roots |
| f tolerance | 1e-9 | |f(mid)|<1e-9 stops |
| maxDepth validation | >0 and <=CrushDepth else "crush" | |

Procedure:
- Validate g>0,maxDepth>0,tolerance>0 else error. If maxDepth>CrushDepth => "crush"
- If |f(0)|<=Tolerance return 0
- Scan 0..maxDepth with 1000 steps, compute f. For each consecutive pair, if `f_i*f_{i+1}<=0` or |f_i|<Tol, bisection bracket. Bisection up to 100 iter.
- Collect, sort ascending, deduplicate within tolerance*10.
- FindEquilibriumDepth returns shallowest, FindEquilibriumDepths all sorted, error if none.
- FindEquilibriumDepthsWithStability same depths with Stable field: stable if f(z+0.5)>0 or via central diff derivative>0. Tests check sorted depth and Stable present, not strict sign.

**TimeToDepth via fixed RK4 (easier):**

Structured parameters:

| Parameter | Value | Notes |
|-----------|-------|-------|
| dt | passed argument, tests use 0.1 vs ref 0.01 | fixed step RK4 |
| maxTime | passed argument | fail if not reached |
| maxSteps implicit | maxTime/dt up to 100000 | safety |
| accuracy target | 5% rel vs dt/10 reference | Euler fails >15% |
| ODEs | dz/dt=v, dv/dt=Fnet_down/m, m=EffectiveMass (no added mass) | down-positive |

Start (0,0) at rest, step dt using classic RK4 `k1_z=v, k1_v=F/m, k2_z=v+0.5dt*k1_v ...`, `z+=dt/6*(k1+2k2+2k3+k4)`. Interpolate linearly when crossing target. Return interpolated time.
- Validate targetDepth>0,g>0,dt>0,maxTime>0 else error
- If target>CrushDepth => "crush"
- If during integration z>CrushDepth => "crush"
- If not reached within maxTime => error "not reached" / "time" / "unreachable"

**Fleet batch bounded worker-pool:**

| Parameter | Value |
|-----------|-------|
| pool semaphore | 4 via `make(chan struct{},4)` |
| order preservation | indexed results, final slice sorted by Index |
| invalid sub handling | DiveResult{Index:i,State:"invalid"} |
| empty input | return empty slice |
| mismatched lengths | error containing "length" or "mismatch" |
| context | BatchAnalyzeFleetWithContext must check ctx.Err() before start, return ctx.Err() on immediate cancel, import context |

- BatchAnalyzeFleet: fluid valid else error, subs nil/empty empty, uses `go`, `sync.WaitGroup`, `chan`, semaphore 4, race-safe.
- BatchAnalyzeFleetWithTargets: validates fluid,g>0,len equal else error, per-i target<0 => invalid, target>CrushDepth => CrushRisk true State "invalid", else AnalyzeDive + TimeToDepth for TimeToDepth field.
- BatchAnalyzeFleetWithContext: same as WithTargets plus ctx. Pre-check `ctx.Err()`, if cancelled return nil,ctx.Err(). Must contain `context` import, `go`, `WaitGroup`, `chan`, `make(chan struct{},4)`. Tests check immediate cancel returns error containing "context" or "cancel", background works order preserved.

## File Location
- Existing `/app/submarine.go` must remain.
- New `/app/dive.go`, package submarine, stdlib only (math,errors,sync,context). go vet and race must pass.

## Types
```go
type DiveResult struct {
    Index int; State string; StateAtDepth string; Fraction float64
    RequiredBallast float64; RequiredBallastAtDepth float64
    IsPossible bool; IsPossibleAtDepth bool
    EffectiveDensity float64; EffectiveDensityAtDepth float64
    NetForce float64; NetForceAtDepth float64; Acceleration float64
    EquilibriumDepth float64; TerminalVelocity float64; TimeToDepth float64
    MaxPressure float64; VolumeAtDepth float64; CrushRisk bool
}
type EquilibriumPoint struct { Depth float64; Stable bool; FPrime float64 }
```

## Functions Required (exact signatures)
```go
func SubmergedFraction(sub Submarine, fluid Seawater) (float64,error)
func NetVerticalForce(sub Submarine, fluid Seawater, g float64) (float64,error)
func VerticalAcceleration(sub Submarine, fluid Seawater, g float64) (float64,error)
func AnalyzeDive(sub Submarine, fluid Seawater) (DiveResult,error)
func BatchAnalyzeFleet(subs []Submarine, fluid Seawater) ([]DiveResult,error)
func NetVerticalForceAtDepth(sub Submarine, fluid Seawater, depth float64, velocity float64, g float64) (float64,error)
func CdFromRe(re float64) float64
func TerminalVelocity(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func FindEquilibriumDepth(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) (float64,error)
func FindEquilibriumDepths(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]float64,error)
func FindEquilibriumDepthsWithStability(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]EquilibriumPoint,error)
func TimeToDepth(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) (float64,error)
func BatchAnalyzeFleetWithTargets(subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult,error)
func BatchAnalyzeFleetWithContext(ctx context.Context, subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult,error)
```

## Requirements
1. Reuse types/constants from submarine.go, do NOT redefine Submarine,Seawater,Tolerance etc (AST check dive.go must NOT contain "type Submarine struct")
2. File /app/dive.go package submarine, go vet and race pass
3. Structs required fields present, functions exact signatures
4. Stdlib only, no hardcoding, compute via physics helpers
5. Concurrency: bounded pool 4 with `make(chan struct{},4)`, WaitGroup, chan, go, context import. Behavioral test: 20 subs order preserved, race -count=1
6. RK4: must contain k1..k4, accuracy 5% vs dt/10 (Euler fails)
7. Terminal: bisection with CdFromRe, simple sqrt constant Cd fails at Re thresholds
8. Equilibrium: scanning + bisection required, naive f(lo)*f(hi) fails multi-root hump
9. CdFromRe table 1.2/0.5/0.2

## Grading Hidden
- SubmergedFraction clamped
- NetForce surface/at depth Re table, zero-v = Fb-Fw
- CdFromRe bands 1.1-1.3 low,0.4-0.6 mid,0.15-0.3 high monotonic non-inc
- Terminal inverse tol 0.1 signed error drag Re threshold
- Equilibrium surface 0, heavy error, brute 0.5m, multi-root hump f(lo)*f(hi)>0 but root inside
- TimeToDepth heavy reaches 5% vs ref dt/10, light fails, crush error
- BatchFleet order 20 invalid empty mismatched lengths sem 4 race
- BatchWithContext immediate cancel context error background order
