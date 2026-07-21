# Step 2: Dive Dynamics - Re Table Drag, RK4 & Fleet

## Overview
Step 2 of 2, `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 — reuse its types, constants, methods without redefining. It contains triple pycnocline + halocline + thermocline + dual cabbeling (mixed scales 24m and 22.5m) + depth-dependent thermal coupling gamma0*tAnom*(1+gDepth*z) with z*exp integral, sound speed with quadratic term and gradient + SOFAR axis and pycnocline max gradient finders, potential density, second-order potential temperature, steric height, double-diffusive regime, pressure analytic with mixed scales and z*exp term, volume with quad thermal.

Goal: dive dynamics with Re table drag, terminal bisection, multi-root equilibrium scanning, fixed RK4 time-to-depth, bounded fleet worker-pool.

**You must NOT redefine:** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `PycnoclineDelta`, `PycnoclineScale`, `DeepPycnoclineDelta`, `DeepPycnoclineScale`, `MidPycnoclineDelta`, `MidPycnoclineScale`, `HaloclineDelta`, `HaloclineScale`, `ThermoclineScale`, `HullThermalExpansionCoeff`, `SeawaterViscosity`, `SalinityDensityCoeff`, `BulkModulus`, `CabbelingCoeff`, `HullThermalExpansionQuadCoeff`, `SoundSpeedPressureQuadCoeff`, `ThermobaricCoeff`, `ThermalCouplingCoeff`, `GammaDepthFactor`.

Available methods from Step1: `DensityAtDepth`, `CabbelingParameterAtDepth`, `SpicinessAtDepth`, `DensityGradientAtDepth`, `DensitySecondDerivativeAtDepth`, `DensityThirdDerivativeAtDepth`, `SoundSpeedAtDepth`, `SoundSpeedGradientAtDepth`, `FindSOFARAxis`, `FindPycnoclineMaxGradient`, `PotentialDensityAtDepth`, `PotentialTemperatureAtDepth`, `PressureAtDepth`, `StericHeightAtDepth`, `BuoyancyFrequencySquared`, `TurnerAngleAtDepth`, `DoubleDiffusiveRegimeAtDepth`, `VolumeAtDepth`, etc.

## Ocean & Hull Recap (Reuse Step1)
- S(z)=35+Hd*(1-exp(-z/Hs)), T(z)=15-12*(1-exp(-z/Ts)), sAnom=Hd*(1-exp(-z/Hs)), tAnom=12*(1-exp(-z/Ts)), pyc1=D1(1-exp(-z/S1)), pyc2, pyc3
- rho(z)=rho0+grad*z+pyc1+pyc2+pyc3+beta*sAnom+gamma0*tAnom*(1+gDepth*z)+Cc*sAnom*tAnom+Cc*pyc3*sAnom, mixed scales 24m=Hs*Ts/(Hs+Ts) and 22.5m=Mid*Hs/(Mid+Hs), plus z*tAnom term, beta=SalinityDensityCoeff, gamma0=ThermalCouplingCoeff, gDepth=GammaDepthFactor, Cc=CabbelingCoeff
- Spiciness beta*(S-35)+gamma0*(T-15), cab total Cc*sAnom*tAnom+Cc*pyc3*sAnom
- Sound speed with quad term and gradient, SOFAR axis and pycnocline max gradient via scanning 1000+ternary, potential density rho-grad*z, potential temperature second-order, N2, Turner, regime, pressure analytic with quadratic+5 exps+mixed 24m+22.5m+z*exp, steric (P/g -rho0*z)/rho0, volume V0*exp(-kP)*(1+alpha*dT+alpha2*dT^2)

## New Physics

**Effective mass:** `m=DryMass+BallastLevel`. Area `A(z)=V(z)/Length`.

**Re table drag:** mu=SeawaterViscosity=0.001, Re=rho(z)*|v|*Length/mu, Cd(Re)=1.2 if Re<1e5 else 0.5 if Re<5e5 else 0.2, Re->0 use 1.2. Drag 0.5*rho*Cd*A*v*|v|. Fnet=Fb-Fw-drag, v up. For TimeToDepth down-positive: Fnet_down=Fw-Fb-0.5*rho*Cd*A*v*|v|.

**Terminal velocity (bisection):**
Find v where Fnet=0, |Fb-Fw|=0.5*rho*Cd(Re)*A*v^2, bisection after upper bound doubling.
- If |Fb-Fw|<=1e-12 =>0
- If DragCoefficient<=0 error "drag"
- hi doubling from 1 m/s until drag>=|delta| or 1e4, bisect up to 100 iter until |drag-|delta||<1e-6 or interval<1e-6. Signed sign(Fb-Fw)*v_mag positive up.
- Validate depth>=0,g>0,depth<=CrushDepth else "crush".

**Equilibrium depth (multi-root scanning + bisection):**
f(z)=Fb(z)-Fw, scanning due to rho*V hump 0-2 roots.
- scan points >=1000 equally spaced [0,maxDepth], tolerance arg, bisection max iter 100, dedup tolerance*10, f tolerance 1e-9, maxDepth>0 and <=CrushDepth else "crush"
- Validate g>0,maxDepth>0,tolerance>0 else error. If |f(0)|<=Tolerance return 0
- Scan, for each pair f_i*f_{i+1}<=0 bracket, bisection up to 100 iter, collect sorted dedup within tolerance*10
- FindEquilibriumDepth returns shallowest, FindEquilibriumDepths all sorted, error if none, WithStability includes Stable field.

**TimeToDepth via fixed RK4:**
- dt argument, tests use 0.1 vs ref 0.01, maxTime argument, maxSteps maxTime/dt up to 100000, accuracy 5% rel vs dt/10 reference
- ODEs dz/dt=v, dv/dt=Fnet_down/m, down-positive
- Start (0,0) at rest, classic RK4 k1_z=v, k1_v=F/m, k2_z=v+0.5dt*k1_v ... z+=dt/6*(k1+2k2+2k3+k4), interpolate linearly when crossing target
- Validate targetDepth>0,g>0,dt>0,maxTime>0 else error, target>CrushDepth "crush", z>CrushDepth during integration "crush", not reached "not reached"/"time"/"unreachable"

**Fleet batch bounded worker-pool:**
- pool semaphore 4 via make(chan struct{},4), order preservation indexed results sorted by Index, invalid sub DiveResult{Index:i,State:"invalid"}, empty input empty slice, mismatched lengths error "length" or "mismatch", context BatchAnalyzeFleetWithContext must check ctx.Err() before start, return ctx.Err() on immediate cancel, import context
- BatchAnalyzeFleet, WithTargets, WithContext same as before, uses go, WaitGroup, chan, semaphore 4, race-safe, order preserved 20.

## File Location
Existing `/app/submarine.go` must remain. New `/app/dive.go`, package submarine, stdlib only (math,errors,sync,context). go vet and race pass.

## Types
```go
type DiveResult struct {
    Index int; State string; StateAtDepth string; Fraction float64
    RequiredBallast float64; RequiredBallastAtDepth float64
    IsPossible bool; IsPossibleAtDepth bool
    EffectiveDensity float64; EffectiveDensityAtDepth float64
    NetForce float64; NetForceAtDepth float64; Acceleration float64
    EquilibriumDepth float64; TerminalVelocity float64; TimeToDepth float64
    MaxPressure float64; VolumeAtDepth float64; CrushRisk bool
}
type EquilibriumPoint struct { Depth float64; Stable bool; FPrime float64 }
```

## Functions Required
```go
func SubmergedFraction(sub Submarine, fluid Seawater) (float64,error)
func NetVerticalForce(sub Submarine, fluid Seawater, g float64) (float64,error)
func VerticalAcceleration(sub Submarine, fluid Seawater, g float64) (float64,error)
func AnalyzeDive(sub Submarine, fluid Seawater) (DiveResult,error)
func BatchAnalyzeFleet(subs []Submarine, fluid Seawater) ([]DiveResult,error)
func NetVerticalForceAtDepth(sub Submarine, fluid Seawater, depth float64, velocity float64, g float64) (float64,error)
func CdFromRe(re float64) float64
func TerminalVelocity(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func FindEquilibriumDepth(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) (float64,error)
func FindEquilibriumDepths(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]float64,error)
func FindEquilibriumDepthsWithStability(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]EquilibriumPoint,error)
func TimeToDepth(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) (float64,error)
func BatchAnalyzeFleetWithTargets(subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult,error)
func BatchAnalyzeFleetWithContext(ctx context.Context, subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult,error)
```

## Requirements
1. Reuse types/constants from submarine.go, do NOT redefine Submarine,Seawater,Tolerance etc (AST check dive.go must NOT contain "type Submarine struct")
2. File /app/dive.go package submarine, go vet and race pass
3. Structs required fields present, functions exact signatures
4. Stdlib only, no hardcoding, compute via physics helpers
5. Concurrency bounded pool 4 with make(chan struct{},4), WaitGroup, chan, go, context import, order preserved 20, race -count=1
6. RK4 must contain k1..k4, accuracy 5% vs dt/10
7. Terminal bisection with CdFromRe, sqrt constant Cd fails at Re thresholds
8. Equilibrium scanning + bisection, naive f(lo)*f(hi) fails multi-root hump
9. CdFromRe table 1.2/0.5/0.2
