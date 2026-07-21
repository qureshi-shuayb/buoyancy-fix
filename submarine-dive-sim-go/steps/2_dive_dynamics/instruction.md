# Step 2: Dive Dynamics - Re Table Drag, RK4 & Fleet

## Overview
Step 2 of 2, `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 — reuse its types, constants, methods without redefining. It contains triple pycnocline + halocline + thermocline + quad cabbeling (mixed scales 24m,22.5m,26.08m,32.72m plus double-freq 15m,60m) + depth-dependent thermal coupling with z*exp integral, sound speed quad and gradient, SOFAR axis and pycnocline max gradient finders, potential density, second-order potential temperature, steric height, double-diffusive regime, pressure with 11 scales plus z*exp, volume quad thermal.

Goal: dive dynamics with Re table drag, terminal bisection, multi-root equilibrium scanning, fixed RK4 time-to-depth, bounded fleet worker-pool.

**You must NOT redefine:** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `PycnoclineDelta`, `PycnoclineScale`, `DeepPycnoclineDelta`, `DeepPycnoclineScale`, `MidPycnoclineDelta`, `MidPycnoclineScale`, `HaloclineDelta`, `HaloclineScale`, `ThermoclineScale`, `HullThermalExpansionCoeff`, `SeawaterViscosity`, `SalinityDensityCoeff`, `BulkModulus`, `CabbelingCoeff`, `HullThermalExpansionQuadCoeff`, `SoundSpeedPressureQuadCoeff`, `ThermobaricCoeff`, `ThermalCouplingCoeff`, `GammaDepthFactor`, `TAnomQuadCoeff`, `SAnomQuadCoeff`.

Available methods: `DensityAtDepth`, `CabbelingParameterAtDepth`, `SpicinessAtDepth`, `DensityGradientAtDepth`, `DensitySecondDerivativeAtDepth`, `DensityThirdDerivativeAtDepth`, `SoundSpeedAtDepth`, `SoundSpeedGradientAtDepth`, `FindSOFARAxis`, `FindPycnoclineMaxGradient`, `PotentialDensityAtDepth`, `PotentialTemperatureAtDepth`, `PressureAtDepth`, `StericHeightAtDepth`, `BuoyancyFrequencySquared`, `TurnerAngleAtDepth`, `DoubleDiffusiveRegimeAtDepth`, `VolumeAtDepth`, etc.

## Ocean & Hull Recap
- S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale)), T(z)=15-12*(1-exp(-z/ThermoclineScale)), sAnom=HaloclineDelta*(1-exp(-z/HaloclineScale)), tAnom=12*(1-exp(-z/ThermoclineScale)), pyc1=PycnoclineDelta*(1-exp(-z/PycnoclineScale)), pyc2=DeepPycnoclineDelta*(1-exp(-z/DeepPycnoclineScale)), pyc3=MidPycnoclineDelta*(1-exp(-z/MidPycnoclineScale))
- rho(z)=rho0+DepthDensityGradient*z+pyc1+pyc2+pyc3+SalinityDensityCoeff*sAnom+ThermalCouplingCoeff*tAnom*(1+GammaDepthFactor*z)+CabbelingCoeff*sAnom*tAnom+CabbelingCoeff*pyc3*sAnom+CabbelingCoeff*pyc1*sAnom+CabbelingCoeff*pyc2*tAnom+TAnomQuadCoeff*tAnom^2+SAnomQuadCoeff*sAnom^2

## New Physics (easier tolerances)

**Effective mass:** m=DryMass+BallastLevel. Area A(z)=V(z)/Length.

**Re table drag:** mu=SeawaterViscosity, Re=rho(z)*|v|*Length/mu, Cd(Re)=1.2 if Re<1e5 else 0.5 if Re<5e5 else 0.2, drag 0.5*rho*Cd*A*v*|v|, Fnet=Fb-Fw-drag.

**Terminal velocity (bisection):**
Find v where |Fb-Fw|=0.5*rho*Cd*A*v^2 via bisection after doubling hi until drag>=|delta| or 1e4, 100 iter.

**Equilibrium depth (easier):**
f(z)=Fb(z)-Fw, scanning may have 0-2 roots.
- Scan points >=200 equally spaced [0,maxDepth], tolerance 1e-1, bisection 100 iter, dedup tolerance*10, f zero tolerance 1e-6, maxDepth>0 and <=CrushDepth else "crush"
- Returns shallowest, all sorted, error if none.

**TimeToDepth via fixed RK4 (easier 15%):**
- dt 0.1 vs ref 0.01, maxTime 30000, accuracy 15% rel vs dt/10 reference.
- ODEs dz/dt=v, dv/dt=Fnet_down/m, down-positive, start (0,0), classic RK4 k1..k4, interpolate on crossing.

**Fleet batch bounded worker-pool:**
- Semaphore 4 via make(chan struct{},4), order preservation indexed results sorted by Index, invalid sub DiveResult{Index:i,State:"invalid"}, empty slice, mismatched lengths error "length"/"mismatch", context check.

## File Location
Existing `/app/submarine.go` remains. New `/app/dive.go`, package submarine, stdlib only. go vet and race pass.

## Types
```go
type DiveResult struct { Index int; State string; StateAtDepth string; Fraction float64; RequiredBallast float64; RequiredBallastAtDepth float64; IsPossible bool; IsPossibleAtDepth bool; EffectiveDensity float64; EffectiveDensityAtDepth float64; NetForce float64; NetForceAtDepth float64; Acceleration float64; EquilibriumDepth float64; TerminalVelocity float64; TimeToDepth float64; MaxPressure float64; VolumeAtDepth float64; CrushRisk bool }
type EquilibriumPoint struct { Depth float64; Stable bool; FPrime float64 }
```

## Functions Required
SubmergedFraction, NetVerticalForce, VerticalAcceleration, AnalyzeDive, BatchAnalyzeFleet, NetVerticalForceAtDepth, CdFromRe, TerminalVelocity, FindEquilibriumDepth, FindEquilibriumDepths, FindEquilibriumDepthsWithStability, TimeToDepth, BatchAnalyzeFleetWithTargets, BatchAnalyzeFleetWithContext exact signatures.

## Requirements
Reuse types/constants, do NOT redefine, go vet and race pass, order preserved 20.
