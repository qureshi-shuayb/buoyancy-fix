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

- `CompressibleObject.Validate()`: Mass>0, Volume0>0, Height>0, BulkModulus>0, DragCoefficient>=0, CrushDepth>0, MinVolumeFraction in (0,1), all finite (reject NaN/Inf).
- `StratifiedFluid`: SurfaceDensity>0 finite, Gradient>=0 finite.
- Depth params: depth, targetDepth >=0 finite; g, dt, maxTime, tol, maxDepth >0 finite; Cd<=0 allowed for general but TerminalVelocity requires Cd>0 finite. All numeric inputs must be finite.
- `PressureAtDepth`, `VolumeAtDepth`, `BuoyantForceAtDepth`, `NetForceAtDepth`, `TerminalVelocityAtDepth` must error on overflow to Inf/NaN.
- `BatchFindEquilibrium` must be concurrent with WaitGroup+Mutex like `BatchTimeToDepthConcurrent`, with Index ordering preserved.

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

- `PressureAtDepth`: hydrostatic pressure from integrating `rho(z')*g` from 0 to depth, where `rho(z)=S+G*z` stratified. Must handle overflow chain stepwise.
- `VolumeAtDepth`: compressible volume from pressure and bulk modulus `K`, clamped to minimum fraction. Must respect both object field `MinVolumeFraction` and package constant `MinimumVolumeFraction`, lower-bounded by their max. Error if depth exceeds CrushDepth.
- `BuoyantForceAtDepth`: buoyant force using density at depth and volume at depth.
- `NetForceAtDepth`: net force `weight - buoyant - drag` with quadratic drag using reference area derived from volume at depth and height, drag opposes motion via signed velocity.
- `TerminalVelocityAtDepth`: terminal velocity solving net force zero, handling zero net case and sign, with drag validation.
- `FindEquilibriumDepth`: equilibrium where mass equals buoyant mass `rho(z)*V(z)` via bisection with tolerance, handling edge cases for surface and max depth and crush clamping when maxDepth exceeds CrushDepth.
- `TimeToDepthRK4`: time to reach target depth integrating `dz/dt=v`, `dv/dt=Fnet/M` from rest via RK4, with depth clamping and interpolated crossing time.
- Batch: validates inputs, nil handling, Index ordering, invalid and crush states, CrushRisk near crush depth, and concurrent implementation.

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
