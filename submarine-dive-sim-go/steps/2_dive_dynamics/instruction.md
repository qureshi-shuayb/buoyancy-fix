# Step 2: Dive Dynamics – MEDIUM-HARD – Log-Interp Drag, Implicit Terminal, Fixed RK4 + Optional Adaptive, Priority Fleet

## Overview
Step 2 of 2, `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 **EASY-MEDIUM** – 24 constants (PycnoclineDelta/Scale 10/200, Deep 4.5/45, Halo 2.5/30, Thermo 120, HullExp 2e-4, Viscosity 0.001, SalinityCoeff 0.8, Bulk 2.2e9, Cab 0.06, HullQuad 1.2e-6, SoundQuad 1.2e-5, Thermobaric 0.5, ThermalCoupling 0.15, Gamma 0.0001, Tquad 0.002, Squad 0.01), 9-term density, 10-term pressure via single + 2-scale product, derivatives up to 2nd only, sound 5 terms without P coupling, potential temp 2nd order x², 2 finders via 1000 pts Brent 80 iter. Reuse all without redefining.

**Goal – MEDIUM-HARD (eased from HARD):** dive dynamics with 10-point log-interp drag (looser band), implicit terminal velocity via Brent solving |Fb-Fw|=drag where Cd=Cd(Re(v)), multi-root equilibrium via 1000 pts scanning + stability, dive integration via **fixed RK4 with optional adaptive Dormand-Prince** (atol/rtol + error estimate still required but reference comparison looser), priority fleet (heap by effective density) with bounded pool 4, atomic max concurrency tracking accepting **any atomic width/style** (Int32, Int64, Uint32/64, typed `atomic.Int32/Int64`), per-task context deadline with generous timeouts, partial error handling, dive profile.

**You must NOT redefine (24):** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `PycnoclineDelta`, `PycnoclineScale`, `DeepPycnoclineDelta`, `DeepPycnoclineScale`, `HaloclineDelta`, `HaloclineScale`, `ThermoclineScale`, `HullThermalExpansionCoeff`, `SeawaterViscosity`, `SalinityDensityCoeff`, `BulkModulus`, `CabbelingCoeff`, `HullThermalExpansionQuadCoeff`, `SoundSpeedPressureQuadCoeff`, `ThermobaricCoeff`, `ThermalCouplingCoeff`, `GammaDepthFactor`, `TAnomQuadCoeff`, `SAnomQuadCoeff`.

Available methods from Step1: `DensityAtDepth` (9 terms), `CabbelingParameterAtDepth` (3 terms), `SpicinessAtDepth`, `DensityGradientAtDepth`, `DensitySecondDerivativeAtDepth`, `SoundSpeedAtDepth` (5 terms), `SoundSpeedGradientAtDepth`, `FindSOFARAxis` (1000 pts 80 iter), `FindPycnoclineMaxGradient`, `PotentialDensityAtDepth`, `PotentialTemperatureAtDepth` (2nd order), `PressureAtDepth` (10-term), `StericHeightAtDepth` (simple), `BuoyancyFrequencySquared`, `PotentialVorticityAtDepth`, `VolumeAtDepth` (simple), `BulkModulusAtDepth` (simple), etc.

## Ocean & Hull Recap – EASY-MEDIUM
- S(z)=35+Hd*(1-exp(-z/Hs)), T(z)=15-12*(1-exp(-z/Ts)), sAnom=Hd*(1-expH), tAnom=12*(1-expT), pyc1=10*(1-expS1), pyc2=4.5*(1-expS2)
- rho(z)=rho0+grad*z+pyc1+pyc2+beta*sAnom+gamma0*tAnom*(1+Gamma*z)+Cc*s*t+Tquad*t²+Squad*s²
- Pressure: P(z)=g*Integral(z) with 10 terms – integrals via `∫(1-exp)=z+S*exp-S`, `∫(1-expH)(1-expT)=z - S1(1-expS1)-S2(1-expS2)+Smix(1-expMix)`, `∫(1-exp)²`, `∫z(1-exp)`. Matches Simpson 100k rel 1e-4.
- Sound: c=1449.2+4.6T-0.055T²+1.34(S-35)+0.016z+SSq*z², gradient 4.6dT-0.11TdT+1.34dS+0.016+2SSq z.

## New Physics – MEDIUM-HARD (eased tolerances)

**Effective mass & area:** m=DryMass+BallastLevel, Area A(z)=V(z)/Length where V(z)=V0*exp(-k*P)*(1+alpha*ΔT+alpha2*ΔT²) clamped MinimumVolumeFraction*V0, ΔT=T-15, alpha=2e-4, alpha2=1.2e-6, k=HullCompressibility. Bulk K=1/k.

**Re log-interp drag – MEDIUM-HARD (eased band):**
mu=0.001, Re=rho*|v|*Length/mu, Cd table 10 points same:
```
Re: [1e3,5e3,1e4,2e4,5e4,1e5,2e5,5e5,1e6,5e6]
Cd: [1.44,1.35,1.2,1.1,0.9,0.7,0.5,0.35,0.2,0.12]
```
`CdFromRe(re)` must do log-linear interpolation on log10(Re). For re <=1e3 return 1.44, re>=5e6 return 0.12. Monotonic non-increasing, tested at 5 points with band **0.1** (was 0.05), midpoint log exact check tol **0.05** (was 0.02).

Drag: `drag=0.5*rho*Cd(Re)*A*v*|v|`, Fnet up positive: `Fnet(z,v)=Fb(z)-Fw - drag`, Fb=rho(z)*V(z)*g, Fw=m*g.

**Terminal velocity – implicit Brent – MEDIUM-HARD (eased iter):**
Find v where |Fb-Fw| = 0.5*rho*Cd(Re(|v|))*A*v². Cd depends on v.
- delta = Fb-Fw at depth, |delta|<1e-12 =>0
- dragMag(vMag)=0.5*rho*Cd(Re(vMag))*A*vMag²
- Doubling hi: lo=0 hi=1 while hi<1e6 and dragMag(hi)<|delta| hi*=2. If hi>=1e6 and dragMag<|delta| error "unable to find terminal velocity upper bound".
- Brent/bisection **80 iterations** (was 150) until |drag-|delta||<1e-3 or width<1e-6. Signed: delta>0 => +vMag else -vMag.
- Must error containing "drag" if DragCoefficient<=0 or area<=0.

**Equilibrium depth – Brent 1000 pts – MEDIUM-HARD (eased):**
f(z)=Fb(z)-Fw zero velocity.
- Scan **1000 points** (was 2000) equally spaced [0,maxDepth], fs via NetVerticalForceAtDepth(z,0)
- Brackets where f[i]*f[i+1]<=0 or |f[i]|<1e-12
- For each bracket, Brent **80 iter** (was 150) until |f(mid)|<1e-6 or width<tol (tol=1e-1). Dedup tolerance*10 and 1e-6.
- Returns: `FindEquilibriumDepth` shallowest, `FindEquilibriumDepths` all sorted, `FindEquilibriumDepthsWithStability` with FPrime via central diff h=0.05, Stable if FPrime<0
- Validate g>0, maxDepth>0, tol>0, maxDepth <= CrushDepth else "crush". No roots → "no equilibrium depth: no sign change".

**TimeToDepth – fixed RK4 + optional adaptive RK45 – MEDIUM-HARD (eased):**
- ODEs down-positive: dz/dt=v, dv/dt=Fnet_down/m where Fnet_down=Fw-Fb-0.5*rho*Cd*A*v*|v|
- Must implement **fixed RK4** as baseline (k1..k4) – passes if adaptive not perfect. If implements adaptive Dormand-Prince 5(4) with atol=1e-6 rtol=1e-5 PI control, also accepted. Must have k1..k4 identifiers, and if adaptive, atol/rtol/errorEstimate/errNorm.
- Accuracy: adaptive or fixed result must match **independent reference RK4 dt=0.001** within **15%** (was 8%). Euler fails >30%.
- Interpolation for target crossing linear fraction.

**Fleet batch – priority, atomic (any width), deadline, dive profile – MEDIUM-HARD (eased):**
- Semaphore 4 via `make(chan struct{},4)` + `sync.WaitGroup` + `go` required.
- Priority: processing by effective density descending using `container/heap` priority queue, but final results sorted by Index. Test verifies heap import and final ordering plus that heavy subs are prioritized internally via checking heap Less descending (behavioral).
- Atomic concurrency tracking: **must use `sync/atomic` but accepts any valid style**: `AddInt32/LoadInt32/CompareAndSwapInt32` **OR** `AddInt64/LoadInt64`, `AddUint32/64`, `Store`, `Swap`, **OR typed** `atomic.Int32`, `atomic.Int64`, `atomic.Uint32`, `atomic.Uint64` with `Add/Load/Store/CompareAndSwap`. Grader no longer requires `Int32` specifically. Behavioral: with 20 items max concurrency <=4 and >0, batch time < sum serial.
- Deadline: `BatchAnalyzeFleetWithContext` must respect `context.WithTimeout` – tests now use **200ms timeout for 100 items** (was 20ms) with lenient fallback that logs on fast machines, not strict fail.
- Cancellation during flight: 100 items depth 1000 cancel after **100ms** (was 5ms) → 10ms retry fallback.
- Dive profile: `ComputeDiveProfile` returns trajectory, checks monotonic depth/time, final depth within **2%** (was 1%), length >5 (was 10), pressure monotonic.
- Partial errors & CrushRisk: target>CrushDepth => invalid + CrushRisk true, invalid sub => invalid.

## File Location
Existing `/app/submarine.go` remains (now 24 consts, 20 methods). New `/app/dive.go`, package submarine, stdlib + `container/heap`, `sync/atomic` allowed. `go vet` and `race` pass. Order preserved 20 even with priority queue (final sort by Index). Verifier-generated files `/app/*_test.go`, `/app/ast_check*.go` are removed before and after verifier to prevent R05 leak.

## Types
```go
type DiveResult struct { Index int; State string; StateAtDepth string; Fraction float64; RequiredBallast float64; RequiredBallastAtDepth float64; IsPossible bool; IsPossibleAtDepth bool; EffectiveDensity float64; EffectiveDensityAtDepth float64; NetForce float64; NetForceAtDepth float64; Acceleration float64; EquilibriumDepth float64; TerminalVelocity float64; TimeToDepth float64; MaxPressure float64; VolumeAtDepth float64; CrushRisk bool }
type EquilibriumPoint struct { Depth float64; Stable bool; FPrime float64 }
type DiveState struct { Time float64; Depth float64; Velocity float64; Acceleration float64; Pressure float64 }
```

## Functions Required – MEDIUM-HARD
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
func ComputeDiveProfile(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) ([]DiveState, error)
```

## Requirements
- Reuse 24 constants, do NOT redefine.
- File `/app/dive.go` package submarine, stdlib + heap + atomic allowed, vet & race pass, order preserved 20, atomic max concurrency <=4 (any width Int32/Int64/Uint/typed atomic accepted), priority heap, cancellation 100ms/100items (lenient), deadline 200ms/100items (lenient), fixed RK4 (k1..k4) + optional adaptive with atol/rtol/errorEstimate, log-interp Cd with math.Log10, DiveState trajectory len>5 tol 2%.
- Must import `context`, `sync`, `container/heap`, `sync/atomic`, `math`.
- Use `make(chan struct{},4)` bounded semaphore.
- Must NOT leak verifier files: test.sh removes `/app/*_test.go` before and after verification.

## R05 R08 Fix Notes
- Verifier-generated files are removed before and after each step to prevent information leakage.
- Atomic check accepts any correct sync/atomic usage: AddInt32/64, AddUint32/64, Load/Store/CompareAndSwap, or typed atomic.Int32/Int64/Uint32/Uint64 with Add/Load/Store/CompareAndSwap – per R08 accepts alternatives.
- Max concurrency and priority verified behaviorally (order preserved, batch faster than serial, heap Less descending) not just AST.
