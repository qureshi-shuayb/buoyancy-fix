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

All 26 must be defined exactly. beta=SalinityDensityCoeff, gamma0=ThermalCouplingCoeff.

## Ocean State

Coordinate z>=0 downward, surface 0. Validation: depth<0 error contains "depth", g<=0 error contains "gravity".

**Salinity:** `S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale))`. Surface 35, monotonic increasing.

**Temperature:** `T(z)=15-12*(1-exp(-z/ThermoclineScale))`. Surface 15, decreasing.

**Intermediate Variables – explicit definitions used in density and pressure:**

- `sAnom(z) = HaloclineDelta * (1 - exp(-z / HaloclineScale))` amplitude 2.5 scale 30m
- `tAnom(z) = 12 * (1 - exp(-z / ThermoclineScale))` amplitude 12 scale 120m
- `pyc1(z) = PycnoclineDelta * (1 - exp(-z / PycnoclineScale))` amplitude 10 scale 200m
- `pyc2(z) = DeepPycnoclineDelta * (1 - exp(-z / DeepPycnoclineScale))` amplitude 4.5 scale 45m
- `pyc3(z) = MidPycnoclineDelta * (1 - exp(-z / MidPycnoclineScale))` amplitude 7 scale 90m
- `expS1(z) = exp(-z / PycnoclineScale)`
- `expS2(z) = exp(-z / DeepPycnoclineScale)`
- `expS3(z) = exp(-z / MidPycnoclineScale)` also called expMid
- `expH(z) = exp(-z / HaloclineScale)`
- `expT(z) = exp(-z / ThermoclineScale)`
- `Smix24 = HaloclineScale*ThermoclineScale/(HaloclineScale+ThermoclineScale) = 24m`, `expMix24(z)=exp(-z/Smix24)`
- `Smix22_5 = MidPycnoclineScale*HaloclineScale/(MidPycnoclineScale+HaloclineScale)=22.5m`, `expMix22_5(z)=exp(-z/Smix22_5)`
- `SmixS1_Hs = PycnoclineScale*HaloclineScale/(PycnoclineScale+HaloclineScale)=26.0869m`, `expMixS1_Hs(z)=exp(-z/SmixS1_Hs)`
- `SmixS2_Ts = DeepPycnoclineScale*ThermoclineScale/(DeepPycnoclineScale+ThermoclineScale)=32.7272m`, `expMixS2_Ts(z)=exp(-z/SmixS2_Ts)`
- `exp2H(z)=exp(-2*z/HaloclineScale)` scale Hs/2=15m double frequency from sAnom^2
- `exp2T(z)=exp(-2*z/ThermoclineScale)` scale Ts/2=60m double frequency from tAnom^2

**Density:**
`rho(z) = rho0 + DepthDensityGradient*z + pyc1(z)+pyc2(z)+pyc3(z) + SalinityDensityCoeff*sAnom(z) + ThermalCouplingCoeff*tAnom(z)*(1+GammaDepthFactor*z) + CabbelingCoeff*sAnom(z)*tAnom(z) + CabbelingCoeff*pyc3(z)*sAnom(z) + CabbelingCoeff*pyc1(z)*sAnom(z) + CabbelingCoeff*pyc2(z)*tAnom(z) + TAnomQuadCoeff*tAnom(z)*tAnom(z) + SAnomQuadCoeff*sAnom(z)*sAnom(z)`
where rho0=fluid.Density.

Properties: rho(0)=rho0, monotonic increasing, at 60m differs from model without cab and quad terms by >=0.5.

**Cabbeling parameter:** sum of all cab and quad terms, zero at surface.

**Spiciness:** `spice(z)=SalinityDensityCoeff*(S(z)-35)+ThermalCouplingCoeff*(T(z)-15)`, zero at surface.

**Potential density:** `rho_pot(z)=rho(z)-DepthDensityGradient*z`, surface rho0.

**Potential temperature:** `theta(z)=T(z)*(1 - x - ThermobaricCoeff*x^2)` where `x=P(z)/BulkModulus*1e-3`, P from PressureAtDepth with StandardGravity.

**Sound speed (with cross term for extra hardness):**
`c(z)=1449.2+4.6*T -0.055*T^2 +1.34*(S-35)+0.016*z+SoundSpeedPressureQuadCoeff*z^2 +0.01*T*(S-35)`
where 0.01 is fixed coefficient for T*(S-35) coupling exclusive to acoustic. Minimum: c0>c200 and c1500>c200.

**Sound speed gradient:**
`dc/dz=4.6*dT/dz -0.11*T*dT/dz +1.34*dS/dz +0.016 +2*SoundSpeedPressureQuadCoeff*z +0.01*dT/dz*(S-35)+0.01*T*dS/dz`
Matches central diff h=0.1 within 1e-4.

**SOFAR axis:** depth of minimum c in [0,maxDepth] via scanning >=1000 points then ternary refinement until width<tolerance. Brute 0.5m within 1m.

**Pycnocline max gradient:** depth where density gradient maximal in [0,maxDepth], same method, brute 0.5m within 1m.

**Spiciness maximum:** depth where spiciness maximal in [0,maxDepth] (interior ~50-70m due to competing halocline vs thermocline), same scanning+ternary method, brute 0.5m within 1.5m.

**Buoyancy frequency:** `N^2=g/rho*drho/dz`, positive decreasing.

**Turner angle:** `Tu=atan2(ThermalCouplingCoeff*dT/dz+SalinityDensityCoeff*dS/dz, SalinityDensityCoeff*dS/dz-ThermalCouplingCoeff*dT/dz)*180/pi`, range -90..90.

**Double-diffusive regime:** Tu>45 contains "salt" and "finger", <-45 contains "diffus", else contains "stable".

**Pressure – Complete closed-form with readable breakdown:**

`P(z)=g*Integral(z)`, P(0)=0, monotonic increasing. Integral(z) is sum of terms below, each with scale noted. Matches Simpson 500k reference rel 1e-5. Missing any mixed, double-freq, or z*exp term fails by >10.

| Term | Meaning | Formula | Scale |
|------|---------|---------|-------|
| Surface ref | rho0 | `rho0*z` | – |
| Linear compressibility | quadratic from grad*z | `0.5*DepthDensityGradient*z^2` | – |
| Shallow pycnocline | D1 saturation | `PycnoclineDelta*(z+PycnoclineScale*expS1(z)-PycnoclineScale)` | 200m |
| Deep pycnocline | D2 saturation | `DeepPycnoclineDelta*(z+DeepPycnoclineScale*expS2(z)-DeepPycnoclineScale)` | 45m |
| Mid pycnocline | D3 saturation | `MidPycnoclineDelta*(z+MidPycnoclineScale*expS3(z)-MidPycnoclineScale)` | 90m |
| Halocline beta | salinity coupling | `SalinityDensityCoeff*HaloclineDelta*(z+HaloclineScale*expH(z)-HaloclineScale)` | 30m |
| Thermocline gamma | thermal coupling | `ThermalCouplingCoeff*12*(z+ThermoclineScale*expT(z)-ThermoclineScale)` | 120m |
| Depth-dependent thermal | z*tAnom | `ThermalCouplingCoeff*GammaDepthFactor*12*(0.5*z^2+Ts*z*expT(z)+Ts^2*expT(z)-Ts^2)` | includes z*exp 120m |
| Cab sAnom*tAnom | first cabbeling | `CabbelingCoeff*HaloclineDelta*12*(z+HaloclineScale*(expH(z)-1)+ThermoclineScale*(expT(z)-1)+Smix24*(1-expMix24(z)))` | Smix24=24m |
| Cab pyc3*sAnom | second cabbeling | `CabbelingCoeff*MidPycnoclineDelta*HaloclineDelta*(z+Mid* (expS3(z)-1)+Hs*(expH(z)-1)+Smix22_5*(1-expMix22_5(z)))` | 22.5m |
| Cab pyc1*sAnom | third cabbeling | `CabbelingCoeff*PycnoclineDelta*HaloclineDelta*(z+S1*(expS1(z)-1)+Hs*(expH(z)-1)+SmixS1_Hs*(1-expMixS1_Hs(z)))` | 26.0869m |
| Cab pyc2*tAnom | fourth cabbeling | `CabbelingCoeff*DeepPycnoclineDelta*12*(z+S2*(expS2(z)-1)+Ts*(expT(z)-1)+SmixS2_Ts*(1-expMixS2_Ts(z)))` | 32.7272m |
| Quad tAnom^2 | double frequency | `TAnomQuadCoeff*144*(z+2*Ts*expT(z)-2*Ts+Ts/2*(1-exp2T(z)))` | Ts/2=60m |
| Quad sAnom^2 | double frequency | `SAnomQuadCoeff*Hd*Hd*(z+2*Hs*expH(z)-2*Hs+Hs/2*(1-exp2H(z)))` | Hs/2=15m |

Go code uses `math.Exp(-depth/Scale)` for each exp and same Smix values.

**Steric height:** `(P/g - rho0*z)/rho0`, matches Simpson 100k rel 1e-3.

**Hull volume:** `V(z)=V0*exp(-k*P)*(1+alpha*(T-15)+alpha2*(T-15)^2)` clamped to MinimumVolumeFraction*V0, crush error contains "crush".

## File Location
`/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only. `go vet` passes.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required – Grouped for Large Milestone

Section A – Core Ocean (8 methods):
- `SalinityAtDepth(depth) (float64,error)`
- `SalinityGradientAtDepth(depth) (float64,error)`
- `TemperatureAtDepth(depth) (float64,error)`
- `TemperatureGradientAtDepth(depth) (float64,error)`
- `DensityAtDepth(depth) (float64,error)`
- `DensityGradientAtDepth(depth) (float64,error)` matches central diff h=0.01 within 1e-6
- `DensitySecondDerivativeAtDepth(depth) (float64,error)` matches diff h=0.01 within 1e-6
- `DensityThirdDerivativeAtDepth(depth) (float64,error)` matches diff h=0.01 within 1e-5

Section B – Acoustic (3 methods):
- `SoundSpeedAtDepth(depth) (float64,error)` includes quad and cross T*(S-35) term
- `SoundSpeedGradientAtDepth(depth) (float64,error)` includes cross term product
- `FindSOFARAxis(maxDepth,tolerance float64) (float64,error)` scanning >=1000 then ternary

Section C – Stability & Derived (8 methods):
- `PotentialDensityAtDepth(depth) (float64,error)`
- `PotentialTemperatureAtDepth(depth) (float64,error)` uses BulkModulus and ThermobaricCoeff
- `BuoyancyFrequencySquared(depth,g float64) (float64,error)` g/rho*drho/dz
- `TurnerAngleAtDepth(depth) (float64,error)`
- `DoubleDiffusiveRegimeAtDepth(depth) (string,error)`
- `FindPycnoclineMaxGradient(maxDepth,tolerance float64) (float64,error)` max of gradient
- `CabbelingParameterAtDepth(depth) (float64,error)`
- `SpicinessAtDepth(depth) (float64,error)`

Additional finder in Section C: `FindSpicinessMaximum(maxDepth,tolerance float64) (float64,error)` depth where spiciness maximal, scanning >=1000 then ternary.

Section D – Hull & Buoyancy (4 methods):
- `PressureAtDepth(depth,g float64) (float64,error)` analytic with breakdown table above
- `StericHeightAtDepth(depth,g float64) (float64,error)`
- `VolumeAtDepth(depth,fluid Seawater,g float64) (float64,error)` exp + quad thermal clamp crush
- `EffectiveDensityAtDepth(depth,fluid Seawater,g float64) (float64,error)`

Section E – Validation & Helpers (required for Step 2 reuse, kept explicit here so no hidden dependency):
- `(Submarine) Validate() error` checks DryMass>0, Volume>0, Length>0, BallastCapacity>0, BallastLevel>=0 and <=Capacity, HullCompressibility>=0, CrushDepth>0, DragCoefficient>=0, error messages contain field name keyword
- `(Seawater) Validate() error` checks Density>0
- `(Submarine) EffectiveMass() float64` returns DryMass+BallastLevel, no error
- `(Submarine) EffectiveDensity() (float64,error)` returns EffectiveMass/Volume

All depth methods validate depth>=0 else error contains "depth". Methods use math.Exp, Abs, Atan2.
Step 2 tests call `sub.EffectiveMass()` directly, so it must exist with exact signature.

Note: ~800 lines estimate includes all analytic derivatives and closed-form integrals verified against Simpson 500k and central diff h=0.01; kept as single milestone because Step2 with inherit_prior_session reuses all 26 constants and all depth methods – splitting would require redefining constants and breaking multi-turn dependency.

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
