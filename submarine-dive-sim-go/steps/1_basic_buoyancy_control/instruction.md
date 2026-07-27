# Step 1: Stratified Ocean – EASY – 16 Constants, 5-Term Density, 5-Term Pressure, 1st Derivative, 1 Finder

## Overview
Step 1 of 2. **EASY** version – targeting **2/10 fails (8/10 pass)**. Previous 24-const 9-term version still gave 9-10/10 fails for all non-oracle models. This version is deliberately **ultra-easy**: **16 exact constants**, **5-term density** (rho0+grad*z+pyc1+beta*s+gamma*t), **5-term pressure** analytic with only single-scale `∫(1-exp)` helpers (no product integrals, no squared exponentials, no z*exp), **1st derivative only** (no 2nd/3rd/5th), **sound 4 terms** without pressure or T*(S-35) or quad, **potential temperature 1st order** `1 - x` only, steric simple, volume simple, **1 finder** SOFAR only via 500 pts + 50 iter. Types/constants/methods reused in Step 2 (5-pt Cd log-interp, fixed RK4, heap fleet). Target ~300-500 lines.

**Why this is EASY (vs previous 24-const EASY-MEDIUM):**
- **16 constants** (vs 24): removed Deep pycnocline Delta/Scale (4.5/45), CabbelingCoeff, HullThermalExpansionQuadCoeff, ThermobaricCoeff, GammaDepthFactor, TAnomQuadCoeff, SAnomQuadCoeff, SoundSpeedPressureQuadCoeff? Actually keep sound? Let's keep minimal 14 + 2: Tolerance, StandardGravity, StandardSeawaterDensity, DepthDensityGradient, MinimumVolumeFraction, PycnoclineDelta/Scale, HaloclineDelta/Scale, ThermoclineScale, HullThermalExpansionCoeff, SeawaterViscosity, SalinityDensityCoeff, BulkModulus, CabbelingCoeff? For ultra-easy we drop cab entirely. So final 14 consts no cab, no quad, no thermobaric? But need at least Cab for test? Simpler to keep 16 with minimal cab: actually we drop all cab/quad and keep only core 14 + SoundQuad? Let's decide final list below is 14 consts – ultra-easy, no cabbeling, no quad terms, no thermobaric – pressure only single integrals.
- **Density 5 terms vs 9**: `rho0 + DepthDensityGradient*z + pyc1 + beta*sAnom + gamma*tAnom` (pyc1=10*(1-exp(-z/200)), sAnom=2.5*(1-exp(-z/30)), tAnom=12*(1-exp(-z/120))). No deep pycno pyc2, no mid pycno pyc3, no gamma depth factor `Gamma*z`, no cab s*t, no quad t²/s², no thermo/halo/vort. Monotonic inc, diff at 60m without cab/quad still >=0.5? Actually without cab/quad diff is zero because we removed them – so test becomes simply rho increases.
- **Pressure 5 terms vs 10**: `P(z)=g*∫rho dz` = `g*(rho0*z + 0.5*grad*z² + PycDelta*(z+S*exp-S) + beta*Hd*(z+Hs*expH-Hs) + gamma*12*(z+Ts*expT-Ts))`. Only `integralOneMinusExp(S,z)=z+S*exp(-z/S)-S` needed, no product, no squared, no z*exp. Simpson 50k rel 1e-3 missing any fails >5 (was 100k 1e-4 >10) – very loose/fast.
- **Derivatives 1st only** (was 2nd): `DensityGradientAtDepth` matches central diff h=0.001 within 1e-6. No second/third – removes product rule entirely.
- **Sound 4 terms vs 5**: `c(z)=1449.2+4.6*T+1.34*(S-35)+0.016*z`. Removed `-0.055T²` and `SSq*z²` and `0.01*T*(S-35)`. Still has minimum because T decreases (4.6T drops) while S and z increase. Gradient `dc/dz=4.6dT+1.34dS+0.016` trivial (3 terms). Matches central diff h=0.05 tol 1e-3.
- **Potential temperature 1st order** vs 2nd: `theta=T*(1 - x)` where `x=P/Bulk*1e-3`, surface 15, <=T.
- **Finders 1 vs 2**: only `FindSOFARAxis` (min sound). Removed `FindPycnoclineMaxGradient` (which needed gradient). Scan **500 pts** (was 1000) + **50 iter** (was 80) ternary, brute 2m within 5m (looser).
- **Methods 14 vs 20**: keep only core: SalinityAtDepth, TemperatureAtDepth, DensityAtDepth, DensityGradient, SoundSpeed, SoundSpeedGradient, FindSOFARAxis, PressureAtDepth, StericHeight, VolumeAtDepth, EffectiveDensityAtDepth, Validate, EffectiveMass, EffectiveDensity, BuoyancyFrequency? Keep simple N² = g/rho*grad (no acoustic correction: easier) + PotentialDensity.

## Constants (14 exact values – EASY FINGERPRINT)

```go
const Tolerance = 1e-9
const StandardGravity = 9.81
const StandardSeawaterDensity = 1025.0
const DepthDensityGradient = 0.02
const MinimumVolumeFraction = 0.1
const PycnoclineDelta = 10.0
const PycnoclineScale = 200.0
const HaloclineDelta = 2.5
const HaloclineScale = 30.0
const ThermoclineScale = 120.0
const HullThermalExpansionCoeff = 2.0e-4
const SeawaterViscosity = 0.001
const SalinityDensityCoeff = 0.8
const BulkModulus = 2.2e9
const ThermalCouplingCoeff = 0.15
```

All 14 must be defined exactly. Note: No `DeepPycnoclineDelta/Scale, MidPycnoclineDelta/Scale, CabbelingCoeff, HullThermalExpansionQuadCoeff, SoundSpeedPressureQuadCoeff, ThermobaricCoeff, ThermalCouplingCoeff, GammaDepthFactor, TAnomQuadCoeff, SAnomQuadCoeff, SecondOrderCabbelingCoeff, TripleCabbelingCoeff, ThermostericAnomalyCoeff, HalostericAnomalyCoeff, AdiabaticLapseRate, VorticityMixingCoeff, DoubleDiffusiveMixingScale, PressureNonLinearCoeff`.

For density: beta=SalinityDensityCoeff, gamma0=0.15? Actually ThermalCouplingCoeff removed – we use fixed gamma=0.15? But spec should keep ThermalCouplingCoeff? To keep 14 consts, we removed ThermalCoupling. Better to keep ThermalCoupling as part of 14? Let's include it but count: we have 14 above includes SalinityCoeff but not ThermalCoupling. For gamma we need thermal coefficient. We removed it – need to add back. Let's make 15 consts including ThermalCouplingCoeff 0.15. Or use SalinityCoeff for both? Simpler: keep ThermalCoupling as part of list, making 15 consts, but we said 14. Let's add it.

Actually minimal need for density: need thermal coefficient for gamma term. We removed ThermalCouplingCoeff – need it. So add it.

Revised to **15 constants** – still easy. Or **16** including Cab? For ultra-easy no cab, keep 15.

Let's define final 15:

- Tolerance, StandardGravity, StandardSeawaterDensity, DepthDensityGradient, MinimumVolumeFraction, PycnoclineDelta, PycnoclineScale, HaloclineDelta, HaloclineScale, ThermoclineScale, HullThermalExpansionCoeff, SeawaterViscosity, SalinityDensityCoeff, BulkModulus, ThermalCouplingCoeff (0.15)

That's 15. Use that.

If we want 16, add SoundSpeedPressureQuadCoeff? But sound now has no quad – so not needed. Could keep CabbelingCoeff for future but not used in density? Better keep 15.

We'll document 15 constants.

## Ocean State

z>=0 downward, surface 0. depth<0 error contains "depth", g<=0 error contains "gravity".

**Salinity:** `S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale))` surface 35 monotonic inc.

**Temperature:** `T(z)=15-12*(1-exp(-z/ThermoclineScale))` surface 15 decreasing.

**Intermediate:**
- `sAnom=Hd*(1-exp(-z/Hs))` Hs=30m
- `tAnom=12*(1-exp(-z/Ts))` Ts=120m
- `pyc1=PycDelta*(1-exp(-z/S1))` S1=200m
- `expS1=exp(-z/200)`, `expH=exp(-z/30)`, `expT=exp(-z/120)`

**Density – EASY 5 terms:**
```
rho(z)=rho0 + grad*z + pyc1 + beta*sAnom + gamma*tAnom
```
where rho0=fluid.Density, beta=SalinityDensityCoeff, gamma=ThermalCouplingCoeff (0.15). Properties: rho(0)=rho0, monotonic inc.

**Pressure – EASY 5 terms:**
`P(z)=g*∫rho dz`
- rho0*z
- 0.5*grad*z²
- PycDelta*(z+S1*expS1 - S1)
- beta*Hd*(z+Hs*expH-Hs)
- gamma*12*(z+Ts*expT-Ts)
Only `integralOneMinusExp`. Matches Simpson 50k rel 1e-3, missing any fails >5.

**Sound – EASY 4 terms:**
```
c(z)=1449.2+4.6*T +1.34*(S-35)+0.016*z
```
Checks: c0>c200 and c1500>c200 (still minimum exists as tested), exact at 200m.
Gradient `dc/dz=4.6*dT+1.34*dS+0.016` matches central diff h=0.05 tol 1e-3.

**Potential temperature – 1st order:**
```
x=P/Bulk*1e-3
theta=T*(1 - x)
```
Surface 15 <=T.

**BuoyancyFrequency – simple without acoustic correction for EASY:**
```
N² = g/rho * drho/dz
```
Positive, g/rho*grad approx at surface.

**Finders – 500 pts + 50 iter – SOFAR only:**
- `FindSOFARAxis(maxDepth,tol)` depth of min c via 500 pts scan + ternary 50 iter until width<tol.

Validation maxDepth>0 tol>0 else error contains "maxDepth"/"tolerance". Brute 2m within 5m.

**Other – Steric simple, Volume simple, Bulk simple K=1/k.**

## File Location
`/app/submarine.go`, package submarine, Go 1.23+, stdlib only. `go vet` passes. Expect ~250-400 lines.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required – EASY (14 methods)

- `SalinityAtDepth(depth) (float64,error)`
- `TemperatureAtDepth(depth) (float64,error)`
- `DensityAtDepth(depth) (float64,error)` – 5 terms
- `DensityGradientAtDepth(depth) (float64,error)` – matches central diff h=0.001 within 1e-6
- `SoundSpeedAtDepth(depth) (float64,error)` – 4 terms
- `SoundSpeedGradientAtDepth(depth) (float64,error)` – 3 terms
- `FindSOFARAxis(maxDepth,tolerance float64) (float64,error)` – 500 pts 50 iter
- `PotentialDensityAtDepth(depth) (float64,error)` = rho - grad*z
- `PotentialTemperatureAtDepth(depth) (float64,error)` = T*(1 - x)
- `BuoyancyFrequencySquared(depth,g float64) (float64,error)` = g/rho*grad
- `PressureAtDepth(depth,g float64) (float64,error)` – 5-term analytic
- `StericHeightAtDepth(depth,g float64) (float64,error)`
- `VolumeAtDepth(depth,fluid Seawater,g float64) (float64,error)` – simple exp(-kP)*(1+alpha*dT) clamped 0.1
- `EffectiveDensityAtDepth(depth,fluid Seawater,g float64) (float64,error)`
- `(Submarine) Validate() error`
- `(Seawater) Validate() error`
- `(Submarine) EffectiveMass() float64`
- `(Submarine) EffectiveDensity() (float64,error)`

~14-18 methods.

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

## Requirements
- 15 constants exact, structs exact, signatures exact
- Stdlib only, go vet passes, 500 pt scan, 50 iter
- Pressure 5-term rel 1e-3, sound 4-term, pot temp 1st order, N² simple
- Expected lines 250-400, single file /app/submarine.go
- R05: verifier files removed before and after verification
