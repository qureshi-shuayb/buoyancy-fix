# Step 2: Dive Dynamics - Re Table Drag, RK4 & Fleet

## Overview
Step 2 of 2, `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 — reuse its types, constants, methods without redefining. It contains triple pycnocline + halocline + thermocline + quad cabbeling (mixed scales 24m,22.5m,26.08m,32.72m plus double-freq 15m,60m) + depth-dependent thermal coupling with z*exp integral, sound speed quad and gradient, SOFAR axis and pycnocline max gradient finders, potential density, second-order potential temperature, steric height, double-diffusive regime, pressure with 11 scales plus z*exp, volume quad thermal.

Goal: dive dynamics with Re table drag, terminal bisection, multi-root equilibrium scanning, fixed RK4 time-to-depth, bounded fleet worker-pool.

**You must NOT redefine:** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `PycnoclineDelta`, `PycnoclineScale`, `DeepPycnoclineDelta`, `DeepPycnoclineScale`, `MidPycnoclineDelta`, `MidPycnoclineScale`, `HaloclineDelta`, `HaloclineScale`, `ThermoclineScale`, `HullThermalExpansionCoeff`, `SeawaterViscosity`, `SalinityDensityCoeff`, `BulkModulus`, `CabbelingCoeff`, `HullThermalExpansionQuadCoeff`, `SoundSpeedPressureQuadCoeff`, `ThermobaricCoeff`, `ThermalCouplingCoeff`, `GammaDepthFactor`, `TAnomQuadCoeff`, `SAnomQuadCoeff`.

Available methods: `DensityAtDepth`, `CabbelingParameterAtDepth`, `SpicinessAtDepth`, `DensityGradientAtDepth`, `DensitySecondDerivativeAtDepth`, `DensityThirdDerivativeAtDepth`, `SoundSpeedAtDepth`, `SoundSpeedGradientAtDepth`, `FindSOFARAxis`, `FindPycnoclineMaxGradient`, `PotentialDensityAtDepth`, `PotentialTemperatureAtDepth`, `PressureAtDepth`, `StericHeightAtDepth`, `BuoyancyFrequencySquared`, `TurnerAngleAtDepth`, `DoubleDiffusiveRegimeAtDepth`, `VolumeAtDepth`, etc.

## Ocean & Hull Recap
- S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale)), T(z)=15-12*(1-exp(-z/ThermoclineScale)), sAnom=HaloclineDelta*(1-exp(-z/HaloclineScale)), tAnom=12*(1-exp(-z/ThermoclineScale)), pyc1=PycnoclineDelta*(1-exp(-z/PycnoclineScale)), pyc2=DeepPycnoclineDelta*(1-exp(-z/DeepPycnoclineScale)), pyc3=MidPycnoclineDelta*(1-exp(-z/MidPycnoclineScale))
- rho(z)=rho0+DepthDensityGradient*z+pyc1+pyc2+pyc3+SalinityDensityCoeff*sAnom+ThermalCouplingCoeff*tAnom*(1+GammaDepthFactor*z)+CabbelingCoeff*sAnom*tAnom+CabbelingCoeff*pyc3*sAnom+CabbelingCoeff*pyc1*sAnom+CabbelingCoeff*pyc2*tAnom+TAnomQuadCoeff*tAnom^2+SAnomQuadCoeff*sAnom^2

## New Physics

**Effective mass:** m=DryMass+BallastLevel. Area A(z)=V(z)/Length.

**Re table drag:** mu=SeawaterViscosity, Re=rho(z)*|v|*Length/mu, Cd(Re)=1.2 if Re<1e5 else 0.5 if Re<5e5 else 0.2, drag 0.5*rho*Cd*A*v*|v|, Fnet=Fb-Fw-drag, v up. Down-positive for TimeToDepth: Fnet_down=Fw-Fb-0.5*rho*Cd*A*v*|v|.

**Terminal velocity (bisection):**
Find v where |Fb-Fw|=0.5*rho*Cd* A*v^2 via bisection after upper bound doubling. If |Fb-Fw|<=1e-12 return 0. If DragCoefficient<=0 error contains "drag". hi doubling from 1 until drag>=|delta| or 1e4, bisect 100 iter until interval<1e-6. Signed sign(Fb-Fw)*v_mag.

**Equilibrium depth (easier):**
f(z)=Fb(z)-Fw, scanning due to rho*V hump may have 0-2 roots.
- Scan points >=500 equally spaced [0,maxDepth], tolerance 1e-2, bisection max iter 100, dedup tolerance*10, f zero tolerance 1e-6, maxDepth>0 and <=CrushDepth else "crush"
- Validation g>0,maxDepth>0,tolerance>0 else error.
- Scan, bracket where f_i*f_{i+1}<=0, bisection, collect sorted dedup. FindEquilibriumDepth returns shallowest, FindEquilibriumDepths all sorted, error if none, WithStability includes Stable.

**TimeToDepth via fixed RK4 (easier 10%):**
- dt argument, tests use 0.1 vs ref 0.01, maxTime 20000, accuracy 10% rel vs dt/10 reference (was 5%)
- ODEs dz/dt=v, dv/dt=Fnet_down/m, down-positive, start (0,0), classic RK4 k1_z=v, k1_v=F/m, etc., interpolate linearly when crossing target.
- Validate targetDepth>0,g>0,dt>0,maxTime>0 else error, target>CrushDepth "crush", not reached "not reached"/"time"/"unreachable"

**Fleet batch bounded worker-pool:**
- Semaphore 4 via make(chan struct{},4), order preservation indexed results sorted by Index, invalid sub DiveResult{Index:i,State:"invalid"}, empty input empty slice, mismatched lengths error "length"/"mismatch", context BatchAnalyzeFleetWithContext checks ctx.Err() before start, return ctx.Err() on immediate cancel, import context, uses go, WaitGroup, chan.

## File Location
Existing `/app/submarine.go` remains. New `/app/dive.go`, package submarine, stdlib only (math,errors,sync,context). go vet and race pass.

## Types
```go
type DiveResult struct { Index int; State string; StateAtDepth string; Fraction float64; RequiredBallast float64; RequiredBallastAtDepth float64; IsPossible bool; IsPossibleAtDepth bool; EffectiveDensity float64; EffectiveDensityAtDepth float64; NetForce float64; NetForceAtDepth float64; Acceleration float64; EquilibriumDepth float64; TerminalVelocity float64; TimeToDepth float64; MaxPressure float64; VolumeAtDepth float64; CrushRisk bool }
type EquilibriumPoint struct { Depth float64; Stable bool; FPrime float64 }
```

## Functions Required
SubmergedFraction, NetVerticalForce, VerticalAcceleration, AnalyzeDive, BatchAnalyzeFleet, NetVerticalForceAtDepth, CdFromRe, TerminalVelocity, FindEquilibriumDepth, FindEquilibriumDepths, FindEquilibriumDepthsWithStability, TimeToDepth, BatchAnalyzeFleetWithTargets, BatchAnalyzeFleetWithContext exact signatures.

## Requirements
Reuse types/constants, do NOT redefine Submarine,Seawater,Tolerance etc. File dive.go package submarine, go vet and race pass, order preserved 20.
