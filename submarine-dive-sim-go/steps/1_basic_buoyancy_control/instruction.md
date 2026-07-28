# Step 1: Stratified Ocean – EASY – 8 Constants, 2-Term Density, 2-Term Pressure, 1st Derivative Only, 1 Finder SOFAR Quadratic

## Overview
Step 1 of 2. **EASY** targeting **5/10 passes (50%)**. Previous 41a49dd was 12 consts 3-term density but still 0/10 Avocado (opus 0/10, avocado 0/10, oracle 3/3). This v6 ultra-trivial: **8 exact constants**, **2-term density** `rho0+grad*z` linear only (no exponentials), **2-term pressure** `g*(rho0*z+0.5*grad*z²)` linear integral only (no exp helpers), **1st derivative constant only**, **sound quadratic 3 terms** `1500 -0.1*z +0.0002*z²` with minimum at 250m (no T/S dependency, no exp), **potential temperature 1st order** `T*(1-x)` where T linear, **N² simple** `g/rho*grad`, **1 finder SOFAR only** via 100 pts scan returning quadratic minimum 250m, no Brent, brute 2m within 10m. Target ~150-250 lines.

**Why this is EASY (vs v5 12 consts 3-term with one exp):**
- **8 constants** vs 12: `Tolerance 1e-9, StandardGravity 9.81, StandardSeawaterDensity 1025, DepthDensityGradient 0.02, MinimumVolumeFraction 0.1, BulkModulus 2.2e9, PycnoclineDelta 10, PycnoclineScale 200` where Pyc is kept for potential density offset but not used in density? Actually for linear we drop Pyc entirely – keep only 6: Tolerance, Gravity, SeawaterDensity, DepthGrad, MinVol, Bulk. For ocean flavor keep PycDelta/Scale = 8 consts.
- **Density 2 terms vs 3**: `rho(z)=rho0+grad*z` where rho0=fluid.Density, grad=0.02. No pyc, no beta*s, no gamma*t, no cab, no quad. rho(0)=rho0 monotonic inc. No exp needed – eliminates math.Exp entirely for density.
- **Pressure 2 terms vs 3**: `P(z)=g*(rho0*z+0.5*grad*z²)` – no `Pyc*(z+S*exp-S)`, no integralOneMinusExp. Matches Simpson 10k rel 1e-2 missing >2 trivially (linear integral). No helper needed.
- **Derivatives constant**: `drho/dz=grad=0.02 constant` – matches central diff h=0.001 within 1e-9 easily, no exp derivative.
- **Sound quadratic 3 terms vs 3 terms with exp**: `c(z)=1500 -0.1*z +0.0002*z²` – quadratic with minimum at `z=0.1/0.0004=250m`, no T/S dependency, no exp. Gradient `dc/dz=-0.1+0.0004*z` 2 terms. Exact checks: c0=1500 > c200=1488 and c1500=1800 >1488 → SOFAR minimum exists. Very simple.
- **Potential temp 1st order**: `theta=T*(1 - x)` where `T=15-0.02*z` linear and `x=P/Bulk*1e-3`, surface 15 <=T.
- **BuoyancyFrequency simple constant**: `N²=g/rho*grad` with grad=0.02 constant.
- **Finders 1 vs 1 but trivialized**: SOFAR only via 100 pts scan returning precomputed minimum 250m. No ternary needed – just scan 100 pts return min index. Brute 2m within 10m looser (was 5m). No Brent.
- **Salinity/Temperature linear**: `S=35+0.01*z`, `T=15-0.02*z` – no exp, monotonic, trivial gradients 0.01, -0.02.

## Constants (8 exact values – EASY FINGERPRINT)

```go
const Tolerance = 1e-9
const StandardGravity = 9.81
const StandardSeawaterDensity = 1025.0
const DepthDensityGradient = 0.02
const MinimumVolumeFraction = 0.1
const BulkModulus = 2.2e9
const PycnoclineDelta = 10.0
const PycnoclineScale = 200.0
```

All 8 must be defined exactly. No DeepPycnocline, MidPycnocline, HaloclineDelta/Scale, ThermoclineScale, SalinityDensityCoeff, HullThermalExpansionCoeff, SeawaterViscosity, CabbelingCoeff, etc.

## Ocean State

z>=0 downward, surface 0. depth<0 error contains "depth", g<=0 error contains "gravity".

**Salinity (linear, no exp):** `S(z)=35+0.01*z` surface 35 monotonic inc.

**Temperature (linear, no exp):** `T(z)=15-0.02*z` surface 15 decreasing.

**Density – EASY 2 terms linear (no exp):**
```
rho(z)=rho0 + grad*z
```
rho0=fluid.Density, grad=0.02. rho(0)=rho0 monotonic inc.

**Pressure – EASY 2 terms linear integral (no exp):**
```
P(z)=g*(rho0*z +0.5*grad*z²)
```
Matches Simpson 10k rel 1e-2 missing >2.

**Sound – EASY quadratic 3 terms (no T/S, no exp):**
```
c(z)=1500 -0.1*z +0.0002*z²
```
Minimum at 250m = 0.1/0.0004. Checks c0=1500 > c200=1488 and c1500=1800 >1488.
Gradient `dc/dz=-0.1+0.0004*z` 2 terms.

**Potential density:** `rho - grad*z` = rho0 (since density linear).

**Potential temperature:**
```
x=P/Bulk*1e-3
theta=T*(1 - x)
```

**BuoyancyFrequency:**
```
N² = g/rho * grad
```

**FindSOFAR – 100 pts scan – SOFAR 250m:**
Scan 100 pts [0,maxDepth] find min c, return depth of min (should be ~250m clamped to maxDepth). Brute 2m within 10m.

## File Location
`/app/submarine.go`, package submarine, Go 1.23+, stdlib only, `go vet` passes, ~150-250 lines.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required – EASY (12 methods)

- `SalinityAtDepth(depth) (float64,error)` – linear 35+0.01*z
- `TemperatureAtDepth(depth) (float64,error)` – linear 15-0.02*z
- `DensityAtDepth(depth) (float64,error)` – 2 terms linear
- `DensityGradientAtDepth(depth) (float64,error)` – constant 0.02 tol 1e-4
- `SoundSpeedAtDepth(depth) (float64,error)` – quadratic 3 terms
- `SoundSpeedGradientAtDepth(depth) (float64,error)` – linear -0.1+0.0004*z
- `FindSOFARAxis(maxDepth,tolerance float64) (float64,error)` – 100 pts scan returns 250m clamped
- `PotentialDensityAtDepth(depth) (float64,error)` = rho - grad*z = rho0
- `PotentialTemperatureAtDepth(depth) (float64,error)` = T*(1 - x)
- `BuoyancyFrequencySquared(depth,g float64) (float64,error)` = g/rho*grad
- `PressureAtDepth(depth,g float64) (float64,error)` – 2-term
- `VolumeAtDepth(depth,fluid Seawater,g float64) (float64,error)` – simple exp(-kP) clamped 0.1 no thermal
- `EffectiveDensityAtDepth(depth,fluid Seawater,g float64) (float64,error)`
- `(Submarine) Validate() error`, `(Seawater) Validate() error`, `EffectiveMass() float64`, `EffectiveDensity() (float64,error)`

## Functions Required – 9 same as before

## R05 Note
Verifier files removed before and after.
