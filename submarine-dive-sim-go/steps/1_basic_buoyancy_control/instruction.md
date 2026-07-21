# Step 1: Stratified Ocean – Triple Pycnocline + Halocline + Thermocline + Quad Cabbeling

## Overview
Step 1 of 2. Package `submarine` models stratified ocean with triple pycnocline, halocline salinity, thermocline temperature, quad cabbeling couplings, depth-dependent thermal coupling and quadratic anomalies. Types/constants/methods are reused in Step 2.

## Constants (26 exact values)

```go
const Tolerance = 1e-9
const StandardGravity = 9.81
const StandardSeawaterDensity = 1025.0
const DepthDensityGradient = 0.02
const MinimumVolumeFraction = 0.1
const PycnoclineDelta = 10.0
const PycnoclineScale = 200.0
const DeepPycnoclineDelta = 4.5
const DeepPycnoclineScale = 45.0
const MidPycnoclineDelta = 7.0
const MidPycnoclineScale = 90.0
const HaloclineDelta = 2.5
const HaloclineScale = 30.0
const ThermoclineScale = 120.0
const HullThermalExpansionCoeff = 2.0e-4
const SeawaterViscosity = 0.001
const SalinityDensityCoeff = 0.8
const BulkModulus = 2.2e9
const CabbelingCoeff = 0.06
const HullThermalExpansionQuadCoeff = 1.2e-6
const SoundSpeedPressureQuadCoeff = 1.2e-5
const ThermobaricCoeff = 0.5
const ThermalCouplingCoeff = 0.15
const GammaDepthFactor = 0.0001
const TAnomQuadCoeff = 0.002
const SAnomQuadCoeff = 0.01
```

All 26 must be defined exactly. beta=SalinityDensityCoeff, gamma0=ThermalCouplingCoeff, gDepth=GammaDepthFactor.

## Ocean State

Coordinate z>=0 downward, surface 0. Validation: depth<0 error contains "depth", g<=0 error contains "gravity".

**Salinity:** `S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale))`. Surface 35, monotonic increasing.

**Temperature:** `T(z)=15-12*(1-exp(-z/ThermoclineScale))`. Surface 15, decreasing.

**Intermediate Variables (definitions used in density and pressure):**
- `sAnom(z)=HaloclineDelta*(1-exp(-z/HaloclineScale))` with HaloclineDelta=2.5 scale 30m
- `tAnom(z)=12*(1-exp(-z/ThermoclineScale))` with ThermoclineScale=120m amplitude 12
- `pyc1(z)=PycnoclineDelta*(1-exp(-z/PycnoclineScale))` amplitude 10 scale 200m
- `pyc2(z)=DeepPycnoclineDelta*(1-exp(-z/DeepPycnoclineScale))` amplitude 4.5 scale 45m
- `pyc3(z)=MidPycnoclineDelta*(1-exp(-z/MidPycnoclineScale))` amplitude 7 scale 90m
- `expS1(z)=exp(-z/PycnoclineScale)`, `expS2(z)=exp(-z/DeepPycnoclineScale)`, `expS3(z)=exp(-z/MidPycnoclineScale)` also written `expMid`
- `expH(z)=exp(-z/HaloclineScale)`, `expT(z)=exp(-z/ThermoclineScale)`
- `Smix24=HaloclineScale*ThermoclineScale/(HaloclineScale+ThermoclineScale)=24m`, `expMix24(z)=exp(-z/Smix24)`
- `Smix22_5=MidPycnoclineScale*HaloclineScale/(MidPycnoclineScale+HaloclineScale)=22.5m`, `expMix22_5(z)=exp(-z/Smix22_5)`
- `SmixS1_Hs=PycnoclineScale*HaloclineScale/(PycnoclineScale+HaloclineScale)=26.0869m`, `expMixS1_Hs(z)=exp(-z/SmixS1_Hs)`
- `SmixS2_Ts=DeepPycnoclineScale*ThermoclineScale/(DeepPycnoclineScale+ThermoclineScale)=32.7272m`, `expMixS2_Ts(z)=exp(-z/SmixS2_Ts)`
- Double frequency: `exp2H(z)=exp(-2*z/HaloclineScale)` scale Hs/2=15m, `exp2T(z)=exp(-2*z/ThermoclineScale)` scale Ts/2=60m

**Density:**
`rho(z)=rho0+DepthDensityGradient*z +pyc1(z)+pyc2(z)+pyc3(z) +SalinityDensityCoeff*sAnom(z) +ThermalCouplingCoeff*tAnom(z)*(1+GammaDepthFactor*z) +CabbelingCoeff*sAnom(z)*tAnom(z) +CabbelingCoeff*pyc3(z)*sAnom(z) +CabbelingCoeff*pyc1(z)*sAnom(z) +CabbelingCoeff*pyc2(z)*tAnom(z) +TAnomQuadCoeff*tAnom(z)*tAnom(z) +SAnomQuadCoeff*sAnom(z)*sAnom(z)`
where rho0=fluid.Density.

Properties: rho(0)=rho0, monotonic increasing, at 60m differs from model without cab and quad terms by >=0.5.

**Cabbeling parameter:** sum of cab and quad terms, zero at surface.

**Spiciness:** `spice(z)=SalinityDensityCoeff*(S(z)-35)+ThermalCouplingCoeff*(T(z)-15)`, zero at surface.

**Potential density:** `rho_pot(z)=rho(z)-DepthDensityGradient*z`, surface rho0.

**Potential temperature:** `theta(z)=T(z)*(1 - x - ThermobaricCoeff*x^2)` where `x=P(z)/BulkModulus*1e-3`, P from PressureAtDepth.

**Sound speed:** `c(z)=1449.2+4.6*T -0.055*T^2 +1.34*(S-35)+0.016*z+SoundSpeedPressureQuadCoeff*z^2`.

**Sound speed gradient:** `dc/dz=4.6*dT/dz -0.11*T*dT/dz +1.34*dS/dz +0.016 +2*SoundSpeedPressureQuadCoeff*z`.

**SOFAR axis:** depth of minimum c in [0,maxDepth] via scanning >=1000 points then ternary refinement until width<tolerance.

**Pycnocline max gradient:** depth where density gradient maximal in [0,maxDepth], same method.

**Buoyancy frequency:** `N^2=g/rho*drho/dz`, positive decreasing.

**Turner angle:** `Tu=atan2(ThermalCouplingCoeff*dT/dz+SalinityDensityCoeff*dS/dz, SalinityDensityCoeff*dS/dz-ThermalCouplingCoeff*dT/dz)*180/pi`, range -90..90.

**Double-diffusive regime:** Tu>45 contains "salt" and "finger", <-45 contains "diffus", else contains "stable".

**Pressure – Complete closed-form (outcome, with defined intermediates):**

`P(z)=g*Integral(z)`, P(0)=0, monotonic, matches Simpson 500k rel 1e-5.

Integral(z) =
```
rho0*z +0.5*DepthDensityGradient*z^2
+ PycnoclineDelta*(z+PycnoclineScale*expS1(z)-PycnoclineScale)
+ DeepPycnoclineDelta*(z+DeepPycnoclineScale*expS2(z)-DeepPycnoclineScale)
+ MidPycnoclineDelta*(z+MidPycnoclineScale*expS3(z)-MidPycnoclineScale)
+ SalinityDensityCoeff*HaloclineDelta*(z+HaloclineScale*expH(z)-HaloclineScale)
+ ThermalCouplingCoeff*12*(z+ThermoclineScale*expT(z)-ThermoclineScale)
+ ThermalCouplingCoeff*GammaDepthFactor*12*(0.5*z^2+ThermoclineScale*z*expT(z)+ThermoclineScale^2*expT(z)-ThermoclineScale^2)
+ CabbelingCoeff*HaloclineDelta*12*(z+HaloclineScale*(expH(z)-1)+ThermoclineScale*(expT(z)-1)+Smix24*(1-expMix24(z)))
+ CabbelingCoeff*MidPycnoclineDelta*HaloclineDelta*(z+MidPycnoclineScale*(expS3(z)-1)+HaloclineScale*(expH(z)-1)+Smix22_5*(1-expMix22_5(z)))
+ CabbelingCoeff*PycnoclineDelta*HaloclineDelta*(z+PycnoclineScale*(expS1(z)-1)+HaloclineScale*(expH(z)-1)+SmixS1_Hs*(1-expMixS1_Hs(z)))
+ CabbelingCoeff*DeepPycnoclineDelta*12*(z+DeepPycnoclineScale*(expS2(z)-1)+ThermoclineScale*(expT(z)-1)+SmixS2_Ts*(1-expMixS2_Ts(z)))
+ TAnomQuadCoeff*144*(z+2*ThermoclineScale*expT(z)-2*ThermoclineScale+ThermoclineScale/2*(1-exp2T(z)))
+ SAnomQuadCoeff*HaloclineDelta*HaloclineDelta*(z+2*HaloclineScale*expH(z)-2*HaloclineScale+HaloclineScale/2*(1-exp2H(z)))
```

Go code equivalent uses `math.Exp(-depth/Scale)` for each exp and same Smix values.

**Steric height:** `(P/g - rho0*z)/rho0`, matches Simpson 100k rel 1e-3.

**Hull volume:** `V(z)=V0*exp(-k*P)*(1+alpha*(T-15)+alpha2*(T-15)^2)` clamped to MinimumVolumeFraction*V0, crush error contains "crush".

## File Location
`/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only. `go vet` passes.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required – Grouped to Manage Large Milestone

Section A – Core Ocean (8 methods): `SalinityAtDepth`, `SalinityGradientAtDepth`, `TemperatureAtDepth`, `TemperatureGradientAtDepth`, `DensityAtDepth`, `DensityGradientAtDepth`, `DensitySecondDerivativeAtDepth`, `DensityThirdDerivativeAtDepth` – each validates depth>=0 else "depth", matches central diff h=0.01 within 1e-6 for gradient/second/third.

Section B – Acoustic (3): `SoundSpeedAtDepth`, `SoundSpeedGradientAtDepth`, `FindSOFARAxis(maxDepth,tolerance)` – scanning >=1000 then ternary, brute 0.5m within 1m.

Section C – Stability & Derived (6): `PotentialDensityAtDepth`, `PotentialTemperatureAtDepth` uses BulkModulus, ThermobaricCoeff, `BuoyancyFrequencySquared(depth,g)`, `TurnerAngleAtDepth`, `DoubleDiffusiveRegimeAtDepth`, `FindPycnoclineMaxGradient(maxDepth,tolerance)`, plus `CabbelingParameterAtDepth`, `SpicinessAtDepth`.

Section D – Hull & Buoyancy (3): `PressureAtDepth(depth,g)` analytic as above, `StericHeightAtDepth(depth,g)`, `VolumeAtDepth(depth,fluid,g)`, `EffectiveDensityAtDepth`.

All depth methods validate depth, g>0, crush depth. Methods use math.Exp, Abs, Atan2.

Note: ~800 lines estimate includes all analytic derivatives and integrals verified against Simpson 500k and central diff h=0.01; splitting would break multi-turn inheritance requiring redefinition of 26 constants in Step2, so kept as single milestone with sections A-D.

## Functions Required
```go
func BuoyantForce(fluid Seawater, sub Submarine, g float64) (float64,error)
func WeightForce(sub Submarine, g float64) (float64,error)
func RequiredBallastForNeutral(sub Submarine, fluid Seawater) (float64,error)
func CheckSubmarineState(sub Submarine, fluid Seawater) (string,error)
func IsNeutralBuoyancyPossible(sub Submarine, fluid Seawater) (bool,error)
func BuoyantForceAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func RequiredBallastForNeutralAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func CheckSubmarineStateAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (string,error)
func IsNeutralBuoyancyPossibleAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (bool,error)
```

State via Tolerance: |eff-fluid|<=Tol neutral, eff<fluid float else sink.

## Requirements
- 26 constants exact, structs exact, signatures exact
- Stdlib only, go vet passes
