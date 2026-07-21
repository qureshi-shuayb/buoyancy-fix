# Step 3: Compressible Dynamics, Drag, and Time Integration

## Overview
Step 3 of 3, `inherit_prior_session=true`. Your Step1 `/app/buoyancy.go` and Step2 `/app/partial.go` are preserved. This step adds hydrostatic pressure integral, bulk-modulus compression clamped to `MinimumVolumeFraction`, crush handling, quadratic drag with reference area `Ad=V/Height`, terminal velocity, equilibrium depth via bisection, time-to-depth via RK4, and concurrent batch.

## File Location
- `/app/buoyancy.go` and `/app/partial.go` must stay
- New file: `/app/dive.go`, package `buoyancy`
- Go 1.23+, stdlib only: `math`, `fmt`, `errors`, `strings`, `sync`
- Must compile `GO111MODULE=off go test`, `go vet` and `go test -race` pass. Do not redefine prior symbols.

## Constants and Types
```go
const MinimumVolumeFraction = 0.1

type CompressibleObject struct {
    Mass              float64
    Volume0           float64
    Height            float64
    BulkModulus       float64
    DragCoefficient   float64
    CrushDepth        float64
    MinVolumeFraction float64
}
type DiveResult struct {
    Index            int
    State            string
    EquilibriumDepth float64
    TerminalVelocity float64
    TimeToDepth      float64
    VolumeAtDepth    float64
    MaxPressure      float64
    CrushRisk        bool
}
```
Methods:
```go
func (c CompressibleObject) Validate() error
```

## Functions
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

## Behavior
- `Validate()`: Mass>0, Volume0>0, Height>0, BulkModulus>0, DragCoefficient>=0, CrushDepth>0, MinVolumeFraction in (0,1).
- `PressureAtDepth`: `P(z)=∫_0^z rho(z')*g dz' = g*(S*z+0.5*G*z²)` where `rho(z')=S+G*z'`. Validate fluid, depth>=0, g>0.
- `VolumeAtDepth`: `V(z)=V0*(1-P(z)/K)` where K=BulkModulus, P from PressureAtDepth, clamped to `Vmin=V0*MinVolumeFraction`, also respect object `MinVolumeFraction` field but not below package `MinimumVolumeFraction`. If depth>CrushDepth, error containing "crush". Must reference `MinimumVolumeFraction` constant.
- `BuoyantForceAtDepth`: `rho(z)*V(z)*g` where rho from `DensityAtDepth`, V from `VolumeAtDepth`.
- `NetForceAtDepth`: `Fw-Fb-Fd`, `Fw=Mass*g`, `Fb` as above, `Fd=0.5*rho*Cd*Ad*v*|v|` where `Ad=V(z)/Height` (bespoke reference area), drag opposes velocity via `v*|v|`.
- `TerminalVelocityAtDepth`: solve `Fnet=0` for v, `0` when |Fw-Fb|<1e-12, sign matches Fw-Fb, error if Cd<=0 containing "drag" or Ad<=0.
- `FindEquilibriumDepth`: solve `Mass = rho(z)*V(z)` via bisection [0,maxDepth] 100 iterations with tol param. If `f(0)<=0` return 0, if `f(maxDepth)>0` return maxDepth. Clamp maxDepth to CrushDepth.
- `TimeToDepthRK4`: integrate `dz/dt=v`, `dv/dt=Fnet/M` from rest z=0,v=0 using RK4 with Butcher [0,0.5,0.5,1], k1..k4 weighted `dt/6*(k1+2k2+2k3+k4)`. Clamp intermediate depths `z+0.5*dt*k1z` etc to >=0. Return interpolated time `t_prev+frac*dt` where `frac=(target-z_prev)/(z-z_prev)` when z>=target. Validate target>0, g>0, dt>0, maxTime>0, target<=CrushDepth else error containing respective keyword. If not reached within maxTime, error. Must be within ±15% of reference run with dt/10.
- `BatchFindEquilibrium`: validate fluid, g>0, maxDepth>0, tol>0 else nil,error. If nil input return `make([]DiveResult,0), nil`. Preserve order via Index. Invalid object → State="invalid" continue. Depth>=0.9*CrushDepth → CrushRisk=true, State may be "crush".
- `BatchTimeToDepthConcurrent`: validate fluid, g, dt, maxTime, len(objs)==len(targets) else error. Handle nil as non-nil empty or length mismatch error. Concurrent with `sync.WaitGroup` and `sync.Mutex`, preserve order via Index, race-free. Invalid object → State="invalid", target>CrushDepth → State="crush" CrushRisk=true.

## Error Handling
All invalid inputs return 0 and error containing keyword: depth, gravity, density, mass, volume, crush, drag, target, dt, maxTime, tol as appropriate. Depth params must be >=0, g>0, Cd>=0 except Terminal requires >0.

## General
- No external deps, no hardcoded tables. Reuse prior types.
