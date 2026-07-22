# Step 1: Stratified Ocean – ULTRA Super-Hard – Triple Pycnocline + Halocline + Thermocline + Cubic Cabbeling + Thermosteric Layers

## Overview
Step 1 of 2. **SUPER-HARD** version – 36 exact constants, cubic cabbeling, triple mixed, thermosteric/halosteric depth coupling, vorticity layer, cubic sound, pressure 18-term analytic with z²*exp integrals, finders via Brent (2000 pts), N² with acoustic compressibility correction, potential temperature 3rd order + adiabatic lapse, 4th derivative. Types/constants/methods are reused in Step 2, which will be even harder (10-pt log-interp drag, implicit terminal Brent, adaptive RK45 with PI control, priority fleet with atomic concurrency, deadline, dive profile).

**Why this is super-hard:**
- 36 constants fingerprint, 15+ exponential scales, cubic s²t, st², triple s*t*pyc, depth-coupled thermo/halo, vorticity, z²*exp integrals, sound cubic cross T²(S-35) and T(S-35)² plus pressure coupling, N² = g/rho*(drho/dz - rho*g/c²) coupling acoustic to stability, potential temperature x³ + adiabatic lapse, volume with P² non-linear compressibility, 4th derivative, 3 finders via Brent 2000 pts + new finder FindDoubleDiffusiveLayer, spiciness curvature, potential vorticity, bulk modulus.

## Constants (36 exact values – SUPER-HARD FINGERPRINT)

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
// SUPER-HARD additions (10 new)
const SecondOrderCabbelingCoeff = 0.015
const TripleCabbelingCoeff = 0.004
const ThermostericAnomalyCoeff = 0.0008
const HalostericAnomalyCoeff = 0.0003
const AdiabaticLapseRate = 0.0002
const SoundSpeedThermoQuadCoeff = -0.00025
const SoundSpeedSalinityQuadCoeff = 0.00012
const VorticityMixingCoeff = 0.00005
const DoubleDiffusiveMixingScale = 18.0
const PressureNonLinearCoeff = 1.5e-6
```

All 36 must be defined exactly. beta=SalinityDensityCoeff, gamma0=ThermalCouplingCoeff.

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
- `expDm(z) = exp(-z / DoubleDiffusiveMixingScale)` scale 18m for vorticity layer
- `Smix24 = HaloclineScale*ThermoclineScale/(HaloclineScale+ThermoclineScale) = 24m`, `expMix24(z)=exp(-z/Smix24)`
- `Smix22_5 = MidPycnoclineScale*HaloclineScale/(MidPycnoclineScale+HaloclineScale)=22.5m`, `expMix22_5(z)=exp(-z/Smix22_5)`
- `SmixS1_Hs = PycnoclineScale*HaloclineScale/(PycnoclineScale+HaloclineScale)=26.0869m`, `expMixS1_Hs(z)=exp(-z/SmixS1_Hs)`
- `SmixS2_Ts = DeepPycnoclineScale*ThermoclineScale/(DeepPycnoclineScale+ThermoclineScale)=32.7272m`, `expMixS2_Ts(z)=exp(-z/SmixS2_Ts)`
- `SmixS1_Ts = PycnoclineScale*ThermoclineScale/(PycnoclineScale+ThermoclineScale)=75m`, `expMixS1_Ts(z)=exp(-z/SmixS1_Ts)`
- `SmixS2_Hs = DeepPycnoclineScale*HaloclineScale/(DeepPycnoclineScale+HaloclineScale)=18m`, `expMixS2_Hs(z)=exp(-z/SmixS2_Hs)`
- `SmixS1_Hs_Ts = 1/(1/PycnoclineScale+1/HaloclineScale+1/ThermoclineScale)=21.42857m`, `expMixS1_Hs_Ts=exp(-z/SmixS1_Hs_Ts)`
- `SmixS2_Hs_Ts = 1/(1/DeepPycnoclineScale+1/HaloclineScale+1/ThermoclineScale)=15.65217m`, `expMixS2_Hs_Ts=exp(-z/SmixS2_Hs_Ts)`
- `exp2H(z)=exp(-2*z/HaloclineScale)` scale Hs/2=15m double frequency from sAnom^2
- `exp2T(z)=exp(-2*z/ThermoclineScale)` scale Ts/2=60m double frequency from tAnom^2
- `Smix_2H_T = 1/(2/HaloclineScale+1/ThermoclineScale)=13.33333m`, `expMix_2H_T=exp(-z/Smix_2H_T)` for s²t term
- `Smix_H_2T = 1/(1/HaloclineScale+2/ThermoclineScale)=20m`, `expMix_H_2T=exp(-z/Smix_H_2T)` for s*t² term

**Density – SUPER-HARD with cubic & triple & depth-coupled:**

```
rho(z) = rho0 + DepthDensityGradient*z + pyc1+pyc2+pyc3 + beta*sAnom + gamma0*tAnom*(1+Gamma*z)
       + Cc*sAnom*tAnom + Cc*pyc3*sAnom + Cc*pyc1*sAnom + Cc*pyc2*tAnom
       + TAnomQuad*tAnom² + SAnomQuad*sAnom²
       // SUPER-HARD new density contributions
       + SecondOrderCabbelingCoeff*sAnom²*tAnom + SecondOrderCabbelingCoeff*sAnom*tAnom²
       + TripleCabbelingCoeff*sAnom*tAnom*pyc1 + TripleCabbelingCoeff*sAnom*tAnom*pyc2
       + ThermostericAnomalyCoeff*0.01*tAnom*z + HalostericAnomalyCoeff*0.01*sAnom*z
       + VorticityMixingCoeff*z*(1-expDm)
```

where rho0=fluid.Density, second order terms are cubic s²t, s*t², triple terms s*t*pyc, depth-coupled thermo/halo = 0.01*anomaly*z, vorticity = Vm*z*(1-expDm). Properties: rho(0)=rho0, monotonic increasing, at 60m differs from model without cab/quad/cubic by >=1.0 (was 0.5), at 30m halocline term still dominates.

**Cabbeling parameter:** zero at surface, sum of all cab, quad, second-order and triple terms:
```
cab = Cc*s*t + Cc*pyc3*s + Cc*pyc1*s + Cc*pyc2*t + Tquad*t² + Squad*s²
    + SecondOrder*s²*t + SecondOrder*s*t² + Triple*s*t*pyc1 + Triple*s*t*pyc2
```

**Spiciness:** `spice(z)=beta*(S-35)+gamma0*(T-15)`, zero at surface.

**Spiciness curvature:** second derivative of spice, `d²spice/dz²`, for mixing layer detection.

**Potential density:** `rho_pot=rho - DepthDensityGradient*z`, surface rho0.

**Potential temperature – 3rd order + adiabatic lapse:**
```
x = P(z)/BulkModulus*1e-3
theta(z)=T(z)*(1 - x - ThermobaricCoeff*x² -0.2*x³) * (1 - AdiabaticLapseRate*z*0.001)
```
Surface: theta(0)=T(0)=15. Uses BulkModulus=2.2e9, ThermobaricCoeff=0.5, AdiabaticLapseRate=0.0002. Monotonic decreasing, <=T.

**Sound speed – cubic cross + pressure coupling:**
```
c(z)=1449.2+4.6*T -0.055*T² +1.34*(S-35)+0.016*z+SoundSpeedPressureQuadCoeff*z² +0.01*T*(S-35)
    + SoundSpeedThermoQuadCoeff*T²*(S-35) + SoundSpeedSalinityQuadCoeff*T*(S-35)²
    + PressureNonLinearCoeff*1e2 * (P/BulkModulus*1e3) * T   // small pressure-T coupling ~0.1-0.3 m/s
```
Minimum: c0>c200 and c1500>c200, plus exact formula verification using T,S,P.

**Sound speed gradient:**
```
dc/dz = 4.6*dT/dz -0.11*T*dT/dz +1.34*dS/dz +0.016 +2*SoundSpeedPressureQuadCoeff*z
      +0.01*dT*(S-35)+0.01*T*dS
      + SoundSpeedThermoQuadCoeff*(2*T*dT*(S-35)+T²*dS)
      + SoundSpeedSalinityQuadCoeff*(dT*(S-35)² + T*2*(S-35)*dS)
      + PressureNonLinearCoeff*1e2 * [ (dP/dz/Bulk*1e3)*T + (P/Bulk*1e3)*dT ]
```
where dP/dz = rho*g, rho from DensityAtDepth. Matches central diff h=0.05 within 2e-4 (looser due to complexity).

**SOFAR axis / Pycnocline max / Spiciness max / Double-diffusive layer:**
- All finders via scanning **2000 points** (was 1000) equally spaced [0,maxDepth] then **Brent's method** (or ternary+Brent with parabolic interpolation) until width<tolerance. Previously ternary only.
- `FindSOFARAxis`: depth of minimum c.
- `FindPycnoclineMaxGradient`: depth where density gradient maximal.
- `FindSpicinessMaximum`: depth where spiciness maximal (interior 50-70m).
- `FindDoubleDiffusiveLayer(maxDepth,tol)`: depth where Turner angle crosses 45° (or -45), root of |Tu|-45, scanning for sign change then Brent. Brute 0.5m within 1m.
- Validation maxDepth>0, tol>0 else error contains "maxDepth"/"tolerance".

**Buoyancy frequency – with acoustic compressibility correction:**
```
N² = g/rho * (drho/dz - rho*g/c²)
```
positive decreasing, g/rho*grad at surface still approximately, but now includes `rho*g/c²` term. Verified vs formula.

**Potential vorticity:** `PV = f * N² / g` where f=1e-4 Coriolis, requires N².

**Turner angle:** `Tu=atan2(gamma*dT/dz+beta*dS/dz, beta*dS/dz - gamma*dT/dz)*180/pi`, range -90..90.

**Double-diffusive regime:** Tu>45 contains "salt" and "finger", <-45 contains "diffus", else if |Tu|<10 and |spice curvature| > VorticityMixingCoeff contains "intrusion" or "thermohaline", else contains "stable".

**Pressure – 18-term SUPER-HARD closed-form:**
`P(z)=g*Integral(z)`, P(0)=0, monotonic inc, matches Simpson 500k rel 5e-6 (was 1e-5). Missing any mixed, double-freq, z*exp, z²*exp, triple or vorticity term fails by >20 (was 10).

| Term | Meaning | Formula (Integral) | Scale |
|------|---------|-------------------|-------|
| Surface ref | rho0 | `rho0*z` | – |
| Linear | 0.5*grad*z² | `0.5*DepthDensityGradient*z²` | – |
| Shallow pycno | `Pycno* (z+S*exp- S)` | `PycnoclineDelta*(z+S1*expS1 -S1)` | 200 |
| Deep pycno | | `DeepPycnoclineDelta*(z+S2*expS2 -S2)` | 45 |
| Mid pycno | | `MidPycnoclineDelta*(z+S3*expS3 -S3)` | 90 |
| Halocline beta | | `beta*Hd*(z+Hs*expH -Hs)` | 30 |
| Thermocline gamma | | `gamma0*12*(z+Ts*expT -Ts)` | 120 |
| Depth gamma | z*tAnom | `gamma0*Gamma*12*(0.5*z²+Ts*z*expT+Ts²*expT -Ts²)` | z*exp 120 |
| Cab s*t | | `Cc*Hd*12*(z+Hs*(expH-1)+Ts*(expT-1)+Smix24*(1-expMix24))` | 24 |
| Cab pyc3*s | | `Cc*Mid*Hd*(z+Mid*(expMid-1)+Hs*(expH-1)+Smix22_5*(1-expMix22_5))` | 22.5 |
| Cab pyc1*s | | `Cc*Pycno*Hd*(z+S1*(expS1-1)+Hs*(expH-1)+SmixS1_Hs*(1-expMixS1_Hs))` | 26.08 |
| Cab pyc2*t | | `Cc*Deep*12*(z+S2*(expS2-1)+Ts*(expT-1)+SmixS2_Ts*(1-expMixS2_Ts))` | 32.72 |
| Quad t² | double freq | `Tquad*144*(z+2*Ts*expT-2*Ts+Ts/2*(1-exp2T))` | 60 |
| Quad s² | | `Squad*Hd²*(z+2*Hs*expH-2*Hs+Hs/2*(1-exp2H))` | 15 |
| **NEW** Halosteric z*s | `Halosteric*0.01*Hd*(0.5*z²+Hs*z*expH+Hs²*expH-Hs²)` | | z*exp 30 |
| **NEW** Thermosteric z*t | `Thermo*0.01*12*(0.5*z²+Ts*z*expT+Ts²*expT-Ts²)` | | z*exp 120 |
| **NEW** Vorticity z*(1-expDm) | `Vm*(0.5*z²+Dm*z*expDm+Dm²*expDm -Dm²)` | | 18 |
| **NEW** s²t cubic | `SecondOrder*Hd²*12*[ (z+Ts*expT-Ts) -2*Hs*(1-expH)+2*Smix24*(1-expMix24) + Hs/2*(1-exp2H) - Smix_2H_T*(1-expMix_2H_T) ]` | 15,24,13.33 |
| **NEW** s*t² cubic | `SecondOrder*Hd*144*[ (z+Hs*expH-Hs) -2*Ts*(1-expT)+2*Smix24*(1-expMix24) + Ts/2*(1-exp2T) - Smix_H_2T*(1-expMix_H_2T) ]` | 24,60,20 |
| **NEW** triple pyc1*s*t | `Triple*300* integralProduct([S1,Hs,Ts])` where integralProduct = sum subsets | 26.08,75,24,21.42 |
| **NEW** triple pyc2*s*t | `Triple*135* integralProduct([S2,Hs,Ts])` | 18,32.72,24,15.65 |

Go must use `math.Exp(-depth/Scale)` and mixed scales as defined. Matches Simpson 500k rel 5e-6.

**Steric height – non-linear correction:**
`(P/g - rho0*z - PressureNonLinearCoeff*P²*1e-9)/rho0` matches Simpson 100k rel 5e-4 (was 1e-3) with P² term.

**Hull volume – P² non-linear + cubic thermal (optional):**
`V(z)=V0*exp(-k*P + PressureNonLinearCoeff*P*P*1e-12)*(1+alpha*(T-15)+alpha2*(T-15)²)` clamped to MinimumVolumeFraction*V0, crush error "crush". Note `exp(-k*P + PressureNonLinearCoeff*P²*1e-12)` – P² term small but uses new constant, k=HullCompressibility. FactorThermal as before clamped 0.1.

**Bulk modulus:** `K = -V * dP/dV` or approx `1/(k -2*PressureNonLinearCoeff*P*1e-12)`? Implement as `K = 1/(HullCompressibility -2*PressureNonLinearCoeff*P*1e-12 +1e-12)` to avoid div0, or compute via derivative of volume: `dV/dP = V*(-k +2*PressureNonLinearCoeff*P*1e-12)`, so `K = -V/(dV/dP)`.

## File Location
`/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only. `go vet` passes. Expect ~1200-1500 lines due to 36 constants and 22-term pressure.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required – SUPER-HARD (28 methods)

Section A – Core Ocean (10 methods):
- `SalinityAtDepth(depth) (float64,error)`
- `SalinityGradientAtDepth(depth) (float64,error)`
- `TemperatureAtDepth(depth) (float64,error)`
- `TemperatureGradientAtDepth(depth) (float64,error)`
- `DensityAtDepth(depth) (float64,error)` – 18 terms with cubic/triple/depth-coupled
- `DensityGradientAtDepth(depth) (float64,error)` matches central diff h=0.005 within 1e-6 (was 0.01/1e-6)
- `DensitySecondDerivativeAtDepth(depth) (float64,error)` matches diff h=0.005 within 1e-5 (tighter)
- `DensityThirdDerivativeAtDepth(depth) (float64,error)` matches diff h=0.005 within 1e-4
- `DensityFourthDerivativeAtDepth(depth) (float64,error)` **NEW** matches diff h=0.005 of third within 1e-3

Section B – Acoustic (5 methods):
- `SoundSpeedAtDepth(depth) (float64,error)` – cubic cross + pressure coupling
- `SoundSpeedGradientAtDepth(depth) (float64,error)` – 6 product + pressure terms, central diff h=0.05 tol 2e-4
- `FindSOFARAxis(maxDepth,tolerance float64) (float64,error)` – 2000 pts scan then Brent 100 iter
- `FindPycnoclineMaxGradient(maxDepth,tolerance float64) (float64,error)` – 2000 pts
- `FindSpicinessMaximum(maxDepth,tolerance float64) (float64,error)` – 2000 pts
- `FindDoubleDiffusiveLayer(maxDepth,tolerance float64) (float64,error)` **NEW** – root of |Tu|-45 via Brent

Section C – Stability & Derived (12 methods):
- `PotentialDensityAtDepth(depth) (float64,error)`
- `PotentialTemperatureAtDepth(depth) (float64,error)` – 3rd order x³ + adiabatic lapse `AdiabaticLapseRate*z*0.001`
- `BuoyancyFrequencySquared(depth,g float64) (float64,error)` – `g/rho*(drho/dz - rho*g/c²)` with acoustic correction
- `TurnerAngleAtDepth(depth) (float64,error)`
- `DoubleDiffusiveRegimeAtDepth(depth) (string,error)` – salt-finger >45, diffusive <-45, intrusion if |Tu|<10 and |spice curvature|>VorticityMixingCoeff, else stable
- `FindPycnoclineMaxGradient` already in B
- `CabbelingParameterAtDepth(depth) (float64,error)` – includes second-order and triple
- `SpicinessAtDepth(depth) (float64,error)`
- `SpicinessCurvatureAtDepth(depth) (float64,error)` **NEW** – second derivative of spice
- `PotentialVorticityAtDepth(depth,g float64) (float64,error)` **NEW** = 1e-4 * N² / g
- `BulkModulusAtDepth(depth,fluid Seawater,g float64) (float64,error)` **NEW** = -V/(dV/dP)
- `Cabbeling` + `Spiciness` finders already

Section D – Hull & Buoyancy (4 methods):
- `PressureAtDepth(depth,g float64) (float64,error)` – 18-term analytic, Simpson 500k rel 5e-6, missing any mixed/double/z*exp/triple/vort fails >20
- `StericHeightAtDepth(depth,g float64) (float64,error)` – includes P² non-linear
- `VolumeAtDepth(depth,fluid Seawater,g float64) (float64,error)` – exp(-kP + PressureNonLinearCoeff*P²*1e-12)*(thermal quad) clamped
- `EffectiveDensityAtDepth(depth,fluid Seawater,g float64) (float64,error)`

Section E – Validation & Helpers (4 methods):
- `(Submarine) Validate() error` – same keywords
- `(Seawater) Validate() error` – Density>0
- `(Submarine) EffectiveMass() float64`
- `(Submarine) EffectiveDensity() (float64,error)`

Note: ~1300 lines estimate, kept single milestone because Step2 inherits all 36 constants and depth methods – splitting would break multi-turn dependency. All depth methods validate depth>=0 else error contains "depth". Use math.Exp, Abs, Atan2, Log for future Step2.

## Functions Required (Step 1)
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
- 36 constants exact, structs exact, signatures exact, 28 methods
- Stdlib only, go vet passes, 2000 pt scans for finders, Brent, 4th derivative
- Pressure 18-term rel 5e-6, steric with P², volume with P² non-linear, N² acoustic correction, sound cubic, potential temp 3rd order + lapse
