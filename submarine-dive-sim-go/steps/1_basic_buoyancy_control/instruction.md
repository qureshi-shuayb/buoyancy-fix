# Step 1: Stratified Ocean – Triple Pycnocline + Halocline + Thermocline + Quad Cabbeling

## Overview
Step 1 of 2. Package `submarine` models stratified ocean with triple pycnocline, halocline salinity, thermocline temperature, quad cabbeling couplings and depth-dependent thermal coupling and quadratic anomalies. Types/constants/methods are reused in Step 2.

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

All 26 must be defined exactly. beta=SalinityDensityCoeff, gamma0=ThermalCouplingCoeff.

## Ocean State

Coordinate z>=0 downward, surface 0. Validation: depth<0 error contains "depth", g<=0 error contains "gravity".

**Salinity:** `S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale))`. Surface 35, monotonic increasing.

**Temperature:** `T(z)=15-12*(1-exp(-z/ThermoclineScale))`. Surface 15, decreasing. Define:
- `sAnom(z)=HaloclineDelta*(1-exp(-z/HaloclineScale))`
- `tAnom(z)=12*(1-exp(-z/ThermoclineScale))`
- `pyc1(z)=PycnoclineDelta*(1-exp(-z/PycnoclineScale))` shallow amplitude 10 scale 200
- `pyc2(z)=DeepPycnoclineDelta*(1-exp(-z/DeepPycnoclineScale))` deep amplitude 4.5 scale 45
- `pyc3(z)=MidPycnoclineDelta*(1-exp(-z/MidPycnoclineScale))` mid amplitude 7 scale 90

**Density:**
`rho(z)=rho0+DepthDensityGradient*z +pyc1(z)+pyc2(z)+pyc3(z) +SalinityDensityCoeff*sAnom(z) +ThermalCouplingCoeff*tAnom(z)*(1+GammaDepthFactor*z) +CabbelingCoeff*sAnom(z)*tAnom(z) +CabbelingCoeff*pyc3(z)*sAnom(z) +CabbelingCoeff*pyc1(z)*sAnom(z) +CabbelingCoeff*pyc2(z)*tAnom(z) +TAnomQuadCoeff*tAnom(z)*tAnom(z) +SAnomQuadCoeff*sAnom(z)*sAnom(z)`
where rho0=fluid.Density.

Properties: rho(0)=rho0, monotonic increasing, at 60m differs from model without cab and quad terms by >=0.5.

**Cabbeling parameter:** sum of all cab and quad terms, zero at surface, positive increasing.

**Spiciness:** `spice(z)=SalinityDensityCoeff*(S(z)-35)+ThermalCouplingCoeff*(T(z)-15)`, zero at surface.

**Potential density:** `rho_pot(z)=rho(z)-DepthDensityGradient*z`, monotonic increasing, surface rho0.

**Potential temperature:** `theta(z)=T(z)*(1 - x - ThermobaricCoeff*x^2)` where `x=P(z)/BulkModulus*1e-3`, P from PressureAtDepth with StandardGravity.

**Sound speed:** `c(z)=1449.2+4.6*T -0.055*T^2 +1.34*(S-35)+0.016*z+SoundSpeedPressureQuadCoeff*z^2`, minimum: c0>c200 and c1500>c200.

**Sound speed gradient:** `dc/dz=4.6*dT/dz -0.11*T*dT/dz +1.34*dS/dz +0.016 +2*SoundSpeedPressureQuadCoeff*z`, matches central diff h=0.1 within 1e-4.

**SOFAR axis:** depth of minimum c in [0,maxDepth]. Scanning >=1000 points then ternary refinement until width<tolerance. Brute 0.5m within 1m.

**Pycnocline max gradient:** depth where density gradient maximal in [0,maxDepth], same method, brute 0.5m within 1m.

**Buoyancy frequency:** `N^2=g/rho*drho/dz`, positive decreasing.

**Turner angle:** `Tu=atan2(ThermalCouplingCoeff*dT/dz+SalinityDensityCoeff*dS/dz, SalinityDensityCoeff*dS/dz-ThermalCouplingCoeff*dT/dz)*180/pi`, range -90..90.

**Double-diffusive regime:** Tu>45 contains "salt" and "finger", <-45 contains "diffus", else contains "stable".

**Pressure complete closed-form:**

Integral(z) breakdown:
- `rho0*z` surface reference
- `0.5*DepthDensityGradient*z^2` linear compressibility quadratic
- `PycnoclineDelta*(z+PycnoclineScale*exp(-z/PycnoclineScale)-PycnoclineScale)` scale 200m
- `DeepPycnoclineDelta*(z+DeepPycnoclineScale*exp(-z/DeepPycnoclineScale)-DeepPycnoclineScale)` scale 45m
- `MidPycnoclineDelta*(z+MidPycnoclineScale*exp(-z/MidPycnoclineScale)-MidPycnoclineScale)` scale 90m
- `SalinityDensityCoeff*HaloclineDelta*(z+HaloclineScale*exp(-z/HaloclineScale)-HaloclineScale)` scale 30m
- `ThermalCouplingCoeff*12*(z+ThermoclineScale*exp(-z/ThermoclineScale)-ThermoclineScale)` scale 120m
- `ThermalCouplingCoeff*GammaDepthFactor*12*(0.5*z^2+ThermoclineScale*z*exp(-z/ThermoclineScale)+ThermoclineScale^2*exp(-z/ThermoclineScale)-ThermoclineScale^2)` includes z*exp
- `CabbelingCoeff*HaloclineDelta*12*(z+HaloclineScale*(expH-1)+ThermoclineScale*(expT-1)+Smix24*(1-expMix24))` Smix24=24m
- `CabbelingCoeff*MidPycnoclineDelta*HaloclineDelta*(z+Mid*(eMid-1)+Hs*(eH-1)+Smix22_5*(1-eMix22_5))` Smix22_5=22.5m
- `CabbelingCoeff*PycnoclineDelta*HaloclineDelta*(z+S1*(eS1-1)+Hs*(eH-1)+SmixS1_Hs*(1-eMixS1_Hs))` SmixS1_Hs=26.0869m
- `CabbelingCoeff*DeepPycnoclineDelta*12*(z+S2*(eS2-1)+Ts*(eT-1)+SmixS2_Ts*(1-eMixS2_Ts))` SmixS2_Ts=32.7272m
- `TAnomQuadCoeff*144*(z+2*Ts*eT-2*Ts+Ts/2*(1-exp(-2z/Ts)))` double-freq 60m
- `SAnomQuadCoeff*Hd*Hd*(z+2*Hs*eH-2*Hs+Hs/2*(1-exp(-2z/Hs)))` double-freq 15m

Full code:
```go
P(z)=g*Integral(z)
Integral = rho0*z +0.5*grad*z^2 + D1*(z+S1*exp(-z/S1)-S1)+D2*(z+S2*exp(-z/S2)-S2)+D3*(z+S3*expMid-S3)+beta*Hd*(z+Hs*expH-Hs)+gamma0*12*(z+Ts*expT-Ts)+gamma0*gDepth*12*(0.5*z^2+Ts*z*expT+Ts*Ts*expT-Ts*Ts)+Cc*Hd*12*(z+Hs*(expH-1)+Ts*(expT-1)+Smix24*(1-expMix24))+Cc*D3*Hd*(z+Mid*(expMid-1)+Hs*(expH-1)+Smix22_5*(1-expMix22_5))+Cc*D1*Hd*(z+S1*(exp1-1)+Hs*(expH-1)+SmixS1_Hs*(1-expMixS1_Hs))+Cc*D2*12*(z+S2*(exp2-1)+Ts*(expT-1)+SmixS2_Ts*(1-expMixS2_Ts))+Tquad*144*(z+2*Ts*expT-2*Ts+Ts/2*(1-exp(-2z/Ts)))+Squad*Hd*Hd*(z+2*Hs*expH-2*Hs+Hs/2*(1-exp(-2z/Hs)))
```

Matches Simpson 500k rel 1e-5. P(0)=0, monotonic increasing.

**Steric height:** `(P/g - rho0*z)/rho0`, matches Simpson 100k rel 1e-3.

**Hull volume:** `V(z)=V0*exp(-k*P)*(1+alpha*(T-15)+alpha2*(T-15)^2)` clamped to MinimumVolumeFraction*V0, crush error contains "crush".

## File Location
`/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only. `go vet` passes.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required
- `(Submarine) Validate() error` errors contain "mass","volume","length","capacity","ballast","compressibility","crush","drag"
- `(Seawater) Validate() error` contains "density"
- `EffectiveMass() float64`
- `EffectiveDensity() (float64,error)`
- Depth methods validate depth>=0 else "depth":
  - `DensityAtDepth`, `CabbelingParameterAtDepth`, `SpicinessAtDepth`, `DensityGradientAtDepth` matches central diff h=0.01 within 1e-6, `DensitySecondDerivativeAtDepth`, `DensityThirdDerivativeAtDepth`, `TemperatureAtDepth`, `TemperatureGradientAtDepth`, `SalinityAtDepth`, `SalinityGradientAtDepth`, `SoundSpeedAtDepth`, `SoundSpeedGradientAtDepth`, `FindSOFARAxis(maxDepth,tolerance)`, `FindPycnoclineMaxGradient(maxDepth,tolerance)`, `PotentialDensityAtDepth`, `PotentialTemperatureAtDepth`, `BuoyancyFrequencySquared(depth,g)`, `TurnerAngleAtDepth`, `DoubleDiffusiveRegimeAtDepth`, `PressureAtDepth(depth,g)`, `StericHeightAtDepth(depth,g)`, `VolumeAtDepth(depth,fluid,g)`, `EffectiveDensityAtDepth`

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
