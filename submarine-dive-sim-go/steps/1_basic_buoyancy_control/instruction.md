# Step 1: Stratified Ocean Submarine – Triple Pycnocline + Halocline + Thermocline + Dual Cabbeling

## Overview
Step 1 of 2. Package `submarine` models stratified ocean with triple exponential pycnocline (shallow/mid/deep), halocline salinity, thermocline temperature, dual cabbeling couplings introducing mixed scales 24m and 22.5m, and depth-dependent thermal coupling introducing z*exp terms in pressure integral. Types/constants/methods defined here are reused in Step 2.

## Constants (24 exact values)

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
```

All 24 must be defined exactly. Reference values: 35 psu salinity, 15 C temperature, beta=SalinityDensityCoeff, gamma0=ThermalCouplingCoeff.

## Ocean State

Coordinate z>=0 downward, surface z=0. Validation: depth<0 error contains "depth", g<=0 error contains "gravity".

**Salinity:** `S(z)=35+Hd*(1-exp(-z/Hs))` where Hd=HaloclineDelta, Hs=HaloclineScale. Surface 35, monotonic increasing. `dS/dz=Hd/Hs*exp(-z/Hs)`.

**Temperature:** `T(z)=15-12*(1-exp(-z/Ts))` where Ts=ThermoclineScale. Surface 15, deep ~3, monotonic decreasing. `dT/dz=-12/Ts*exp(-z/Ts)`. Define `sAnom=Hd*(1-exp(-z/Hs))`, `tAnom=12*(1-exp(-z/Ts))`, `pyc1=D1*(1-exp(-z/S1))`, `pyc2=D2*(1-exp(-z/S2))`, `pyc3=D3*(1-exp(-z/S3))`.

**Density:**
`rho(z)=rho0+grad*z +pyc1+pyc2+pyc3 +beta*sAnom +gamma0*tAnom*(1+gDepth*z) +Cc*sAnom*tAnom +Cc*pyc3*sAnom`
where rho0=fluid.Density, grad=DepthDensityGradient, beta=SalinityDensityCoeff, gamma0=ThermalCouplingCoeff, gDepth=GammaDepthFactor, Cc=CabbelingCoeff.

Properties: rho(0)=rho0, monotonic increasing. At 60m, rho differs from model without cab terms by >=0.3. Contains mixed scales Smix24=1/(1/Hs+1/Ts)=24m and Smix22_5=1/(1/Mid+1/Hs)=22.5m from cross terms, plus z*tAnom term.

**Cabbeling parameter:** `cab(z)=Cc*sAnom*tAnom + Cc*pyc3*sAnom`, zero at surface, positive increasing.

**Spiciness:** `spice(z)=beta*(S-35)+gamma0*(T-15)`, zero at surface.

**Potential density:** `rho_pot(z)=rho(z)-grad*z`, monotonic increasing, rho_pot < rho for z>0, surface rho0.

**Potential temperature:** `theta(z)=T(z)*(1 - x - ThermobaricCoeff*x^2)` where `x=P(z)/BulkModulus*1e-3`, P from PressureAtDepth with StandardGravity. Surface 15, monotonic decreasing, theta <= T.

**Sound speed:** `c(z)=1449.2+4.6*T -0.055*T^2 +1.34*(S-35)+0.016*z+SoundSpeedPressureQuadCoeff*z^2`, surface ~1500, minimum: c0>c200 and c1500>c200.

**Sound speed gradient:** `dc/dz=4.6*dT/dz -0.11*T*dT/dz +1.34*dS/dz +0.016 +2*quad*z`, matches central diff with h=0.1 within 1e-4, negative at surface, positive at 1500m.

**SOFAR axis:** depth of minimum c in [0,maxDepth]. Scanning >=1000 points then ternary refinement until width < tolerance. Brute 0.5m scan within 1m, c(axis) <= c(axis±5m).

**Pycnocline max gradient:** depth where density gradient maximal in [0,maxDepth], same scanning+ternary, brute 0.5m within 1m.

**Buoyancy frequency:** `N^2=g/rho*drho/dz`, positive, decreasing with depth.

**Turner angle:** `Tu=atan2(gamma0*dT/dz+beta*dS/dz, beta*dS/dz -gamma0*dT/dz)*180/pi`, range -90..90.

**Double-diffusive regime:** Tu>45 contains "salt" and "finger", <-45 contains "diffus", else contains "stable".

**Pressure:** `P(z)=g*∫0^z rho(z') dz'`, P(0)=0, monotonic increasing. Closed form contains quadratic term 0.5*grad*z^2 plus additional quadratic 0.5*gamma0*gDepth*12*z^2, 5 base exponential terms, mixed terms Smix24 and Smix22_5, plus z*exp term Ts*z*exp(-z/Ts). Matches Simpson 200k rel 5e-4. Missing any mixed or z*exp >10 error.

**Steric height:** `steric(z)=(P/g - rho0*z)/rho0 = ∫(rho-rho0)/rho0`, monotonic increasing, matches Simpson 100k rel 1e-3.

**Hull volume:** `V(z)=V0*exp(-k*P)*(1+alpha*(T-15)+alpha2*(T-15)^2)` where k=Compressibility, alpha=HullThermalExpansionCoeff, alpha2=HullThermalExpansionQuadCoeff. Clamped to MinimumVolumeFraction*V0. Crush error contains "crush". Even with k=0 volume < surface, quad term present diff >1e-6 vs linear-only.

## File Location
`/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only (`math`, `errors`, `fmt`). `go vet` passes.

## Types
```go
type Submarine struct {
    DryMass float64
    Volume float64
    Length float64
    BallastCapacity float64
    BallastLevel float64
    HullCompressibility float64
    CrushDepth float64
    DragCoefficient float64
}
type Seawater struct { Density float64 }
```

## Methods Required
- `Validate() error` Submarine: DryMass>0,Volume>0,Length>0,BallastCapacity>0,BallastLevel in [0,Capacity],HullCompressibility>=0,CrushDepth>0,DragCoefficient>=0 errors contain "mass","volume","length","capacity","ballast","compressibility","crush","drag"
- `Validate() error` Seawater: Density>0 error contains "density"
- `EffectiveMass() float64` = DryMass+BallastLevel
- `EffectiveDensity() (float64,error)` = EffectiveMass/Volume
- Depth methods validate depth>=0 else "depth":
  - `DensityAtDepth(depth) (float64,error)`
  - `CabbelingParameterAtDepth(depth) (float64,error)`
  - `SpicinessAtDepth(depth) (float64,error)`
  - `DensityGradientAtDepth(depth) (float64,error)` matches central diff h=0.05 within 5e-5
  - `DensitySecondDerivativeAtDepth(depth) (float64,error)` negative increasing to 0, matches gradient diff h=0.05 within 5e-5
  - `DensityThirdDerivativeAtDepth(depth) (float64,error)` matches second derivative diff
  - `TemperatureAtDepth(depth) (float64,error)`
  - `TemperatureGradientAtDepth(depth) (float64,error)`
  - `SalinityAtDepth(depth) (float64,error)`
  - `SalinityGradientAtDepth(depth) (float64,error)`
  - `SoundSpeedAtDepth(depth) (float64,error)`
  - `SoundSpeedGradientAtDepth(depth) (float64,error)`
  - `FindSOFARAxis(maxDepth, tolerance float64) (float64,error)` >=1000 scan + ternary
  - `FindPycnoclineMaxGradient(maxDepth, tolerance float64) (float64,error)` max of gradient
  - `PotentialDensityAtDepth(depth) (float64,error)`
  - `PotentialTemperatureAtDepth(depth) (float64,error)` uses BulkModulus and ThermobaricCoeff
  - `BuoyancyFrequencySquared(depth,g) (float64,error)` g/rho*drho/dz
  - `TurnerAngleAtDepth(depth) (float64,error)`
  - `DoubleDiffusiveRegimeAtDepth(depth) (string,error)`
  - `PressureAtDepth(depth,g) (float64,error)` analytic with quadratic, mixed scales, z*exp term
  - `StericHeightAtDepth(depth,g) (float64,error)`
  - `VolumeAtDepth(depth,fluid,g) (float64,error)` exp + linear+quad thermal clamp crush
  - `EffectiveDensityAtDepth(depth,fluid,g) (float64,error)`

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

Fb(z)=rho(z)*V(z)*g, Fw=EffectiveMass*g. State via Tolerance=1e-9: |eff-fluid|<=Tol neutral, eff<fluid float else sink.

## Requirements
- 24 constants exact, structs exact, signatures exact
- Stdlib only, go vet passes, uses math.Exp, math.Abs, Atan2
- Monotonic properties enforced by tests
