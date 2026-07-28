# Step 1: Stratified Ocean – EASY-MEDIUM – 24 Constants, 9-Term Density, 10-Term Pressure, 2nd Derivative

## Overview
Step 1 of 2. **EASY-MEDIUM** version – deliberately simplified from HARD 34-const to target ~20% failure rate (2/10 fails, 8/10 pass). **24 exact constants**, 9-term density (rho0+grad*z+2 pycno+beta*s+gamma*t*(1+Gamma*z)+Cc*s*t+Tquad*t²+Squad*s²), 10-term pressure analytic requiring only single-scale `∫(1-exp)` plus one 2-scale product `∫(1-expH)(1-expT)` and `∫(1-exp)²` squared terms plus `∫z*(1-exp)` for gamma depth coupling, derivatives up to **2nd order only** (not 3rd/5th), sound speed **5 terms** without pressure or T*(S-35) coupling, potential temperature **2nd order** `x²` only (no x³/x⁴, no z lapse), steric simple, volume simple, **2 finders** via 1000 pts + Brent 80 iter (SOFAR + pycnocline max gradient only). Types/constants/methods reused in Step 2 (5-pt log-interp drag, implicit terminal Brent, fixed RK4 vs adaptive, priority heap fleet). Target ~400-600 lines.

**Why this is EASY-MEDIUM (vs previous 34-const HARD):**
- **24 constants** fingerprint (10 removed from 34): removed `MidPycnoclineDelta/Scale, SecondOrderCabbelingCoeff, TripleCabbelingCoeff, ThermostericAnomalyCoeff, HalostericAnomalyCoeff, AdiabaticLapseRate, VorticityMixingCoeff, DoubleDiffusiveMixingScale, PressureNonLinearCoeff`. Keeps only 2 pycnoclines (shallow 200m + deep 45m), no mid pycnocline, no second-order/triple/thermo/halo/vort/pressure-nonlinear.
- **Density 9 terms** (vs 19): `rho0 + grad*z + pyc1+pyc2 + beta*sAnom + gamma0*tAnom*(1+Gamma*z) + Cc*s*t + Tquad*t² + Squad*s²`. Removed `pyc3, s²t, st², triple pyc*s*t, thermo 0.01*t*z, halo 0.01*s*z, vort z*(1-expDm)`. Monotonic inc, diff at 60m without cab/quad >=0.8 (was 1.0) – looser.
- **Pressure 10-term** (vs 18): old 10 terms (rho0, linear, 2 pycno, beta, gamma, gamma*z, cab s*t, quad t², quad s²). No s²t, st², triple, thermo, halo, vort. Helpers only `integralOneMinusExp(S,z)=z+S*exp(-z/S)-S`, `integralProduct([Hs,Ts],z)` via 4 masks (2^k, k=2), `integralZOneMinusExp(S,z)=0.5z²+S*z*exp+S²*exp-S²`, and `∫(1-exp)² = z+2S*exp-2S+S/2*(1-exp2)`. Missing any mixed/double/z*exp fails Simpson 100k rel 1e-4 by >10 (was 200k 1e-5 >20) – much looser and faster.
- **Derivatives up to 2nd only** (vs 3rd/5th): Gradient matches central diff h=0.001 within 1e-6 (was 1e-7), Second within 1e-5 (was 1e-6). No third/fourth/fifth – removes Leibniz mul2/mul3 heavy logic.
- **Cabbeling** simplified: `cab = Cc*s*t + Tquad*t² + Squad*s²` (3 terms, was 10 with second-order+triple). Zero at surface.
- **Sound 5 terms** (vs 7 with P*T): `c(z)=1449.2+4.6T-0.055T²+1.34(S-35)+0.016z+SSq*z²`. Removed `0.01*T*(S-35)` and `Pn*1e2*(P/Bulk*1e3)*T` coupling. No pressure dependency – removes chain rule P. Gradient `dc/dz=4.6dT-0.11T dT+1.34dS+0.016+2SSq*z` (4 terms). Matches central diff h=0.05 within 1e-3.
- **Potential temperature 2nd order** (vs 3rd + z lapse): `theta=T*(1 - x - Thermobaric*x²)` where `x=P/Bulk*1e-3`, surface 15, <=T. No x³/x⁴, no z lapse.
- **Steric** simple `(P/g - rho0*z)/rho0`, Volume simple `exp(-kP)*(1+alpha*dT+alpha2*dT²)` clamped, Bulk simple `K=1/k` positive.
- **Finders 2** (vs 4): only `FindSOFARAxis` (min sound) and `FindPycnoclineMaxGradient` (max density grad). Removed spiciness max and double-diffusive layer (which needs Turner angle). Scan **1000 pts** (was 2000) + Brent **80 iter** (was 100), brute 1m within 3m (was 0.5m within 2m).
- **Methods 20** (vs 26): removed `DensityThirdDerivative, SpicinessCurvature, TurnerAngle, DoubleDiffusiveRegime, PotentialVorticity (optional), FindSpicinessMaximum, FindDoubleDiffusiveLayer`.

## Constants (24 exact values – EASY-MEDIUM FINGERPRINT)

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

All 24 must be defined exactly. beta=SalinityDensityCoeff, gamma0=ThermalCouplingCoeff.

## Ocean State

Coordinate z>=0 downward, surface 0. Validation: depth<0 error contains "depth", g<=0 error contains "gravity".

**Salinity:** `S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale))`. Surface 35, monotonic increasing.

**Temperature:** `T(z)=15-12*(1-exp(-z/ThermoclineScale))`. Surface 15, decreasing.

**Intermediate Variables – explicit definitions used in density and pressure:**

- `sAnom(z) = HaloclineDelta * (1 - exp(-z / HaloclineScale))` amplitude 2.5 scale 30m
- `tAnom(z) = 12 * (1 - exp(-z / ThermoclineScale))` amplitude 12 scale 120m
- `pyc1(z) = PycnoclineDelta * (1 - exp(-z / PycnoclineScale))` amplitude 10 scale 200m
- `pyc2(z) = DeepPycnoclineDelta * (1 - exp(-z / DeepPycnoclineScale))` amplitude 4.5 scale 45m
- `expS1(z) = exp(-z / PycnoclineScale)`
- `expS2(z) = exp(-z / DeepPycnoclineScale)`
- `expH(z) = exp(-z / HaloclineScale)`
- `expT(z) = exp(-z / ThermoclineScale)`
- `Smix24 = Hs*Ts/(Hs+Ts)=24m`, `expMix24=exp(-z/Smix24)`
- `exp2H = exp(-2*z/Hs)` scale Hs/2=15m
- `exp2T = exp(-2*z/Ts)` scale Ts/2=60m

Go must use `math.Exp(-depth/Scale)` and mixed scales as defined. Any deviation fails pressure Simpson.

**Density – EASY-MEDIUM 9 terms (FIXED alignment):**

```
rho(z) = rho0 + DepthDensityGradient*z + pyc1+pyc2 + beta*sAnom + gamma0*tAnom*(1+Gamma*z)
       + Cc*sAnom*tAnom + TAnomQuad*tAnom² + SAnomQuad*sAnom²
```

Where rho0=fluid.Density, sAnom=Hd*(1-expH), tAnom=12*(1-expT). Properties: rho(0)=rho0, monotonic increasing (derivative >0), at 60m differs from model without cab/quad by >=0.8 (was 1.0).

Note: This version explicitly excludes mid pycnocline pyc3, second-order s²t/st², triple pyc*s*t, thermo/halo/vort second-order terms, and vort z*(1-expDm) and pressure-nonlinear terms that caused false negatives. Tests and golden match this spec.

**Cabbeling parameter – simplified 3 terms:**

```
cab = Cc*s*t + Tquad*t² + Squad*s²
```

Zero at surface.

**Spiciness:** `spice(z)=beta*(S-35)+gamma0*(T-15)`, zero at surface.

**Potential density:** `rho_pot=rho - DepthDensityGradient*z`, surface rho0.

**Potential temperature – 2nd order (simplified):**

```
x = P(z)/BulkModulus*1e-3
theta(z)=T(z)*(1 - x - ThermobaricCoeff*x²)
```

Surface theta(0)=T(0)=15. Monotonic decreasing, <=T. Exact check uses this 2nd order formula.

**Sound speed – EASY-MEDIUM 5 terms (FIXED alignment):**

```
c(z)=1449.2+4.6*T -0.055*T² +1.34*(S-35)+0.016*z+SoundSpeedPressureQuadCoeff*z²
```

Minimum: c0>c200 and c1500>c200, plus exact formula verification at 200m. This version explicitly excludes `0.01*T*(S-35)` and `Pn*1e2*(P/Bulk*1e3)*T` and depth-cube/T³/S³ etc – tests match displayed formula exactly.

**Sound speed gradient – EASY-MEDIUM:**

```
dc/dz = 4.6*dT -0.11*T*dT +1.34*dS +0.016 +2*SSq*z
```

Matches central diff h=0.05 within 1e-3 (looser).

**Finders – 1000 points + Brent 80 iter (simplified to 2 finders)**

All finders via scanning **1000 points** equally spaced [0,maxDepth] then Brent's method until width<tolerance.

- `FindSOFARAxis`: depth of minimum c.
- `FindPycnoclineMaxGradient`: depth where density gradient maximal.

Removed `FindSpicinessMaximum` and `FindDoubleDiffusiveLayer` (which needed Turner angle).

Validation maxDepth>0, tol>0 else error contains "maxDepth"/"tolerance". Brute 1m within 3m looser.

**Buoyancy frequency – with acoustic correction:**

```
N² = g/rho * (drho/dz - rho*g/c²)
```

Positive, g/rho*grad at surface approximately, but includes rho*g/c². Verified vs formula exact.

**Potential vorticity:** `PV = f * N² / g` where f=1e-4 Coriolis. Optional but kept simple.

**Pressure – 10-term EASY-MEDIUM closed-form:**

`P(z)=g*Integral(z)`, P(0)=0, monotonic inc, matches Simpson 100k rel 1e-4 (was 200k 1e-5). Missing any fails by >10 (was >20).

Helper integrals required:

- `integralOneMinusExp(S,z)= z + S*exp(-z/S) - S`
- `integralProductOneMinusExp([Hs,Ts],z)`: generic product ∫0^z prod_i (1-exp(-u/Scale_i)) du = sum_{mask} (-1)^{bits} * scale_{mask}*(1-exp(-z/scale_{mask})) where scale_{mask}=1/(sum_{i in mask} 1/Scale_i), mask=0 term = z. Only 4 masks needed (k=2)
- `integralZOneMinusExp(S,z)=∫0^z u*(1-exp(-u/S)) du = 0.5*z² + S*z*exp + S²*exp - S²`
- `∫(1-exp)² = z+2S*exp-2S+S/2*(1-exp2)` where `exp2=exp(-2z/S)`

Table:

| Term | Integral Formula | Scale(s) |
|------|------------------|----------|
| Sea ref | rho0*z | – |
| Linear | 0.5*grad*z² | – |
| Shallow pycno | Pycno*(z+S*exp-S) | 200 |
| Deep pycno | Deep*(z+S2*expS2 -S2) | 45 |
| Halocline beta | beta*Hd*(z+Hs*expH-Hs) | 30 |
| Thermocline gamma | gamma0*12*(z+Ts*expT-Ts) | 120 |
| Depth gamma z*t | gamma0*Gamma*12*(0.5z²+Ts*z*expT+Ts²*expT -Ts²) | z*exp 120 |
| Cab s*t | Cc*Hd*12*(z+Hs*(expH-1)+Ts*(expT-1)+Smix24*(1-expMix24)) | 24 |
| Quad t² | Tquad*144*(z+2Ts*expT-2Ts+Ts/2*(1-exp2T)) | 60 |
| Quad s² | Squad*Hd²*(z+2Hs*expH-2Hs+Hs/2*(1-exp2H)) | 15 |

Go must use `math.Exp(-depth/Scale)` and mixed scales as defined. Matches Simpson 100k rel 1e-4.

**Steric height – simple:**

`P/g - rho0*z)/rho0` rel 1e-4.

**Hull volume – simple:**

`V(z)=V0*exp(-k*P)*(1+alpha*(T-15)+alpha2*(T-15)²)` clamped to MinimumVolumeFraction*V0, crush error "crush". FactorThermal clamped 0.1.

**Bulk modulus:** `K = 1/k` or `K = -V/(dV/dP)` positive. Simple `1/k` suffices.

## File Location
`/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only. `go vet` passes. Expect ~400-600 lines due to 24 constants and 10-term pressure.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required – EASY-MEDIUM (20 methods)

Section A – Core Ocean (6 methods):
- `SalinityAtDepth(depth) (float64,error)`
- `SalinityGradientAtDepth(depth) (float64,error)`
- `TemperatureAtDepth(depth) (float64,error)`
- `TemperatureGradientAtDepth(depth) (float64,error)`
- `DensityAtDepth(depth) (float64,error)` – 9 terms
- `DensityGradientAtDepth(depth) (float64,error)` matches central diff h=0.001 within 1e-6
- `DensitySecondDerivativeAtDepth(depth) (float64,error)` matches diff h=0.001 within 1e-5

Section B – Acoustic (4 methods):
- `SoundSpeedAtDepth(depth) (float64,error)` – 5 terms, no P coupling
- `SoundSpeedGradientAtDepth(depth) (float64,error)` – 4 terms, central diff h=0.05 tol 1e-3
- `FindSOFARAxis(maxDepth,tolerance float64) (float64,error)` – 1000 pts scan then Brent 80 iter
- `FindPycnoclineMaxGradient(maxDepth,tolerance float64) (float64,error)` – 1000 pts

Section C – Stability & Derived (6 methods):
- `PotentialDensityAtDepth(depth) (float64,error)`
- `PotentialTemperatureAtDepth(depth) (float64,error)` – 2nd order x² only
- `BuoyancyFrequencySquared(depth,g float64) (float64,error)` – g/rho*(drho/dz - rho*g/c²)
- `CabbelingParameterAtDepth(depth) (float64,error)` – 3 terms
- `SpicinessAtDepth(depth) (float64,error)`
- `PotentialVorticityAtDepth(depth,g float64) (float64,error)` = 1e-4 * N² / g

Section D – Hull & Buoyancy (4 methods):
- `PressureAtDepth(depth,g float64) (float64,error)` – 10-term analytic, Simpson 100k rel 1e-4, missing any mixed/double/z*exp fails >10
- `StericHeightAtDepth(depth,g float64) (float64,error)` – simple
- `VolumeAtDepth(depth,fluid Seawater,g float64) (float64,error)` – simple exp(-kP)*(thermal quad) clamped
- `EffectiveDensityAtDepth(depth,fluid Seawater,g float64) (float64,error)`

Section E – Validation & Helpers (4 methods):
- `(Submarine) Validate() error`
- `(Seawater) Validate() error`
- `(Submarine) EffectiveMass() float64`
- `(Submarine) EffectiveDensity() (float64,error)`

Note: ~500 lines estimate. All depth methods validate depth>=0 else error contains "depth". Use math.Exp, Abs, Atan2.

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
- 24 constants exact, structs exact, signatures exact, 20 methods
- Stdlib only, go vet passes, 1000 pt scans for finders, Brent 80 iter, 2nd derivative max
- Pressure 10-term rel 1e-4, steric simple, volume simple, N² acoustic correction, sound 5 terms, potential temp 2nd order
- Expected lines 400-600, single file /app/submarine.go

## R05 Information Isolation Note
Verifier-generated files `/app/*_test.go` and `/app/ast_check*.go` are removed before and after each verifier run to prevent leaking into next inherited session. Agent must not rely on seeing those grader files.
