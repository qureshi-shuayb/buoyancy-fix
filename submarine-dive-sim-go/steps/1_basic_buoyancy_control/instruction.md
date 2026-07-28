# Step 1: Stratified Ocean – VERY EASY – 6 Constants, 2-Term Linear Density, 2-Term Pressure, Gradient Constant, Sound Quadratic

## Overview
Step 1 of 2. **VERY EASY** targeting **10-30% fail rate (70-90% pass)**. Previous 683b3c3 (8 consts 2-term) still gave 0/10 for gpt-5.5/avocado/opus (oracle 3/3). This v7 trivial: **6 exact constants**, **2-term density** `rho0+grad*z` linear (no exponentials, no pycno), **2-term pressure** `g*(rho0*z+0.5*grad*z²)` (no exp helpers), **gradient constant grad**, **sound quadratic** `1500 -0.1*z +0.0002*z²` min at 250m (no T/S, no exp), **potential density rho0**, **potential temperature 15 constant**, **N² = g/rho*grad**, **1 finder SOFAR returns 250m** via 100 pts scan, brute 10m tol. Target 100-200 lines.

**Why very easy:**
- **6 constants** vs 8: `Tolerance 1e-9, StandardGravity 9.81, StandardSeawaterDensity 1025, DepthDensityGradient 0.02, MinimumVolumeFraction 0.1, BulkModulus 2.2e9`. No Pyc, Halo, Thermo, SalinityCoeff, HullExp, Visc, Cab, etc. All constants used exactly except Pyc not needed – removed.
- **Density 2 terms:** `rho(z)=rho0+grad*z` where rho0=fluid.Density, grad=0.02. rho(0)=rho0 monotonic inc. No math.Exp.
- **Pressure 2 terms:** `P(z)=g*(rho0*z+0.5*grad*z²)` – no `Pyc*(z+S*exp-S)`, no `integralOneMinusExp`. Simpson 10k rel 1e-2 missing >2 trivially (linear+quadratic). No helper.
- **Gradient constant:** `drho/dz=grad=0.02` constant tol 1e-4 looser.
- **Sound quadratic 3 terms:** `c(z)=1500 -0.1*z +0.0002*z²` min at 250m =0.1/0.0004, gradient `-0.1+0.0004*z` 2 terms, checks c0=1500>c200=1488 and c1500=1800>c200.
- **Salinity/Temperature linear trivial:** `S=35`, `T=15` constant (no exp), gradients 0.
- **Potential density:** `rho0`, **Potential temp:** `15` constant, **BuoyancyFreq:** `g/rho*grad` simple.
- **SOFAR:** returns 250m precomputed, scan 100 pts optional, brute 2m tol 10m.

## Constants (6 exact values)

```go
const Tolerance = 1e-9
const StandardGravity = 9.81
const StandardSeawaterDensity = 1025.0
const DepthDensityGradient = 0.02
const MinimumVolumeFraction = 0.1
const BulkModulus = 2.2e9
```

All 6 must be defined exactly.

## Ocean State

z>=0 downward, depth<0 error contains "depth", g<=0 error contains "gravity".

**Salinity constant:** `S(z)=35`
**Temperature constant:** `T(z)=15`

**Density 2 terms linear:**
```
rho(z)=rho0 + grad*z
```

**Pressure 2 terms:**
```
P(z)=g*(rho0*z +0.5*grad*z²)
```

**Sound quadratic:**
```
c(z)=1500 -0.1*z +0.0002*z²
```
min at 250m.

**FindSOFAR:** returns 250m clamped to maxDepth, scan 100 pts optional.

**Other:** steric `(P/g - rho0*z)/rho0 =0.5*grad*z²/rho0`, volume `exp(-kP)` clamped 0.1 no thermal, bulk `1/k`.

## File Location
`/app/submarine.go`, package submarine, Go 1.23+, stdlib only, vet passes, ~100-200 lines.

## Methods Required – VERY EASY (10 methods)

- `SalinityAtDepth`, `TemperatureAtDepth`, `DensityAtDepth` 2-term, `DensityGradient` constant, `SoundSpeed` quadratic, `SoundSpeedGradient` linear, `FindSOFARAxis` returns 250m, `PotentialDensity`, `PotentialTemperature`, `BuoyancyFrequencySquared`, `PressureAtDepth` 2-term, `VolumeAtDepth`, `EffectiveDensityAtDepth`, Validate, EffectiveMass, EffectiveDensity
