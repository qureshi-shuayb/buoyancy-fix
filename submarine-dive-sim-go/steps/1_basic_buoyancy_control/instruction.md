# Step 1: ULTRA Super-Hard Submarine — Triple Pycnocline + Halocline Salinity + Thermocline T/S Coupling + Sound Speed + Potential Density

## Overview
This is **Step 1 of 2** ultra super-hard multi-turn submarine simulator. You are building a Go package that models realistic ocean with **triple exponential pycnocline** (shallow + deep + mid), **halocline salinity**, **thermocline temperature** with T/S coupling to density, **sound speed SOFAR channel**, **potential density**, **second derivative**, **Turner angle**.

Step 1 implements foundational types plus depth-aware buoyancy with full T/S/Z model: surface sink/float/neutral, plus how density, its first/second derivatives, salinity, temperature, their gradients, sound speed, potential density, potential temperature, Brunt-Vaisala frequency, Turner angle, pressure, hull volume with thermal contraction, buoyancy, and required ballast evolve with depth. **Step 2 will reuse your types** to add simple Re table drag, fixed RK4 time-to-depth, multi-root equilibrium scanning, and bounded fleet analysis. Define types cleanly now; do NOT rename fields/package/constants.

Goal: model fully submerged submarine where seawater density has 5 exponential contributions: three pycnoclines + halocline salinity + thermocline thermal coupling.

## Ocean & Physics Background (Derive Formulas Yourself - No Explicit Pressure Formula Given)

**Effective mass:** DryMass + BallastLevel. Effective density = EffectiveMass / Volume at that depth.

**State decision:** Compare effective density to local seawater density using absolute tolerance `Tolerance=1e-9`. If |eff - fluid| <= Tolerance => "neutral", else if eff < fluid => "float", else "sink". Exact lower-case strings.

**Depth coordinate:** z >=0 positive downward, surface z=0.

**Salinity profile (halocline):**
Reference salinity `Sref=35.0 psu`. Salinity increases with depth as `S(z)=35 + HaloclineDelta*(1-exp(-z/HaloclineScale))` where `HaloclineDelta=2.5 psu`, `HaloclineScale=30.0 m`. At surface 35, at deep ~37.5 psu. Monotonic increasing, saturates. Implement `SalinityAtDepth`.

**Temperature profile (thermocline):**
Reference surface temperature `Tref=15.0 C`. Temperature drops as `T(z)=15 -12*(1-exp(-z/ThermoclineScale))` where `ThermoclineScale=120.0 m`. Surface 15C, deep ~3C. Monotonic decreasing. Implement `TemperatureAtDepth`.

**Salinity & Temperature gradients:**
- `dS/dz = HaloclineDelta/HaloclineScale*exp(-z/HaloclineScale)` positive decreasing.
- `dT/dz = -12/ThermoclineScale*exp(-z/ThermoclineScale)` negative increasing (less negative) with depth.
Implement `SalinityGradientAtDepth`, `TemperatureGradientAtDepth`.

**Seawater density with triple pycnocline + T/S coupling:**
Ocean density has seven contributions:
- Surface density `rho_surface = fluid.Density`
- Linear compressibility `DepthDensityGradient=0.02 kg/m4 * z`
- Shallow pycnocline `PycnoclineDelta=10.0 kg/m3` over `PycnoclineScale=200.0 m`: `D1*(1-exp(-z/S1))`
- Deep halocline pycnocline `DeepPycnoclineDelta=4.5 kg/m3` over `DeepPycnoclineScale=45.0 m`: `D2*(1-exp(-z/S2))`
- Mid pycnocline `MidPycnoclineDelta=7.0 kg/m3` over `MidPycnoclineScale=90.0 m`: `D3*(1-exp(-z/S3))`
- Halocline salinity coupling `beta*(S(z)-35)` where `beta=SalinityDensityCoeff=0.8 kg/m3 per psu`
- Thermocline thermal coupling `gamma*(15 - T(z))` where `gamma=0.15 kg/m3 per C` fixed (not a constant, but 0.15). Since T drops 12C, this adds ~1.8 kg/m3.

So `rho(z)=rho_surface + grad*z + D1*(1-exp(-z/S1))+D2*(1-exp(-z/S2))+D3*(1-exp(-z/S3)) + beta*(S(z)-35) + gamma*(15 - T(z))`

You must combine into single rho(z) that is monotonic increasing, starts at rho_surface at z=0, includes linear + triple exponential + salinity + thermal. Do not hardcode numeric examples; derive from description. Must contain 5 distinct exp terms (3 pycnocline + halocline + thermocline).

**Density gradient:**
Derivative `drho/dz = grad + D1/S1*exp(-z/S1)+D2/S2*exp(-z/S2)+D3/S3*exp(-z/S3) + beta*dS/dz + gamma*(-dT/dz)` where `-dT/dz = 12/Therm*exp(-z/Therm)` positive. So 5 exp terms. Must be positive decreasing with depth. Implement `DensityGradientAtDepth`.

**Second derivative:**
`d2rho/dz2 = -D1/S1²*exp(-z/S1) -D2/S2²*exp(-z/S2) -D3/S3²*exp(-z/S3) -beta*HaloclineDelta/HaloclineScale²*exp(-z/Hs) -gamma*12/Therm²*exp(-z/Therm)` negative, increasing toward 0. Implement `DensitySecondDerivativeAtDepth`.

**Sound speed (SOFAR channel):**
Simplified UNESCO formula: `c(z)=1449.2 +4.6*T(z) -0.055*T(z)² +1.34*(S(z)-35) +0.016*z` where T(z) thermocline, S(z) halocline, z depth. Surface T 15 => c~1500, at thermocline depth T drops reducing c, but depth term 0.016*z increases c at large depth, creating minimum around 600-1000m SOFAR channel. Implement `SoundSpeedAtDepth`. Must show minimum: c at 0 > c at 200, and c at 1500 > c at 200.

**Potential density (density at surface pressure):**
Remove linear compressible gradient and pressure effect: `rho_pot(z)=rho0 + D1*(1-exp(-z/S1))+D2*(1-exp(-z/S2))+D3*(1-exp(-z/S3)) + beta*(S(z)-35) + gamma*(15 - T(z))` — i.e., rho without `grad*z` term. Alternatively could define as `rho(z)/(1+P(z)/BulkModulus)` but for this task use above definition (without grad*z) to keep analytic. Must be monotonic increasing but less steep than in-situ rho. Implement `PotentialDensityAtDepth`.

**Potential temperature:**
Simplified: `theta(z)=T(z) * (1 - P(z)*1e-10)` or just `T(z)` with small compression correction. For this task define `theta(z)=T(z)` (potential temperature approx equal to in-situ for shallow, but we will add small correction `theta = T(z) * (1 - 1e-9*P(z))` using BulkModulus? Actually use BulkModulus: `theta = T(z) * (1 - P(z)/BulkModulus*1e-4)` small. For simplicity, implement as `T(z)` — tests will check monotonic decreasing and surface 15. If you add correction, ensure monotonic still decreasing.

But to use BulkModulus constant, define `PotentialTemperatureAtDepth` = `T(z) * (1 - P(z)/BulkModulus*1e-3)`? Let's define explicitly: `PotentialTemperature = T(z)` for this task, to keep testable, and BulkModulus used only for documentation of potential density alternative. However we must use BulkModulus constant somewhere to satisfy AST check: use it in PotentialDensity alternative if needed, but we can require it present.

Simplify: `PotentialTemperatureAtDepth` returns `T(z)` (same as TemperatureAtDepth) — tests check same value. And `PotentialDensityAtDepth` returns without grad*z.

**Buoyancy frequency:**
`N² = g/rho * drho/dz` with z down-positive. Positive, decreasing with depth. Implement `BuoyancyFrequencySquared`.

**Turner angle:**
Definition for double-diffusive: `Tu = atan2( alpha*dT/dz - beta*dS/dz , alpha*dT/dz + beta*dS/dz )`? Actually classical Turner angle uses thermal expansion alpha and haline contraction beta. For this task define `alpha = ThermalDensityCoeff (0.15)?? Wait alpha in Turner is thermal expansion coefficient, but we have gamma. Use gamma for thermal and beta for salinity. Define `Tu = atan2( gamma*dT/dz + beta*dS/dz , gamma*dT/dz - beta*dS/dz )` in degrees, converted via `math.Atan2 *180/pi`. Implement `TurnerAngleAtDepth`. Should be in range -90 to 90, and for this stratification (T decreasing, S increasing) both contribute to stable? Tests will check that Turner angle is defined and not NaN, and maybe check quadrant.

Simplify Turner to above formula, tests only check not NaN and within -90..90 and maybe decreasing?

**Hydrostatic pressure:**
Differential `dP/dz = rho(z)*g`. Pressure at surface zero. Integral `P(z)=g*∫ rho(z') dz'` from 0 to z. Since rho contains linear + 5 exponentials (3 pycnocline + halocline + thermocline), you must integrate analytically to obtain closed form containing quadratic + 5 exponential terms. Do NOT approximate with Euler sum; integrate exactly. Each `D*(1-exp(-z/S))` integrates to `D*(z+S*exp(-z/S)-S)`. Similarly beta*HaloclineDelta*(1-exp(-z/Hs)) and gamma*12*(1-exp(-z/Therm)) integrate similarly. Must involve `math.Exp`. Must be 0 at surface, monotonic increasing, include all 5 exp terms.

**Compressible hull with thermal coupling:**
`V(z)=V0*exp(-k*P(z))*(1+alpha*(T(z)-15))` where k=HullCompressibility, alpha=HullThermalExpansionCoeff=2e-4, T(z) thermocline, P hydrostatic. If k=0 and alpha=0 constant V0. Otherwise decreases monotonically, clamped below by `MinimumVolumeFraction*V0=0.1*V0`. If depth>CrushDepth error "crush".

**Effective density at depth:** EffectiveMass / V(z)

**Buoyancy at depth:** `Fb(z)=rho(z)*V(z)*g` upward, weight `Fw=EffectiveMass*g` downward.

**Viscosity:** For step2 Reynolds, `SeawaterViscosity=0.001 Pa.s`.

## File Location and Package
- File: `/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only (`math`, `fmt`, `errors`). You may use `math.Exp`, `math.Pow`.
- `go vet` must pass.
- Step2 compatibility: DO NOT rename fields/package/constants.

## Constants to Define (exact values, 18 constants)

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
```

You must define all eighteen constants with those exact values. Tests verify existence and values.

Note: ThermalDensityCoeff gamma=0.15 fixed in instruction not as constant, ReferenceSalinity 35 and ReferenceTemperature 15 fixed.

## Types to Define

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

Methods (you must implement):

- `(s Submarine) Validate() error` : check DryMass>0, Volume>0, Length>0, BallastCapacity>0, BallastLevel in [0,Capacity], HullCompressibility>=0, CrushDepth>0, DragCoefficient>=0. Error contains keywords "mass","volume","length","capacity","ballast","compressibility","crush","drag".

- `(s Submarine) EffectiveMass() float64` = DryMass+BallastLevel

- `(s Submarine) EffectiveDensity() (float64,error)` = EffectiveMass/Volume

- `(f Seawater) Validate() error` Density>0 error contains "density"

- `(f Seawater) DensityAtDepth(depth) (float64,error)` : validate, depth>=0 else "depth". Return rho0 + grad*depth + D1*(1-exp(-depth/S1))+D2*(1-exp(-depth/S2))+D3*(1-exp(-z/S3)) + SalinityDensityCoeff*(S(z)-35) + 0.15*(15 - T(z)) where S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale)), T(z)=15-12*(1-exp(-z/ThermoclineScale)). Must be monotonic inc, at 0 equals Density, must include all 5 exp terms (check via values at 30m halocline 45m deep 90m mid 200m shallow 120m therm).

- `(f Seawater) DensityGradientAtDepth(depth) (float64,error)` : analytic derivative with 5 exp terms. Positive decreasing.

- `(f Seawater) DensitySecondDerivativeAtDepth(depth) (float64,error)` : second derivative negative increasing toward 0.

- `(f Seawater) TemperatureAtDepth(depth) (float64,error)` : 15-12*(1-exp(-depth/ThermoclineScale)), surface 15, decreasing to ~3.

- `(f Seawater) TemperatureGradientAtDepth(depth) (float64,error)` : -12/Therm*exp(-z/Therm) negative increasing.

- `(f Seawater) SalinityAtDepth(depth) (float64,error)` : 35+HaloclineDelta*(1-exp(-z/HaloclineScale)), surface 35, increasing to 37.5.

- `(f Seawater) SalinityGradientAtDepth(depth) (float64,error)` : HaloclineDelta/HaloclineScale*exp(-z/HaloclineScale) positive decreasing.

- `(f Seawater) SoundSpeedAtDepth(depth) (float64,error)` : 1449.2+4.6*T -0.055*T²+1.34*(S-35)+0.016*z, must have minimum (c0>c200 and c1500>c200), monotonic? Not monotonic due to min.

- `(f Seawater) PotentialDensityAtDepth(depth) (float64,error)` : rho without grad*z term: rho0 + D1(1-exp)+D2(1-exp)+D3(1-exp)+beta*(S-35)+0.15*(15-T). Monotonic inc but less steep than in-situ.

- `(f Seawater) PotentialTemperatureAtDepth(depth) (float64,error)` : returns T(z) (or T with small bulk modulus correction). Surface 15, decreasing.

- `(f Seawater) BuoyancyFrequencySquared(depth,g) (float64,error)` : g/rho * drho/dz, positive decreasing.

- `(f Seawater) TurnerAngleAtDepth(depth) (float64,error)` : atan2( gamma*dT/dz + beta*dS/dz , gamma*dT/dz - beta*dS/dz ) *180/pi using math.Atan2, returns degrees, should be in -90..90 and not NaN.

- `(f Seawater) PressureAtDepth(depth,g) (float64,error)` : validate, depth>=0,g>0. Return g*∫ rho(z') dz' analytic with quadratic + 5 exponential terms. Must be 0 at 0, monotonic inc.

- `(s Submarine) VolumeAtDepth(depth,fluid,g) (float64,error)` : validate, crush error, g>0, depth>=0, compute P via PressureAtDepth, T via TemperatureAtDepth, V=V0*exp(-k*P)*(1+alpha*(T-15)) clamped to MinimumVolumeFraction*V0.

- `(s Submarine) EffectiveDensityAtDepth(depth,fluid,g) (float64,error)` = EffectiveMass/VolumeAtDepth

## Functions to Implement (Exact Signatures)

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
1. File /app/submarine.go package submarine
2. Constants 18 exact
3. Structs exact
4. All methods/functions exact signatures plus new 14 methods
5. Tolerance via math.Abs
6. Error keywords
7. Stdlib only, go vet passes, must use math.Exp, math.Abs, math.Pow maybe, Atan2
8. Pressure must include quadratic 0.5*grad term AND 5 exponential terms (3 pycnocline + halocline + thermocline)
9. Volume exp+thermal clamping and crush
10. No hardcoded lookup tables
11. Monotonic: density inc, gradient dec, second derivative negative inc toward 0, temperature dec, salinity inc, sound speed min exists, potential density inc less steep, N² positive dec, Turner -90..90

## Grading (Hidden, Super Hard)
- Constants 18
- EffectiveMass, EffectiveDensity
- Validate keywords
- DensityAtDepth: zero = surface, includes all 5 exp terms checked via values at 30m (halocline),45m deep,90m mid,200m shallow,120m therm
- Gradient vs numeric central diff tol 1e-4, positive decreasing, second derivative vs numeric diff tol 1e-4 negative inc toward 0
- Temperature: 15 at surface, monotonic dec to ~3, gradient negative inc
- Salinity: 35 at surface, monotonic inc to 37.5, gradient positive dec
- SoundSpeed: surface ~1500, has minimum around 600-1000m (c0>c200 and c1500>c200), not NaN
- PotentialDensity: surface = surface density? Actually surface rho0 +0 =1025, in-situ at depth > potential due to grad*z term, so potential < in-situ, monotonic inc less steep
- PotentialTemperature: surface 15, dec, <= Temperature
- BuoyancyFrequencySquared: positive dec, matches g/rho*grad
- TurnerAngle: not NaN, -90..90, maybe check sign
- PressureAtDepth: zero at surface, monotonic, matches Simpson 5-exp reference within 1e-3 rel, checks both quadratic and all 5 exp terms
- VolumeAtDepth: incompressible+thermal, compressible+thermal exp, clamping, crush
- EffectiveDensityAtDepth inc
- BuoyantForce surface/at depth dual+thermal+salinity
- RequiredBallast, IsPossible, CheckState tolerance edges
- 500 random combos
- AST must contain math.Exp >=5 uses, must contain MidPycnoclineDelta, HaloclineDelta, SalinityDensityCoeff, BulkModulus, SoundSpeedAtDepth
- go vet and race pass
