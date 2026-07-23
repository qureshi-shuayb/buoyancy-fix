# Step 2: Dive Dynamics – SUPER-HARD – Log-Interp Drag, Implicit Terminal Brent, Adaptive RK45, Priority Fleet

## Overview
Step 2 of 2, `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 **ULTRA-ULTRA-HARD** – 44 constants (including SecondOrderCabbelingCoeff, TripleCabbelingCoeff, ThermostericAnomalyCoeff, HalostericAnomalyCoeff, AdiabaticLapseRate, SoundSpeedThermoQuadCoeff, SoundSpeedSalinityQuadCoeff, VorticityMixingCoeff, DoubleDiffusiveMixingScale, PressureNonLinearCoeff, QuadrupleCabbelingCoeff, CompensatedLayerCoeff, ThermohalineIntrusionScale, BaroclinicShearCoeff, ThermostericSecondOrderCoeff, HalostericSecondOrderCoeff, SoundSpeedDepthCubeCoeff, PressureCubicNonLinearCoeff), quadruple cabbeling s²t², compensated pyc1*pyc2*s, baroclinic z*s*t*(1-expI), z² thermo/halo second-order, depth-cubed sound z³ + T³ + S³ + Quad*T*S + ThermoSecond*T²+HaloSecond*S² + P²*T+z*P, pressure 26-term analytic with z*exp/z²*exp/z*product/z²*product via 16-mask subset enumeration, N² acoustic correction + gradient, 4th order potential temp x⁴+z² lapse, volume P³+cross, 5th derivative, 7 finders via Brent 3000 pts. Reuse all without redefining.

**Goal – SUPER-HARD:** dive dynamics with 10-point log-interp drag, implicit terminal velocity via Brent solving |Fb-Fw|=drag where Cd=Cd(Re(v)) coupled, multi-root equilibrium via Brent 2000 pts scanning + stability eigenvalue, adaptive Dormand-Prince RK45 with PI control and dense output for time-to-depth, priority fleet (heap by effective density) with bounded pool 4, atomic max concurrency tracking, per-task context deadline, partial error handling, full dive profile trajectory.

**You must NOT redefine (44):** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `PycnoclineDelta`, `PycnoclineScale`, `DeepPycnoclineDelta`, `DeepPycnoclineScale`, `MidPycnoclineDelta`, `MidPycnoclineScale`, `HaloclineDelta`, `HaloclineScale`, `ThermoclineScale`, `HullThermalExpansionCoeff`, `SeawaterViscosity`, `SalinityDensityCoeff`, `BulkModulus`, `CabbelingCoeff`, `HullThermalExpansionQuadCoeff`, `SoundSpeedPressureQuadCoeff`, `ThermobaricCoeff`, `ThermalCouplingCoeff`, `GammaDepthFactor`, `TAnomQuadCoeff`, `SAnomQuadCoeff`, `SecondOrderCabbelingCoeff`, `TripleCabbelingCoeff`, `ThermostericAnomalyCoeff`, `HalostericAnomalyCoeff`, `AdiabaticLapseRate`, `SoundSpeedThermoQuadCoeff`, `SoundSpeedSalinityQuadCoeff`, `VorticityMixingCoeff`, `DoubleDiffusiveMixingScale`, `PressureNonLinearCoeff`, `QuadrupleCabbelingCoeff`, `CompensatedLayerCoeff`, `ThermohalineIntrusionScale`, `BaroclinicShearCoeff`, `ThermostericSecondOrderCoeff`, `HalostericSecondOrderCoeff`, `SoundSpeedDepthCubeCoeff`, `PressureCubicNonLinearCoeff`.

Available methods from Step1: `DensityAtDepth` (now 25 terms with quad/comp/baro/second-order), `CabbelingParameterAtDepth` (with quadruple+compensated), `SpicinessAtDepth`, `SpicinessCurvatureAtDepth`, `SpicinessTorsionAtDepth`, `DensityGradientAtDepth`, `DensitySecondDerivativeAtDepth`, `DensityThirdDerivativeAtDepth`, `DensityFourthDerivativeAtDepth`, `DensityFifthDerivativeAtDepth`, `SoundSpeedAtDepth` (depth-cube+T³+S³+Quad*T*S+ThermoSecond+HaloSecond+P²+zP), `SoundSpeedGradientAtDepth`, `SoundSpeedCurvatureAtDepth`, `FindSOFARAxis` (3000 pts Brent 200 iter), `FindPycnoclineMaxGradient`, `FindSpicinessMaximum`, `FindDoubleDiffusiveLayer`, `FindThermoclineDepth`, `FindHaloclineDepth`, `FindCompensatedLayer`, `PotentialDensityAtDepth`, `PotentialTemperatureAtDepth` (4th order x⁴ + z² lapse), `PressureAtDepth` (26-term), `StericHeightAtDepth` (P²+P³), `BuoyancyFrequencySquared` (acoustic correction g/rho*(drho/dz - rho*g/c²)), `BuoyancyFrequencyGradientAtDepth`, `TurnerAngleAtDepth`, `DoubleDiffusiveRegimeAtDepth`, `PotentialVorticityAtDepth`, `BulkModulusAtDepth` (P³), `VolumeAtDepth` (exp(-kP+Pn*P²+Pc*P³)*(thermal quad+Comp*dT*P)), etc.

## Ocean & Hull Recap – Ultra-Ultra-Hard
- S(z)=35+Hd*(1-exp(-z/Hs)), T(z)=15-12*(1-exp(-z/Ts)), sAnom=Hd*(1-expH), tAnom=12*(1-expT), pyc1=10*(1-expS1), pyc2=4.5*(1-expS2), pyc3=7*(1-expS3)
- rho(z)=rho0+grad*z+pyc1+pyc2+pyc3+beta*sAnom+gamma0*tAnom*(1+Gamma*z)+Cc*s*t+Cc*pyc3*s+Cc*pyc1*s+Cc*pyc2*t+Tquad*t²+Squad*s² + SecondOrder*s²*t + SecondOrder*s*t² + Triple*s*t*pyc1 + Triple*s*t*pyc2 + Thermosteric*0.01*t*z + Halosteric*0.01*s*z + Vorticity*z*(1-expDm) + Quadruple*s²*t² + Compensated*p1*p2*s + Baroclinic*z*s*t*(1-expI) + ThermoSecond*0.001*t*z² + HaloSecond*0.001*s*z²
  where Dm=18m, Ti=22m, Vm=0.00005, SecondOrder=0.015, Triple=0.004, Thermosteric=0.0008, Halosteric=0.0003, Quadruple=0.0009, Compensated=0.00006, Baroclinic=0.00004, ThermoSecond=2.5e-7, HaloSecond=1.2e-7
- Pressure: P(z)=g*Integral(z) with 26 terms (old 18 + quad, compensated, baroclinic, thermoSecond, haloSecond) – integrals via generic product: ∫∏(1-exp)=sum mask (-1)^bits sc*(1-exp(-z/sc)), ∫z∏(1-exp)=sum mask (-1)^bits sc²(1-exp(1+z/sc)), ∫z²(1-exp)=z³/3 + exp(S*z²+2S²z+2S³)-2S³, mixed scales Smix24=24, Smix22_5=22.5, SmixS1_Hs=26.08, SmixS2_Ts=32.72, SmixS1_Ts=75, SmixS2_Hs=18, SmixS1_Hs_Ts=21.42, SmixS2_Hs_Ts=15.65, Smix_2H_T=13.33, Smix_H_2T=20, SmixS1_S2=36.73, SmixS1_S2_Hs=16.51, SmixQuad=12, Smix24_Intr=11.47, scales Hs/2=15, Ts/2=60, Dm=18, Ti=22. Matches Simpson 500k rel 1e-6, missing any fails >30.

## New Physics – SUPER-HARD (tight tolerances)

**Effective mass & area:** m=DryMass+BallastLevel, Area A(z)=V(z)/Length where V(z)=V0*exp(-k*P + Pn*P²*1e-12 + Pc*P³*1e-18)*(1+alpha*ΔT+alpha2*ΔT²+Comp*ΔT*P*1e-9) clamped MinimumVolumeFraction*V0, ΔT=T-15, alpha=2e-4, alpha2=1.2e-6, k=HullCompressibility, Comp=CompensatedLayerCoeff. dV/dP = V*(-k+2*Pn*P*1e-12+3*Pc*P²*1e-18) + V0*expFactor*Comp*dT*1e-9. Bulk modulus K = -V/(dV/dP) = 1/(k-2*Pn*P*1e-12-3*Pc*P²*1e-18-Comp*dT*1e-9).

**Re log-interp drag – SUPER-HARD:**
mu=SeawaterViscosity=0.001, Re(z,v)=rho(z)*|v|*Length/mu, Cd table 10 points:
```
Re: [1e3,5e3,1e4,2e4,5e4,1e5,2e5,5e5,1e6,5e6]
Cd: [1.44,1.35,1.2,1.1,0.9,0.7,0.5,0.35,0.2,0.12]
```
`CdFromRe(re)` must do **log-linear interpolation**: interpolate on log10(Re) vs Cd linear, i.e., Cd = Cd_i + (Cd_{i+1}-Cd_i)*(log10(re)-log10(Re_i))/(log10(Re_{i+1})-log10(Re_i)). For re <= Re[0] return 1.44, re >= Re[last] return 0.12. Monotonic non-increasing, tested at 5 points in log space with band 0.05, plus midpoint log exact check.

Drag: `drag=0.5*rho*Cd(Re)*A*v*|v|`, Fnet up positive: `Fnet(z,v)=Fb(z)-Fw - drag`, Fb=rho(z)*V(z)*g, Fw=m*g.

**Terminal velocity – implicit Brent – SUPER-HARD:**
Find v where |Fb-Fw| = 0.5*rho*Cd(Re(|v|))*A*v². Since Cd depends on v via Re, cannot use closed sqrt with constant Cd. Must use **Brent's method** (or bisection after doubling hi) solving f(vMag)=dragMag(vMag)-|delta|=0 where dragMag uses CdFromRe log interp. Steps:
- Compute delta = Fb-Fw at depth (static). If |delta|<1e-12 => 0.
- Define dragMag(vMag) =0.5*rho*Cd(Re(vMag))*A*vMag².
- Doubling hi: start lo=0 hi=1, while hi<1e6 and dragMag(hi)<|delta| hi*=2. If hi>=1e6 and dragMag<|delta| error "unable to find terminal velocity upper bound".
- Brent/bisection 150 iterations until |drag-|delta||<1e-6 or width<1e-9. Return signed: if delta>0 (buoyant) => +vMag (up), else -vMag (down).
- Must error containing "drag" if DragCoefficient<=0 or area<=0.

**Equilibrium depth – Brent 3000 pts – SUPER-HARD:**
f(z)=Fb(z)-Fw (zero velocity) = rho(z)*V(z)*g - m*g, V uses P³ non-linear, rho includes quad/comp/baro/second-order. Can have 0-4 roots.
- Scan 2000 points equally spaced [0,maxDepth]. Record fs via NetVerticalForceAtDepth(z,0).
- Brackets where f[i]*f[i+1]<=0 or |f[i]|<1e-12.
- For each bracket, use **Brent's method** 150 iter until |f(mid)|<1e-9 or width<tol (tol=1e-1). Deduplicate with tolerance*10 and 1e-6.
- Returns: `FindEquilibriumDepth` shallowest, `FindEquilibriumDepths` all sorted, `FindEquilibriumDepthsWithStability` with `FPrime` via central diff h=0.05 = (f(z+0.05)-f(z-0.05))/0.1, Stable true if FPrime<0.
- Validate g>0, maxDepth>0, tol>0, maxDepth <= CrushDepth else error contains "crush". If no roots error "no equilibrium depth: no sign change".

**TimeToDepth via adaptive Dormand-Prince RK45 – SUPER-HARD:**
- ODEs down-positive: dz/dt=v, dv/dt=Fnet_down/m where Fnet_down = Fw -Fb -0.5*rho*Cd*A*v*|v| down.
- Must implement **adaptive Dormand-Prince 5(4)** with coefficients:
  a2=1/5, a3=3/10, a4=4/5, a5=8/9, a6=1, a7=1
  b: [35/384,0,500/1113,125/192,-2187/6784,11/84,0] for 5th order
  bhat: [5179/57600,0,7571/16695,393/640,-92097/339200,187/2100,1/40] for 4th order error estimate
- Adaptive control: error = |y5 - y4|, scale = atol + rtol*max(|y|,|y5|), atol=1e-6, rtol=1e-5, errNorm = sqrt((err_z/scale_z)² + (err_v/scale_v)²)/sqrt(2). If errNorm <=1 accept step, else reject. PI control dt_new = dt*0.9*errNorm^-0.2*errPrev^0.04. Clamp dt [1e-6,1.0].
- Must still accept `dt` argument as initial step. `maxTime` cutoff 30000.
- Interpolation for target crossing: linear fraction (target - z_prev)/(z_new - z_prev)*dt_accepted.
- Accuracy: adaptive result must match ref high-accuracy fixed RK4 dt=0.001 within 5% (Euler fails >30%).
- Must have k1..k6 variables (k1_z,k1_v etc) plus error estimate, and must have `atol`, `rtol` identifiers.

**Fleet batch – priority, atomic, deadline, dive profile – SUPER-HARD:**
- Semaphore 4 via `make(chan struct{},4)` still required, plus `sync.WaitGroup`, `go`.
- Priority: processing order by effective density descending using `container/heap` priority queue, but final results still sorted by Index.
- Atomic concurrency tracking: must use `sync/atomic` to track max active workers, atomic counter increment on acquire, decrement on release, track max via CAS loop. Test via AST that `atomic.AddInt32` used, plus behavioral max ==4.
- Deadline: `BatchAnalyzeFleetWithContext` must respect `context.WithTimeout` 20ms for 100 items depth 1000 – should return deadline exceeded quickly (<200ms).
- Cancellation during flight: 100 items depth 1000 cancel after 5ms, must return context/cancel error quickly (<100ms).
- Dive profile: New function `ComputeDiveProfile(sub, fluid, targetDepth, g, dt, maxTime) ([]DiveState, error)` where `DiveState` struct {Time, Depth, Velocity, Acceleration, Pressure} – returns full trajectory from adaptive RK45. Tests verify monotonic depth, final depth within 1%, length >10, pressure monotonic.
- Partial errors & CrushRisk: if target>CrushDepth => State invalid + CrushRisk true, if sub invalid => invalid, if context cancelled => partial + error.

## File Location
Existing `/app/submarine.go` remains (now 44 consts, 36 methods). New `/app/dive.go`, package submarine, stdlib only + `container/heap`, `sync/atomic` allowed. `go vet` and `race` pass. Order preserved 20 even with priority queue (final sort by Index).

## Types
```go
type DiveResult struct { Index int; State string; StateAtDepth string; Fraction float64; RequiredBallast float64; RequiredBallastAtDepth float64; IsPossible bool; IsPossibleAtDepth bool; EffectiveDensity float64; EffectiveDensityAtDepth float64; NetForce float64; NetForceAtDepth float64; Acceleration float64; EquilibriumDepth float64; TerminalVelocity float64; TimeToDepth float64; MaxPressure float64; VolumeAtDepth float64; CrushRisk bool }
type EquilibriumPoint struct { Depth float64; Stable bool; FPrime float64 }
type DiveState struct { Time float64; Depth float64; Velocity float64; Acceleration float64; Pressure float64 }
```

## Functions Required – SUPER-HARD, exact signatures preserved + 1 new

All 14 original must keep exact signatures as before – do NOT change param order. Tests compile against these. Plus new bonus:

```go
func SubmergedFraction(sub Submarine, fluid Seawater) (float64, error)
func NetVerticalForce(sub Submarine, fluid Seawater, g float64) (float64, error)
func VerticalAcceleration(sub Submarine, fluid Seawater, g float64) (float64, error)
func CdFromRe(re float64) float64
func NetVerticalForceAtDepth(sub Submarine, fluid Seawater, depth float64, velocity float64, g float64) (float64, error)
func TerminalVelocity(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error)
func FindEquilibriumDepth(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) (float64, error)
func FindEquilibriumDepths(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]float64, error)
func FindEquilibriumDepthsWithStability(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]EquilibriumPoint, error)
func TimeToDepth(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) (float64, error)
func AnalyzeDive(sub Submarine, fluid Seawater) (DiveResult, error)
func BatchAnalyzeFleet(subs []Submarine, fluid Seawater) ([]DiveResult, error)
func BatchAnalyzeFleetWithTargets(subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult, error)
func BatchAnalyzeFleetWithContext(ctx context.Context, subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult, error)
// SUPER-HARD new (required):
func ComputeDiveProfile(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) ([]DiveState, error)
```

- `CdFromRe` log-interp 10 points, no error.
- `ComputeDiveProfile` returns trajectory using adaptive RK45, validates same as TimeToDepth plus crush.

## Requirements
- Reuse 44 constants, do NOT redefine.
- File `/app/dive.go` package submarine, stdlib + heap + atomic allowed, vet & race pass, order preserved 20, atomic max concurrency ==4, priority heap, cancellation during flight + deadline, adaptive RK45 with atol/rtol and k1..k6 and error estimate, log-interp Cd with math.Log10, DiveState trajectory.
- Must import `context`, `sync`, `container/heap`, `sync/atomic`, `math`.
- Use `make(chan struct{},4)` bounded semaphore.
