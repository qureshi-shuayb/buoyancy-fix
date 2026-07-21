# Step 3: Compressible Dynamics, Drag, and Time Integration

## Overview
Step 3 of 3, `inherit_prior_session=true`. Step1 `buoyancy.go` and Step2 `partial.go` preserved. Adds pressure integral, compression clamped to `MinimumVolumeFraction`, crush 90%, drag `Ad=V/Height`, terminal velocity, equilibrium bisection, RK4, concurrent batch.

## File Location
- `/app/buoyancy.go`, `/app/partial.go` must stay, `/app/dive.go` new, package `buoyancy`
- Go 1.23+, stdlib only: `math`, `fmt`, `errors`, `strings`, `sync`
- `go vet` and `go test -race` must pass. Do not redefine prior symbols.

## Constants and Types
```go
const MinimumVolumeFraction = 0.1
type CompressibleObject struct { Mass, Volume0, Height, BulkModulus, DragCoefficient, CrushDepth, MinVolumeFraction float64 }
type DiveResult struct { Index int; State string; EquilibriumDepth, TerminalVelocity, TimeToDepth, VolumeAtDepth, MaxPressure float64; CrushRisk bool }
```

## Validation Rules

- `CompressibleObject.Validate()`: Mass>0, Volume0>0, Height>0, BulkModulus>0, DragCoefficient>=0, CrushDepth>0, MinVolumeFraction in (0,1).
- `StratifiedFluid`: SurfaceDensity>0, Gradient>=0.
- Depth params: depth, targetDepth >=0; g, dt, maxTime, tol, maxDepth >0; Cd<=0 allowed for general but TerminalVelocity requires Cd>0.

## Functions
```go
func (c CompressibleObject) Validate() error
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

- `PressureAtDepth`: `P(z)=g*(S*z+0.5*G*z²)` from integral ∫rho(z')g dz'.
- `VolumeAtDepth`: `V(z)=V0*(1-P/K)` clamped to `Vmin=V0*MinFraction`, respects package `MinimumVolumeFraction` constant and object field, both lower-bounded. Error if depth>CrushDepth containing "crush". Must reference `MinimumVolumeFraction`.
- `BuoyantForceAtDepth`: `rho(z)*V(z)*g`.
- `NetForceAtDepth`: `Fw-Fb-Fd`, `Fd=0.5*rho*Cd*Ad*v*|v|`, `Ad=V(z)/Height`, drag opposes via `v*|v|`.
- `TerminalVelocityAtDepth`: solve `Fnet=0` for v, 0 when |Fw-Fb|<1e-12, sign matches Fw-Fb, error if Cd<=0 containing "drag".
- `FindEquilibriumDepth`: solve `Mass=rho(z)V(z)` via bisection [0,maxDepth] 100 iters with tol param.
- `TimeToDepthRK4`: integrate `dz/dt=v`, `dv/dt=Fnet/M` from rest via RK4 Butcher [0,0.5,0.5,1], clamp intermediate depths >=0, return interpolated time. Must be within ±15% of reference dt/10.
- Batch: validate fluid,g,maxDepth,tol,dt,maxTime,len match; if nil → `make(...,0),nil`; order via Index; invalid→State="invalid" continue; target>CrushDepth→State="crush" CrushRisk=true; depth>=0.9*CrushDepth→CrushRisk=true; concurrent with WaitGroup+Mutex race-free.

## Error Handling

Explicit mapping, error must contain keyword case-insensitive:
- depth/target invalid → contains "depth" or "target"
- gravity/g invalid → contains "gravity"
- density/S invalid → contains "density"
- mass invalid → contains "mass"
- volume invalid → contains "volume"
- crush depth exceeded → contains "crush"
- drag Cd invalid → contains "drag"
- dt invalid → contains "dt"
- maxTime invalid → contains "maxTime" or "time"
- tol invalid → contains "tol"
Return 0 and non-nil error.

## Overflow Handling

After any multiplication/division that can overflow, if intermediate or final result is Inf or NaN return error.
Example: `PressureAtDepth` with `S=1e200,G=1e200,depth=1e100,g=1e10` must error not return Inf.
Example: `VolumeAtDepth` with `BulkModulus=1e-9` causing `P/K` overflow must error.
Example: `CompressibleObject{Volume0=1e150,BulkModulus=1e150}.VolumeAtDepth` with large pressure must error if intermediate Inf.
Tiny values like `1e-9` must still succeed.

## General
- No external deps, no hardcoded tables, reuse prior types.
