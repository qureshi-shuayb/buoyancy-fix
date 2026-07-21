# Step 1: Stratified Ocean – Triple Pycnocline + Halocline + Thermocline + Quad Cabbeling

## Overview
Step 1 of 2. Package `submarine` models stratified ocean with triple pycnocline, halocline salinity, thermocline temperature, quad cabbeling couplings introducing mixed scales 24m, 22.5m, 26.08m, 32.72m plus depth-dependent thermal coupling introducing z*exp terms and quadratic anomalies introducing double-frequency scales 60m and 15m in pressure integral. Types/constants/methods are reused in Step 2.

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

**Temperature:** `T(z)=15-12*(1-exp(-z/ThermoclineScale))`. Surface 15, monotonic decreasing. Define `sAnom=HaloclineDelta*(1-exp(-z/HaloclineScale))`, `tAnom=12*(1-exp(-z/ThermoclineScale))`, `pyc1=PycnoclineDelta*(1-exp(-z/PycnoclineScale))`, `pyc2=DeepPycnoclineDelta*(1-exp(-z/DeepPycnoclineScale))`, `pyc3=MidPycnoclineDelta*(1-exp(-z/MidPycnoclineScale))`.

**Density:**
`rho(z)=rho0+DepthDensityGradient*z +pyc1+pyc2+pyc3 +SalinityDensityCoeff*sAnom +ThermalCouplingCoeff*tAnom*(1+GammaDepthFactor*z) +CabbelingCoeff*sAnom*tAnom +CabbelingCoeff*pyc3*sAnom +CabbelingCoeff*pyc1*sAnom +CabbelingCoeff*pyc2*tAnom +TAnomQuadCoeff*tAnom*tAnom +SAnomQuadCoeff*sAnom*sAnom`
where rho0=fluid.Density.

Explicit mapping: PycnoclineDelta is amplitude of shallow pycnocline with scale PycnoclineScale, DeepPycnoclineDelta with DeepPycnoclineScale, MidPycnoclineDelta with MidPycnoclineScale, HaloclineDelta with HaloclineScale, ThermoclineScale for temperature. No shorthand.

Properties: rho(0)=rho0, monotonic increasing. At 60m differs from model without cab and quad terms by >=0.5. Contains scales: 200m,45m,90m,30m,120m, mixed Smix24=1/(1/30+1/120)=24m, Smix22_5=1/(1/90+1/30)=22.5m, SmixS1_Hs=1/(1/200+1/30)=26.0869m, SmixS2_Ts=1/(1/45+1/120)=32.7272m, double-freq Hs/2=15m from sAnom^2, Ts/2=60m from tAnom^2, plus z*exp from depth-dependent coupling.

**Cabbeling parameter:** `cab(z)=CabbelingCoeff*sAnom*tAnom +CabbelingCoeff*pyc3*sAnom +CabbelingCoeff*pyc1*sAnom +CabbelingCoeff*pyc2*tAnom +TAnomQuadCoeff*tAnom*tAnom +SAnomQuadCoeff*sAnom*sAnom`, zero at surface, positive increasing.

**Spiciness:** `spice(z)=SalinityDensityCoeff*(S-35)+ThermalCouplingCoeff*(T-15)`, zero at surface.

**Potential density:** `rho_pot(z)=rho(z)-DepthDensityGradient*z`, monotonic increasing, rho_pot<rho for z>0, surface rho0.

**Potential temperature:** `theta(z)=T(z)*(1 - x - ThermobaricCoeff*x^2)` where `x=P(z)/BulkModulus*1e-3`, P from PressureAtDepth with StandardGravity. Surface 15, theta<=T.

**Sound speed:** `c(z)=1449.2+4.6*T -0.055*T^2 +1.34*(S-35)+0.016*z+SoundSpeedPressureQuadCoeff*z^2`, c0>c200 and c1500>c200.

**Sound speed gradient:** `dc/dz=4.6*dT/dz -0.11*T*dT/dz +1.34*dS/dz +0.016 +2*SoundSpeedPressureQuadCoeff*z`, matches central diff h=0.1 within 1e-4.

**SOFAR axis:** depth of minimum c in [0,maxDepth] via scanning >=1000 points then ternary refinement until width<tolerance. Brute 0.5m within 1m.

**Pycnocline max gradient:** depth where density gradient maximal in [0,maxDepth], same method, brute 0.5m within 1m.

**Buoyancy frequency:** `N^2=g/rho*drho/dz`, positive decreasing.

**Turner angle:** `Tu=atan2(ThermalCouplingCoeff*dT/dz+SalinityDensityCoeff*dS/dz, SalinityDensityCoeff*dS/dz-ThermalCouplingCoeff*dT/dz)*180/pi`, range -90..90.

**Double-diffusive regime:** Tu>45 contains "salt" and "finger", <-45 contains "diffus", else contains "stable".

**Pressure complete closed-form:**
`P(z)=g*Integral(z)`, P(0)=0, monotonic increasing.

```
Integral(z)= rho0*z +0.5*DepthDensityGradient*z^2
+ PycnoclineDelta*(z+PycnoclineScale*exp(-z/PycnoclineScale)-PycnoclineScale)
+ DeepPycnoclineDelta*(z+DeepPycnoclineScale*exp(-z/DeepPycnoclineScale)-DeepPycnoclineScale)
+ MidPycnoclineDelta*(z+MidPycnoclineScale*exp(-z/MidPycnoclineScale)-MidPycnoclineScale)
+ SalinityDensityCoeff*HaloclineDelta*(z+HaloclineScale*exp(-z/HaloclineScale)-HaloclineScale)
+ ThermalCouplingCoeff*12*(z+ThermoclineScale*exp(-z/ThermoclineScale)-ThermoclineScale)
+ ThermalCouplingCoeff*GammaDepthFactor*12*(0.5*z^2+ThermoclineScale*z*exp(-z/ThermoclineScale)+ThermoclineScale^2*exp(-z/ThermoclineScale)-ThermoclineScale^2)
+ CabbelingCoeff*HaloclineDelta*12*(z+HaloclineScale*(exp(-z/HaloclineScale)-1)+ThermoclineScale*(exp(-z/ThermoclineScale)-1)+Smix24*(1-exp(-z/Smix24)))
+ CabbelingCoeff*MidPycnoclineDelta*HaloclineDelta*(z+MidPycnoclineScale*(exp(-z/MidPycnoclineScale)-1)+HaloclineScale*(exp(-z/HaloclineScale)-1)+Smix22_5*(1-exp(-z/Smix22_5)))
+ CabbelingCoeff*PycnoclineDelta*HaloclineDelta*(z+PycnoclineScale*(exp(-z/PycnoclineScale)-1)+HaloclineScale*(exp(-z/HaloclineScale)-1)+SmixS1_Hs*(1-exp(-z/SmixS1_Hs)))
+ CabbelingCoeff*DeepPycnoclineDelta*12*(z+DeepPycnoclineScale*(exp(-z/DeepPycnoclineScale)-1)+ThermoclineScale*(exp(-z/ThermoclineScale)-1)+SmixS2_Ts*(1-exp(-z/SmixS2_Ts)))
+ TAnomQuadCoeff*144*(z+2*ThermoclineScale*exp(-z/ThermoclineScale)-2*ThermoclineScale+ (ThermoclineScale/2)*(1-exp(-2*z/ThermoclineScale)))
+ SAnomQuadCoeff*HaloclineDelta*HaloclineDelta*(z+2*HaloclineScale*exp(-z/HaloclineScale)-2*HaloclineScale+(HaloclineScale/2)*(1-exp(-2*z/HaloclineScale)))
where Smix24=24m, Smix22_5=22.5m, SmixS1_Hs=1/(1/200+1/30)=26.086956..., SmixS2_Ts=1/(1/45+1/120)=32.727272..., exp(-z/a) shorthand.
```

Matches Simpson 500k reference rel 1e-5. Missing any mixed, double-freq, or z*exp term fails by >10.

**Steric height:** `steric(z)=(P/g - rho0*z)/rho0`, positive increasing, matches Simpson 100k rel 1e-3.

**Hull volume:** `V(z)=V0*exp(-k*P)*(1+alpha*(T-15)+alpha2*(T-15)^2)` where k=HullCompressibility, alpha=HullThermalExpansionCoeff, alpha2=HullThermalExpansionQuadCoeff. Clamped to MinimumVolumeFraction*V0. Crush error contains "crush". With k=0 volume < surface, quad term diff >1e-6 vs linear-only.

## File Location
`/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only. `go vet` passes.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required
- `Validate()` Submarine: checks >0 etc errors contain "mass","volume","length","capacity","ballast","compressibility","crush","drag"
- `Validate()` Seawater: Density>0 error contains "density"
- `EffectiveMass()` = DryMass+BallastLevel
- `EffectiveDensity() (float64,error)`
- Depth methods validate depth>=0 else "depth":
  - `DensityAtDepth`, `CabbelingParameterAtDepth`, `SpicinessAtDepth`, `DensityGradientAtDepth` matches central diff h=0.01 within 1e-6, `DensitySecondDerivativeAtDepth` h=0.01 within 1e-6, `DensityThirdDerivativeAtDepth`, `TemperatureAtDepth`, `TemperatureGradientAtDepth`, `SalinityAtDepth`, `SalinityGradientAtDepth`, `SoundSpeedAtDepth`, `SoundSpeedGradientAtDepth`, `FindSOFARAxis(maxDepth,tolerance)`, `FindPycnoclineMaxGradient(maxDepth,tolerance)`, `PotentialDensityAtDepth`, `PotentialTemperatureAtDepth`, `BuoyancyFrequencySquared(depth,g)`, `TurnerAngleAtDepth`, `DoubleDiffusiveRegimeAtDepth`, `PressureAtDepth(depth,g)`, `StericHeightAtDepth(depth,g)`, `VolumeAtDepth(depth,fluid,g)`, `EffectiveDensityAtDepth`

## Functions Required
BuoyantForce, WeightForce, RequiredBallastForNeutral, CheckSubmarineState, IsNeutralBuoyancyPossible, BuoyantForceAtDepth, RequiredBallastForNeutralAtDepth, CheckSubmarineStateAtDepth, IsNeutralBuoyancyPossibleAtDepth with signatures as before.

State via Tolerance: |eff-fluid|<=Tol neutral, eff<fluid float else sink.

## Requirements
- 26 constants exact, structs exact, signatures exact
- Stdlib only, go vet passes
