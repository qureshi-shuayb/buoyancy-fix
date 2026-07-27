# Step 2: Dive Dynamics – MEDIUM – 5-pt Drag, 500pts Equilibrium, Fixed RK4, Priority Fleet

## Overview
Step 2 of 2, `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 **EASY** – 15 constants (Tolerance 1e-9, Gravity 9.81, SeawaterDensity 1025, DepthGrad 0.02, MinVol 0.1, PycDelta 10/Scale 200, Halo 2.5/30, ThermoScale 120, HullExp 2e-4, Visc 0.001, SalinityCoeff 0.8, Bulk 2.2e9, ThermalCoupling 0.15), 5-term density, 5-term pressure single-scale only, 1st derivative only, sound 4 terms, pot temp 1st order, 1 finder SOFAR 500pts 50iter. Reuse all without redefining.

**Goal – MEDIUM (eased from MEDIUM-HARD):** 5-pt Cd log-interp, implicit terminal velocity Brent 50 iter loose 1e-2, equilibrium 500 pts 50 iter, dive integration fixed RK4 k1..k4 with optional adaptive, reference comparison 25% looser, priority fleet heap + bounded pool 4 + atomic any width, deadline 500ms/50items lenient, cancellation 200ms/50items lenient, dive profile len>3 tol 5%.

**You must NOT redefine (15):** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `PycnoclineDelta`, `PycnoclineScale`, `HaloclineDelta`, `HaloclineScale`, `ThermoclineScale`, `HullThermalExpansionCoeff`, `SeawaterViscosity`, `SalinityDensityCoeff`, `BulkModulus`, `ThermalCouplingCoeff`.

Available: Density 5-term, Gradient 1st only, Sound 4-term, FindSOFARAxis 500pts 50iter, PotentialDensity, PotentialTemperature 1st order, Pressure 5-term single-scale, Steric simple, Volume simple, etc.

## Ocean & Hull Recap – EASY
- S(z)=35+2.5*(1-exp(-z/30)), T(z)=15-12*(1-exp(-z/120)), sAnom=2.5*(1-expH), tAnom=12*(1-expT), pyc1=10*(1-exp(-z/200))
- rho(z)=rho0+0.02z+pyc1+0.8*s+0.15*t
- Pressure P=g*∫rho dz = g*(rho0*z+0.01z²+10*(z+200*expS1-200)+0.8*2.5*(z+30*expH-30)+0.15*12*(z+120*expT-120)) single-scale only, Simpson 50k rel 1e-3 missing >5.
- Sound c=1449.2+4.6T+1.34(S-35)+0.016z, gradient 4.6dT+1.34dS+0.016.

## New Physics – MEDIUM (eased)

**Effective mass & area:** m=Dry+Ballast, A=V/Length, V=V0*exp(-kP)*(1+alpha*(T-15)) clamped 0.1, alpha=2e-4, K=1/k.

**Re log-interp drag – 5-pt table (eased from 10-pt):**
```
Re: [1e3, 1e4, 1e5, 1e6, 5e6]
Cd: [1.44, 1.2, 0.7, 0.2, 0.12]
```
`CdFromRe(re)` log-linear on log10(Re). re<=1e3 return 1.44, re>=5e6 return 0.12. Band 0.1, midpoint log exact tol 0.05.

Drag `0.5*rho*Cd*A*v*|v|`, Fnet up: `Fb-Fw - drag`

**Terminal – 50 iter 1e-2:**
delta=Fb-Fw, dragMag(vMag)=0.5*rho*Cd(Re(vMag))*A*vMag², doubling hi from 1 while drag<|delta| hi*=2 up to 1e6 else error "unable to find terminal velocity upper bound", Brent/bisect 50 iter until |drag-|delta||<1e-2 or width<1e-5.

**Equilibrium – 500pts 50iter:**
f(z)=Fb(z)-Fw, scan 500 pts [0,maxDepth], brackets sign change, Brent 50 iter until |f|<1e-6 or width<tol, dedup, sorted. Crush check maxDepth>CrushDepth error "crush", no roots "no equilibrium depth".

**TimeToDepth – fixed RK4 k1..k4 (eased):**
down-positive dz/dt=v, dv/dt=Fnet_down/m, Fnet_down=Fw-Fb-0.5*rho*Cd*A*v*|v|
Must have k1_z,k1_v,k2_z,k2_v,k3_z,k3_v,k4_z,k4_v. Optional adaptive with atol/rtol/errorEstimate also accepted. Reference RK4 dt=0.001 comparison **25% rel** (was 15%, was 8%). Interpolation linear.

**Fleet – heap + atomic any width + lenient deadlines:**
- Semaphore 4 `make(chan struct{},4)` + WaitGroup + go required.
- Priority heap by effective density descending via `container/heap`, final results sorted by Index. Behavioral: order preserved 20, heap Less descending.
- Atomic any style: `AddInt32/64, AddUint32/64, Load/Store/CompareAndSwap/Swap` any width, or typed `atomic.Int32/Int64/Uint32/Uint64` with `Add/Load` – per R08 fix.
- Deadline: `BatchAnalyzeFleetWithContext` with **500ms timeout 50 items** (was 200ms/100) lenient fallback: if completes before deadline, log and skip strict fail (fast-machine safe).
- Cancellation: **200ms timeout 50 items** cancel after 100ms? Actually test cancels after 100ms with 50 items, retry 10ms, lenient.
- DiveProfile `ComputeDiveProfile` returns []DiveState trajectory, checks monotonic depth/time, final depth within 5% (was 2%), len>3 (was 5), pressure monotonic.

## File Location
Existing `/app/submarine.go` (15 consts, ~14 methods). New `/app/dive.go`, package submarine, stdlib+heap+atomic, vet+race pass, order preserved. Verifier files removed before/after to prevent R05 leak.

## Types – same as before
```go
type DiveResult struct { Index int; State string; StateAtDepth string; Fraction float64; RequiredBallast float64; RequiredBallastAtDepth float64; IsPossible bool; IsPossibleAtDepth bool; EffectiveDensity float64; EffectiveDensityAtDepth float64; NetForce float64; NetForceAtDepth float64; Acceleration float64; EquilibriumDepth float64; TerminalVelocity float64; TimeToDepth float64; MaxPressure float64; VolumeAtDepth float64; CrushRisk bool }
type EquilibriumPoint struct { Depth float64; Stable bool; FPrime float64 }
type DiveState struct { Time float64; Depth float64; Velocity float64; Acceleration float64; Pressure float64 }
```

## Functions Required – same signatures
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

## Requirements – MEDIUM
- Reuse 15 consts, do NOT redefine.
- dive.go package submarine, stdlib+heap+atomic, vet+race pass, order preserved, atomic any width accepted, heap priority, fixed RK4 k1..k4, log-interp Cd, deadline 500ms/50items lenient, cancellation 200ms/50items lenient.
