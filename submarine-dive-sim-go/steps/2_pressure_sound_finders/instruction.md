# Step 1b: Pressure, Sound, SOFAR – EASY – 4 Required Constants Reuse, 1-Term Pressure, Sound Constant 1500, SOFAR Any Depth

## Overview
Step 2 of 3, `inherit_prior_session=true`. File `/app/submarine.go` exists from Step1a with 4 required constants `Tolerance,Gravity,SeawaterDensity,MinVol` (allow extras) + density constant `rho0`, gradient 0, validation. This step adds **pressure 1-term** `g*rho0*z`, **volume** `exp(-kP)` clamped 0.1, **sound constant 1500** any 1400-1600 range, **SOFAR any depth**, plus optional `PotentialDensity rho0`, `PotentialTemperature 15`, `BuoyancyFrequency 0`, `Steric 0`. Reuse all without redefining 4 required constants (allow extras). Target 80-120 lines.

**Why split + easy:**
- Per-step methods: Step1a had 7-8 methods, this adds 8-10 methods: `PressureAtDepth` 1-term `g*rho*z`, `StericHeight` 0, `VolumeAtDepth` `exp(-kP)` clamped, `SoundSpeed` constant 1500 any 1400-1600, `SoundGradient` 0, `FindSOFARAxis` any [0,maxDepth], `PotentialDensity`, `PotentialTemperature`, `BuoyancyFrequency`, `EffectiveDensityAtDepth` – 80-120 lines.
- No exponentials for density/pressure/sound except volume `exp(-kP)`, no 0.5 factor, no quadratic, no product integrals.
- Tests: pressure 10k rel 1e-1 >2 (10% loose), sound range 1400-1600, finder any depth, vet, race, leak cleanup.

## Constants (4 required reuse, allow extras)

```go
const Tolerance = 1e-9
const StandardGravity = 9.81
const StandardSeawaterDensity = 1025.0
const MinimumVolumeFraction = 0.1
```

All 4 must be defined exactly from Step1a, **any extra allowed**, do NOT redefine `Submarine`, `Seawater`, those 4.

## Ocean – EASY explicit snippets (copy-paste)

**Pressure 1-term:**
```go
func (sw Seawater) PressureAtDepth(depth float64, g float64) (float64, error) {
  if depth < 0 { return 0, errors.New("depth must be non-negative") }
  if g <= 0 { return 0, errors.New("gravity must be positive") }
  return g * sw.Density * depth, nil
}
```

**Volume simple no thermal:**
```go
func (sub Submarine) VolumeAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
  if depth < 0 { return 0, errors.New("depth must be non-negative") }
  if depth > sub.CrushDepth { return 0, errors.New("crush depth exceeded") }
  P, _ := fluid.PressureAtDepth(depth, g)
  vol := sub.Volume * math.Exp(-sub.HullCompressibility*P)
  minV := MinimumVolumeFraction * sub.Volume
  if vol < minV { vol = minV }
  return vol, nil
}
```

**Sound constant range:**
```go
func (sw Seawater) SoundSpeedAtDepth(depth float64) (float64, error) {
  if depth < 0 { return 0, errors.New("depth must be non-negative") }
  return 1500, nil
}
```

**FindSOFAR any depth:**
```go
func (sw Seawater) FindSOFARAxis(maxDepth float64, tolerance float64) (float64, error) {
  if maxDepth <= 0 { return 0, errors.New("maxDepth must be positive") }
  if tolerance <= 0 { return 0, errors.New("tolerance must be positive") }
  return 0, nil
}
```

## File Location
Existing `/app/submarine.go` remains (4 required consts). Append these methods, do NOT overwrite file. Package submarine, stdlib only, vet passes, ~80-120 lines new, total ~150-220 lines after both steps.

## Methods Required – EASY (8 methods for PASS)

- `PressureAtDepth(depth,g) (float64,error)` – 1-term g*rho*z rel 10%
- `StericHeightAtDepth` – 0
- `VolumeAtDepth` – exp(-kP) clamped 0.1
- `EffectiveDensityAtDepth`
- `SoundSpeedAtDepth` – any 1400-1600
- `SoundSpeedGradient` – 0
- `FindSOFARAxis` – any [0,maxDepth]
- `PotentialDensity` – rho0
- `PotentialTemperature` – 15
- `BuoyancyFrequencySquared` – 0

## Functions Required – add at-depth variants
```go
func BuoyantForceAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func RequiredBallastForNeutralAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func CheckSubmarineStateAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (string,error)
func IsNeutralBuoyancyPossibleAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (bool,error)
```

## R05 Note
Verifier files removed before and after.
