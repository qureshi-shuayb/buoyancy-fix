# Step 1a: Ocean Constants and Density – TRIVIAL – 4 Required Constants, Allow Extras, Constant Density

## Overview
Step 1 of 3. **TRIVIAL** targeting **10-30% fail (70-90% pass)**. Previous 683b3c3 (8 consts 2-term linear + quadratic sound) still gave 0/10 for all models. This split makes Step1a only **4 required constants** `Tolerance 1e-9, StandardGravity 9.81, StandardSeawaterDensity 1025, MinimumVolumeFraction 0.1` (allow any extra per R08), **density constant rho0**, **gradient 0**, salinity 35 constant, temperature 15 constant, validation. No pressure, no sound, no finders. Target 60-100 lines.

**Why trivial + split helps 60% easier:**
- Per-step methods: from 12 methods in one file → 7-8 methods in Step1a: `SalinityAtDepth` 35, `TemperatureAtDepth` 15, `DensityAtDepth` constant `rho0=fluid.Density`, `DensityGradient` 0, `Validate`, `EffectiveMass`, `EffectiveDensity` – 60-100 lines.
- Constants: only 4 required exact, **allow any extras** – removes NOT-contain false negatives that rejected 24-const impls.
- Density constant: `rho(z)=rho0`, gradient 0, `math.Exp` not needed, explicit snippet provided.
- Tests: constants 4 exact, density constant within 10%, gradient 0 tol 1e-2, vet, race, leak cleanup rm before+after.

## Constants (4 required, allow extras)

```go
const Tolerance = 1e-9
const StandardGravity = 9.81
const StandardSeawaterDensity = 1025.0
const MinimumVolumeFraction = 0.1
```

All 4 must be defined exactly, but **any extra constants allowed** (no NOT-contain) per R08.

**Allowed extras:** `BulkModulus 2.2e9, DepthDensityGradient 0.02, PycnoclineDelta 10/Scale 200, HaloclineDelta, HaloclineScale, ThermoclineScale, SalinityDensityCoeff, etc.` – models may include and still pass.

## Ocean – TRIVIAL (provided snippets)

**Salinity constant:**
```go
func (sw Seawater) SalinityAtDepth(depth float64) (float64, error) {
  if depth < 0 { return 0, errors.New("depth must be non-negative") }
  return 35.0, nil
}
```

**Temperature constant:**
```go
func (sw Seawater) TemperatureAtDepth(depth float64) (float64, error) {
  if depth < 0 { return 0, errors.New("depth must be non-negative") }
  return 15.0, nil
}
```

**Density constant:**
```go
func (sw Seawater) DensityAtDepth(depth float64) (float64, error) {
  if depth < 0 { return 0, errors.New("depth must be non-negative") }
  return sw.Density, nil
}
```

**Gradient constant 0:**
```go
func (sw Seawater) DensityGradientAtDepth(depth float64) (float64, error) {
  if depth < 0 { return 0, errors.New("depth must be non-negative") }
  return 0, nil
}
```

## File Location
`/app/submarine.go`, package submarine, Go 1.23+, stdlib only, vet passes, ~60-100 lines.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required – TRIVIAL (7 methods for PASS)

- `SalinityAtDepth(depth) (float64,error)` – 35 constant
- `TemperatureAtDepth(depth) (float64,error)` – 15 constant
- `DensityAtDepth(depth) (float64,error)` – constant rho0
- `DensityGradientAtDepth(depth) (float64,error)` – 0 constant tol 1e-2
- `(Submarine) Validate() error`, `(Seawater) Validate() error`, `EffectiveMass() float64`, `EffectiveDensity() (float64,error)`

Optional: `PotentialDensity`, `PotentialTemperature`, etc.

## Functions Required
```go
func BuoyantForce(fluid Seawater, sub Submarine, g float64) (float64,error)
func WeightForce(sub Submarine, g float64) (float64,error)
func RequiredBallastForNeutral(sub Submarine, fluid Seawater) (float64,error)
func CheckSubmarineState(sub Submarine, fluid Seawater) (string,error)
func IsNeutralBuoyancyPossible(sub Submarine, fluid Seawater) (bool,error)
```

State via Tolerance: |eff-fluid|<=Tol neutral, eff<fluid float else sink.

## R05 Note
Verifier files removed before and after.
