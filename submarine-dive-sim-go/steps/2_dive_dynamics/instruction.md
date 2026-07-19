# Step 2: Submarine Dive Dynamics, Equilibrium, RK4 & Fleet

## Overview
This is **Step 2 of 2**. Builds on Step 1 with `inherit_prior_session=true`. File `/app/submarine.go` exists — inspect with `cat /app/submarine.go`. Do NOT redefine `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`.

Goal: dive dynamics including drag, terminal velocity, equilibrium depth via bisection, time-to-depth via RK4, and batch fleet.

## Physics with Explicit Formulas

Reuse Step1 helpers: `DensityAtDepth`, `PressureAtDepth`, `VolumeAtDepth`.

- **Density at depth:** `rho(z) = rho0 + grad*z` where grad=0.02, z>=0.
- **Pressure:** `P(z) = g * (rho0*z + 0.5*grad*z^2)`
- **Volume at depth:** `V(z) = V0 * (1 - k*P(z))` clamped to `0.1*V0`, k=HullCompressibility. If z>CrushDepth error "crush". If k=0, V=V0.
- **Effective mass:** `m = DryMass + BallastLevel`
- **Cross-section area:** `A = V(z) / Length` (or V0/Length at surface)
- **Buoyant force at depth:** `Fb(z) = rho(z)*V(z)*g` upward
- **Weight:** `Fw = m*g` downward
- **Quadratic drag (upward positive):** `Fnet(z,v) = Fb(z) - Fw - 0.5*rho(z)*Cd*A*v*|v|` where Cd=DragCoefficient, v up-positive. When v=0 drag 0. If Cd=0 drag 0.
- **Terminal velocity:** Solve Fnet=0: `0.5*rho*Cd*A*v*|v| = Fb-Fw` => `|v| = sqrt(2*|Fb-Fw|/(rho*Cd*A))`, signed `v_term = sign(Fb-Fw)*sqrt(...)`. If Fb=Fw => 0. If Cd<=0 error "drag".
- **Equilibrium depth (zero velocity):** Find z in [0,maxDepth] where `Fb(z)-Fw=0`. No closed form because P(z) quadratic. Use bisection:
  ```
  lo=0, hi=maxDepth
  if |f(lo)| small => return lo
  if f(lo)*f(hi)>0 => no root error
  for 100 iterations:
    mid=(lo+hi)/2
    if |f(mid)|<1e-9 or hi-lo < tol => return mid
    if f(lo)*f(mid)<=0 => hi=mid else lo=mid
  return (lo+hi)/2
  ```
  Validate g>0,maxDepth>0,tol>0, maxDepth<=CrushDepth else error "crush".
- **Time to depth via RK4:** Integrate from rest z=0,v=0 to targetDepth>0. Recommend down-positive for integration for simplicity: `z` down positive, `v` down positive, `Fnet_down = Fw - Fb - 0.5*rho*Cd*A*v*|v|`, `dz/dt=v`, `dv/dt=Fnet_down/m`. Start (0,0), step dt, maxTime cutoff. Return time when z>=target (interpolate). If target>CrushDepth error crush. If never reaches within maxTime error. Validate target>0,g>0,dt>0,maxTime>0.
  RK4 per step:
  ```
  k1_z=v, k1_v=Fnet(z,v)/m
  k2_z=v+0.5dt*k1_v, k2_v=Fnet(z+0.5dt*k1_z, v+0.5dt*k1_v)/m
  k3_z=v+0.5dt*k2_v, k3_v=Fnet(z+0.5dt*k2_z, v+0.5dt*k2_v)/m
  k4_z=v+dt*k3_v, k4_v=Fnet(z+dt*k3_z, v+dt*k3_v)/m
  z+=dt/6*(k1_z+2k2_z+2k3_z+k4_z)
  v+=dt/6*(k1_v+2k2_v+2k3_v+k4_v)
  ```
  Euler will fail accuracy test which requires within 12% of small-dt reference (middle ground).
- **Batch fleet:** For each sub preserve order, if invalid (Validate fails) => State="invalid" Index=i. Else AnalyzeDive. If fluid invalid => nil,error. Empty => empty. To hit sweet spot difficulty, you should use at least one goroutine for fleet processing (e.g., launch goroutine per sub with WaitGroup, preserve order via indexed results). Full worker-pool with semaphore is optional bonus but at least one `go` usage is required (checked). Must be race-safe.

## File Location
- /app/submarine.go exists
- New file /app/dive.go package submarine stdlib only, both go vet and race pass.

## Types

```go
type DiveResult struct {
    Index int
    State string
    StateAtDepth string
    Fraction float64
    RequiredBallast float64
    RequiredBallastAtDepth float64
    IsPossible bool
    IsPossibleAtDepth bool
    EffectiveDensity float64
    EffectiveDensityAtDepth float64
    NetForce float64
    NetForceAtDepth float64
    Acceleration float64
    EquilibriumDepth float64
    TerminalVelocity float64
    TimeToDepth float64
    MaxPressure float64
    VolumeAtDepth float64
    CrushRisk bool
}
```

## Functions

```go
func SubmergedFraction(sub Submarine, fluid Seawater) (float64,error)
func NetVerticalForce(sub Submarine, fluid Seawater, g float64) (float64,error)
func VerticalAcceleration(sub Submarine, fluid Seawater, g float64) (float64,error)
func AnalyzeDive(sub Submarine, fluid Seawater) (DiveResult,error)
func BatchAnalyzeFleet(subs []Submarine, fluid Seawater) ([]DiveResult,error)

func NetVerticalForceAtDepth(sub Submarine, fluid Seawater, depth float64, velocity float64, g float64) (float64,error)
func TerminalVelocity(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func FindEquilibriumDepth(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) (float64,error)
func TimeToDepth(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) (float64,error)
func BatchAnalyzeFleetWithTargets(subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult,error)
```

Details:

- **SubmergedFraction**: effDensity/fluid.Density clamped [0,1], validate.
- **NetVerticalForce**: Fb-Fw surface up positive.
- **VerticalAcceleration**: Fnet/EffectiveMass.
- **NetVerticalForceAtDepth**: Fb(z)-Fw -0.5*rho*Cd*A*v|v| up positive, validate depth>=0,g>0,crush.
- **TerminalVelocity**: as formula, Cd>0 else error drag, signed.
- **FindEquilibriumDepth**: bisection as above, validate, if maxDepth>CrushDepth error crush, if f(lo)*f(hi)>0 error no equilibrium (any message), else bisection.
- **TimeToDepth**: RK4 as above, validate, crush, unreachable error, not reached within maxTime error.
- **AnalyzeDive**: Validate, surface calcs via reuse, ref depth 100m (or 0.9*CrushDepth), equilibrium up to min(CrushDepth,2000) tol 1e-3, if error set -1, terminal at 0, time to 100m dt 0.1 max 10000 set 0 if error, MaxPressure at eq or 100m, CrushRisk if 100>CrushDepth.
- **BatchAnalyzeFleet**: fluid valid else nil,error, empty => empty, for each i if invalid => invalid, else AnalyzeDive Index=i, order preserved. Sequential ok.
- **BatchAnalyzeFleetWithTargets**: fluid valid,g>0,len match else error, empty => empty, for each i if invalid or target<0 => invalid, if target>CrushDepth => CrushRisk true, else AnalyzeDive + TimeToDepth to its target. Preserve order.

## Requirements
1. Reuse types/constants.
2. File /app/dive.go package submarine, vet and race pass.
3. Struct at least required fields.
4. Functions exact signatures.
5. Stdlib only.
6. No hardcode.

## Grading
- SubmergedFraction clamped
- NetVerticalForce surface and at depth with drag sign
- TerminalVelocity sqrt sign inverse check (tol 0.3 middle)
- FindEquilibriumDepth vs brute-force within 2.0m middle, crush, tolerance
- TimeToDepth RK4 within 12% vs small dt middle, crush, unreachable
- AnalyzeDive fields
- BatchFleet order invalid fluid empty + at least one goroutine required

## What NOT to Do
- Do not redefine types
- Do not hardcode
- Do not drop invalid
- Do not modify submarine.go
