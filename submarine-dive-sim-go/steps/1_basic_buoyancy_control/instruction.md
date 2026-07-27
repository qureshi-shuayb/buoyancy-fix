# Step 1: Stratified Ocean – HARD – 34 Constants, 19-Term Density, 3rd Derivative

## Overview
Step 1 of 2. **HARD** version – simplified from ultra-ultra-hard to target 10-30% solve rate. **34 exact constants**, 19-term density (rho0+grad*z+3 pycno+beta*s+gamma*t*(1+Gamma*z)+4 cab+2 quad+2 cubic s²t/st²+2 triple+thermo+halo+vort), 18-term pressure analytic requiring generic product integrals for up to 3 scales (2^3=8 masks) plus ∫z*exp integrals, derivatives up to **3rd order** only, sound speed with pressure coupling P*T (no depth-cube/T³/S³/P²*T/z*P), potential temperature 3rd order x³ + z lapse, steric simple, volume simple, **4 finders** via 2000 pts + Brent 100 iter, N² acoustic correction. Types/constants/methods reused in Step 2 (10-pt log-interp drag, implicit terminal Brent, adaptive RK45, priority heap fleet). Target ~800-1100 lines.

**Why this is HARD (vs previous ultra-ultra):**
- **34 constants** fingerprint (10 removed from 44), all verified. Removed hardest 8 ultra-ultra: QuadrupleCabbelingCoeff, CompensatedLayerCoeff, ThermohalineIntrusionScale, BaroclinicShearCoeff, ThermostericSecondOrderCoeff, HalostericSecondOrderCoeff, SoundSpeedDepthCubeCoeff, PressureCubicNonLinearCoeff, plus SoundSpeedThermoQuadCoeff and SoundSpeedSalinityQuadCoeff to simplify sound.
- **Density 19 terms** (vs 26): rho0+grad*z + pyc1+pyc2+pyc3 + beta*sAnom + gamma0*tAnom*(1+Gamma*z) + 4 cab + 2 quad + 2 second-order s²t/st² + 2 triple + thermo+halo+vort. Removed quadruple s²t², compensated p1p2s, baroclinic z*s*t*(1-expI), z² thermo/halo second-order, z² vorticity. Monotonic inc, diff at 60m without cab/quad/cubic/triple >=1.0 (was 1.5).
- **Pressure 18-term** (vs 26): old 18 terms (rho0, linear, 3 pycno, beta, gamma, depth gamma, 4 cab, 2 quad, thermo, halo, vort, s²t, st², 2 triple). No quad/comp/baro/z² terms. Requires helpers `integralOneMinusExp`, `integralProduct` via subset enumeration for up to 3 scales (8 masks), `integralZExp(S,z)=S²*(1-exp(-z/S)*(1+z/S))`, `∫z*(1-exp)=0.5z² + S*z*exp + S²*exp - S²`. Missing any mixed/double/z*exp/triple fails Simpson 200k rel 1e-5 by >20 (was 500k 1e-6 >30).
- **Derivatives up to 3rd** only (vs 5th): Gradient 1e-7, Second 1e-6, Third 1e-5 via central diff h=0.001. No fourth/fifth – halves derivative work.
- **Sound** simplified: `c(z)=1449.2+4.6T-0.055T²+1.34(S-35)+0.016z+SSPressureQuad*z²+0.01T(S-35)+PressureNonLinear*1e2*(P/Bulk*1e3)*T`. Removed depth-cube z³, T³, S³, Quad*T*S, ThermoSecond, HaloSecond, P²*T, z*P. Gradient 7 terms.
- **Potential temperature** 3rd order x³ + z lapse (vs 4th order x⁴+z² lapse): theta=T*(1 -x -Thermobaric*x² -0.2*x³)*(1 - Adiabatic*z*0.001). No x⁴, no z² term.
- **Steric** simple: (P/g - rho0*z)/rho0 (vs P²+P³ correction)
- **Volume** simple: exp(-kP)*(1+alpha*dT+alpha2*dT²) clamped (vs P³+Comp*dT*P cross)
- **Finders**: 2000 pts scan (vs 3000) + Brent 100 iter (vs 200) for SOFAR, pycno max, spice max, double-diffusive layer. Removed thermocline, halocline, compensated layer finders. Brute 0.5m within 2m.
- **Methods**: 26 methods (vs 35): removed DensityFourth/Fifth, SoundSpeedCurvature, BuoyancyFrequencyGradient, SpicinessTorsion, Thermocline/Halocline/Compensated finders.

## Constants (34 exact values – HARD FINGERPRINT)

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
const SecondOrderCabbelingCoeff = 0.015
const TripleCabbelingCoeff = 0.004
const ThermostericAnomalyCoeff = 0.0008
const HalostericAnomalyCoeff = 0.0003
const AdiabaticLapseRate = 0.0002
const VorticityMixingCoeff = 0.00005
const DoubleDiffusiveMixingScale = 18.0
const PressureNonLinearCoeff = 1.5e-6
```

All 34 must be defined exactly. beta=SalinityDensityCoeff, gamma0=ThermalCouplingCoeff.

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
- `expS3(z) = exp(-z / MidPycnoclineScale)`
- `expH(z) = exp(-z / HaloclineScale)`
- `expT(z) = exp(-z / ThermoclineScale)`
- `expDm(z) = exp(-z / DoubleDiffusiveMixingScale)` scale 18m
- `Smix24 = Hs*Ts/(Hs+Ts)=24m`, `expMix24=exp(-z/Smix24)`
- `Smix22_5 = Mid*Hs/(Mid+Hs)=22.5m`
- `SmixS1_Hs = S1*Hs/(S1+Hs)=26.0869565217m`
- `SmixS2_Ts = S2*Ts/(S2+Ts)=32.7272727272m`
- `SmixS1_Ts = S1*Ts/(S1+Ts)=75m`
- `SmixS2_Hs = S2*Hs/(S2+Hs)=18m`
- `SmixS1_Hs_Ts = 1/(1/S1+1/Hs+1/Ts)=21.4285714286m`
- `SmixS2_Hs_Ts = 1/(1/S2+1/Hs+1/Ts)=15.652173913m`
- `exp2H = exp(-2*z/Hs)` scale Hs/2=15m
- `exp2T = exp(-2*z/Ts)` scale Ts/2=60m
- `Smix_2H_T = 1/(2/Hs+1/Ts)=13.3333333333m` for s²t
- `Smix_H_2T = 1/(1/Hs+2/Ts)=20m` for s*t²

Go must use `math.Exp(-depth/Scale)` and mixed scales as defined. Any deviation fails pressure Simpson.

**Density – HARD 19 terms (FIXED alignment):**

```
rho(z) = rho0 + DepthDensityGradient*z + pyc1+pyc2+pyc3 + beta*sAnom + gamma0*tAnom*(1+Gamma*z)
       + Cc*sAnom*tAnom + Cc*pyc3*sAnom + Cc*pyc1*sAnom + Cc*pyc2*tAnom
       + TAnomQuad*tAnom² + SAnomQuad*sAnom²
       + SecondOrder*sAnom²*tAnom + SecondOrder*sAnom*tAnom²
       + Triple*sAnom*tAnom*pyc1 + Triple*sAnom*tAnom*pyc2
       + Thermosteric*0.01*tAnom*z + Halosteric*0.01*sAnom*z + Vorticity*z*(1-expDm)
```

Where rho0=fluid.Density, sAnom=Hd*(1-expH), tAnom=12*(1-expT). Properties: rho(0)=rho0, monotonic increasing (derivative >0), at 60m differs from model without cab/quad/cubic/triple by >=1.0.

Note: **FIXED** – Previous version included `VorticityMixingCoeff*0.01*z²*(1-expDm)` second-order vorticity term in spec but tests/golden omitted it, causing false negatives. This version **explicitly excludes** that z² term – only `Vorticity*z*(1-expDm)` is required. Tests and golden match this spec.

**Cabbeling parameter – includes second-order and triple:**

```
cab = Cc*s*t + Cc*pyc3*s + Cc*pyc1*s + Cc*pyc2*t + Tquad*t² + Squad*s²
    + SecondOrder*s²*t + SecondOrder*s*t² + Triple*s*t*pyc1 + Triple*s*t*pyc2
```

Zero at surface.

**Spiciness:** `spice(z)=beta*(S-35)+gamma0*(T-15)`, zero at surface.

**Spiciness curvature:** second derivative of spice, `d²spice/dz²`, for mixing layer detection. `dS/dz=Hd/Hs*expH`, `d²S=-Hd/Hs²*expH`, `dT/dz=-12/Ts*expT`, `d²T=12/Ts²*expT`, so curvature = beta*d²S + gamma0*d²T.

**Potential density:** `rho_pot=rho - DepthDensityGradient*z`, surface rho0.

**Potential temperature – 3rd order + z lapse (simplified):**

```
x = P(z)/BulkModulus*1e-3
theta(z)=T(z)*(1 - x - ThermobaricCoeff*x² -0.2*x³) * (1 - AdiabaticLapseRate*z*0.001)
```

Surface theta(0)=T(0)=15. Monotonic decreasing, <=T.

**Sound speed – HARD simplified (FIXED alignment):**

```
c(z)=1449.2+4.6*T -0.055*T² +1.34*(S-35)+0.016*z+SoundSpeedPressureQuadCoeff*z²+0.01*T*(S-35)
    + PressureNonLinearCoeff*1e2 * (P/BulkModulus*1e3) * T
```

Minimum: c0>c200 and c1500>c200, plus exact formula verification using T,S,P at 200m. This version **explicitly includes** the pressure coupling term and **excludes** depth-cube z³, T³, S³, Quad*T*(S-35), ThermoSecond*T², HaloSecond*S², P²*T, z*P that were hidden in previous tests but not in spec. Tests now match displayed formula exactly.

**Sound speed gradient – HARD simplified:**

```
dc/dz = 4.6*dT -0.11*T*dT +1.34*dS +0.016 +2*SSPressureQuad*z
      +0.01*dT*(S-35)+0.01*T*dS
      + PressureNonLinear*1e2 * [ (dP/dz/Bulk*1e3)*T + (P/Bulk*1e3)*dT ]
```

Where dP/dz = rho*g, rho from DensityAtDepth. Matches central diff h=0.05 within 1e-3 (looser).

**Finders – 2000 points + Brent 100 iter (simplified)**

All finders via scanning **2000 points** equally spaced [0,maxDepth] then Brent's method until width<tolerance.

- `FindSOFARAxis`: depth of minimum c.
- `FindPycnoclineMaxGradient`: depth where density gradient maximal.
- `FindSpicinessMaximum`: depth where spiciness maximal.
- `FindDoubleDiffusiveLayer(maxDepth,tol)`: depth where Turner angle crosses 45° or -45, root of |Tu|-45, scanning for sign change then Brent. Brute 0.5m within 2m.

Validation maxDepth>0, tol>0 else error contains "maxDepth"/"tolerance".

**Buoyancy frequency – with acoustic correction:**

```
N² = g/rho * (drho/dz - rho*g/c²)
```

Positive, g/rho*grad at surface approximately, but includes rho*g/c². Verified vs formula exact.

**Potential vorticity:** `PV = f * N² / g` where f=1e-4 Coriolis.

**Turner angle:** `Tu=atan2(gamma*dT/dz+beta*dS/dz, beta*dS/dz - gamma*dT/dz)*180/pi`, range -90..90.

**Double-diffusive regime:** Tu>45 contains "salt" and "finger", <-45 contains "diffus", else contains "stable" or "intrusion".

**Pressure – 18-term HARD closed-form:**

`P(z)=g*Integral(z)`, P(0)=0, monotonic inc, matches Simpson 200k rel 1e-5. Missing any mixed, double-freq, z*exp, triple fails by >20.

Helper integrals required:

- `integralOneMinusExp(S,z)= z + S*exp(-z/S) - S`
- `integralProductOneMinusExp(scales,z)`: generic product ∫0^z prod_i (1-exp(-u/Scale_i)) du = sum_{mask} (-1)^{bits} * scale_{mask}*(1-exp(-z/scale_{mask})) where scale_{mask}=1/(sum_{i in mask} 1/Scale_i), with mask=0 term = z. This is inclusion-exclusion over 2^k masks (up to k=3 -> 8 masks).
- `integralZExp(S,z)=∫0^z u*exp(-u/S) du = S²*(1 - exp(-z/S)*(1+z/S))` plus variant `∫0^z u*(1-exp(-u/S)) du = 0.5*z² + S*z*exp + S²*exp - S²`

Provide explicit table:

| Term | Meaning | Integral Formula | Scale(s) |
|------|---------|------------------|----------|
| Surface ref | rho0 | rho0*z | – |
| Linear | 0.5*grad*z² | 0.5*DepthDensityGradient*z² | – |
| Shallow pycno | Pycno*(z+S*exp-S) | PycnoclineDelta*(z+S1*expS1 -S1) | 200 |
| Deep pycno | | Deep*(z+S2*expS2 -S2) | 45 |
| Mid pycno | | Mid*(z+S3*expS3 -S3) | 90 |
| Halocline beta | | beta*Hd*(z+Hs*expH-Hs) | 30 |
| Thermocline gamma | | gamma0*12*(z+Ts*expT-Ts) | 120 |
| Depth gamma | z*tAnom | gamma0*Gamma*12*(0.5*z²+Ts*z*expT+Ts²*expT -Ts²) | z*exp 120 |
| Cab s*t | | Cc*Hd*12*(z+Hs*(expH-1)+Ts*(expT-1)+Smix24*(1-expMix24)) | 24 |
| Cab pyc3*s | | Cc*Mid*Hd*(z+Mid*(expMid-1)+Hs*(expH-1)+Smix22_5*(1-expMix22_5)) | 22.5 |
| Cab pyc1*s | | Cc*Pycno*Hd*(z+S1*(expS1-1)+Hs*(expH-1)+SmixS1_Hs*(1-expMixS1_Hs)) | 26.08 |
| Cab pyc2*t | | Cc*Deep*12*(z+S2*(expS2-1)+Ts*(expT-1)+SmixS2_Ts*(1-expMixS2_Ts)) | 32.72 |
| Quad t² | | Tquad*144*(z+2*Ts*expT-2*Ts+Ts/2*(1-exp2T)) | 60 |
| Quad s² | | Squad*Hd²*(z+2*Hs*expH-2*Hs+Hs/2*(1-exp2H)) | 15 |
| Halosteric z*s | | Halosteric*0.01*Hd*(0.5*z²+Hs*z*expH+Hs²*expH-Hs²) | z*exp 30 |
| Thermosteric z*t | | Thermo*0.01*12*(0.5*z²+Ts*z*expT+Ts²*expT-Ts²) | z*exp 120 |
| Vorticity z*(1-expDm) | | Vm*(0.5*z²+Dm*z*expDm+Dm²*expDm -Dm²) | 18 |
| s²t cubic | | SecondOrder*Hd²*12* integralProduct([Hs,Hs,Ts]) | 15,24,13.33 |
| s*t² cubic | | SecondOrder*Hd*144* integralProduct([Hs,Ts,Ts]) | 24,60,20 |
| triple pyc1*s*t | | Triple*300* integralProduct([S1,Hs,Ts]) | 26.08,75,24,21.42 |
| triple pyc2*s*t | | Triple*135* integralProduct([S2,Hs,Ts]) | 18,32.72,24,15.65 |

Go must use math.Exp(-depth/Scale) and mixed scales as defined. Matches Simpson 200k rel 1e-5.

**Steric height – simple:**

`P/g - rho0*z)/rho0` matches exact formula rel 1e-4.

**Hull volume – simple:**

`V(z)=V0*exp(-k*P)*(1+alpha*(T-15)+alpha2*(T-15)²)` clamped to MinimumVolumeFraction*V0, crush error "crush". FactorThermal clamped 0.1.

**Bulk modulus:** `K = 1/k` approx or `K = -V/(dV/dP)` where `dV/dP = V*(-k)*factor`, positive.

## File Location
`/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only. `go vet` passes. Expect ~800-1100 lines due to 34 constants and 18-term pressure.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required – HARD (26 methods)

Section A – Core Ocean (7 methods):
- `SalinityAtDepth(depth) (float64,error)`
- `SalinityGradientAtDepth(depth) (float64,error)`
- `TemperatureAtDepth(depth) (float64,error)`
- `TemperatureGradientAtDepth(depth) (float64,error)`
- `DensityAtDepth(depth) (float64,error)` – 19 terms
- `DensityGradientAtDepth(depth) (float64,error)` matches central diff h=0.001 within 1e-7 (was 1e-8)
- `DensitySecondDerivativeAtDepth(depth) (float64,error)` matches diff h=0.001 within 1e-6
- `DensityThirdDerivativeAtDepth(depth) (float64,error)` matches diff h=0.001 within 1e-5

Section B – Acoustic (6 methods):
- `SoundSpeedAtDepth(depth) (float64,error)` – with P*T coupling, no depth-cube/T³/S³
- `SoundSpeedGradientAtDepth(depth) (float64,error)` – 7 terms, central diff h=0.05 tol 1e-3
- `FindSOFARAxis(maxDepth,tolerance float64) (float64,error)` – 2000 pts scan then Brent 100 iter
- `FindPycnoclineMaxGradient(maxDepth,tolerance float64) (float64,error)` – 2000 pts
- `FindSpicinessMaximum(maxDepth,tolerance float64) (float64,error)` – 2000 pts
- `FindDoubleDiffusiveLayer(maxDepth,tolerance float64) (float64,error)` – root |Tu|-45 via Brent

Section C – Stability & Derived (9 methods):
- `PotentialDensityAtDepth(depth) (float64,error)`
- `PotentialTemperatureAtDepth(depth) (float64,error)` – 3rd order x³ + z lapse (not 4th order)
- `BuoyancyFrequencySquared(depth,g float64) (float64,error)` – g/rho*(drho/dz - rho*g/c²)
- `TurnerAngleAtDepth(depth) (float64,error)`
- `DoubleDiffusiveRegimeAtDepth(depth) (string,error)` – salt-finger >45, diffusive <-45, else stable/intrusion
- `CabbelingParameterAtDepth(depth) (float64,error)` – includes second-order + triple
- `SpicinessAtDepth(depth) (float64,error)`
- `SpicinessCurvatureAtDepth(depth) (float64,error)` – second derivative
- `PotentialVorticityAtDepth(depth,g float64) (float64,error)` = 1e-4 * N² / g
- `BulkModulusAtDepth(depth,fluid Seawater,g float64) (float64,error)` = -V/(dV/dP) simple

Section D – Hull & Buoyancy (4 methods):
- `PressureAtDepth(depth,g float64) (float64,error)` – 18-term analytic, Simpson 200k rel 1e-5, missing any mixed/double/z*exp/triple fails >20
- `StericHeightAtDepth(depth,g float64) (float64,error)` – simple
- `VolumeAtDepth(depth,fluid Seawater,g float64) (float64,error)` – simple exp(-kP)*(thermal quad) clamped
- `EffectiveDensityAtDepth(depth,fluid Seawater,g float64) (float64,error)`

Section E – Validation & Helpers (4 methods):
- `(Submarine) Validate() error` – same keywords
- `(Seawater) Validate() error` – Density>0
- `(Submarine) EffectiveMass() float64`
- `(Submarine) EffectiveDensity() (float64,error)`

Note: ~900-1100 lines estimate. All depth methods validate depth>=0 else error contains "depth". Use math.Exp, Abs, Atan2.

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
- 34 constants exact, structs exact, signatures exact, 26 methods (including up to 3rd derivative)
- Stdlib only, go vet passes, 2000 pt scans for finders, Brent 100 iter, 3rd derivative
- Pressure 18-term rel 1e-5, steric simple, volume simple, N² acoustic correction, sound with P*T coupling only, potential temp 3rd order + z lapse
- Expected lines 800-1100, single file /app/submarine.go
