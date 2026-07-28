# Step 2: Dive Dynamics – EASY-MEDIUM – 5-pt Drag, 500pts Equilibrium, Fixed RK4, Priority Fleet

## Overview
Step 2 of 2, `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 **EASY** – 12 constants (Tolerance 1e-9, Gravity 9.81, SeawaterDensity 1025, DepthGrad 0.02, MinVol 0.1, PycDelta 10/Scale 200, Halo 2.5/30, ThermoScale 120, SalinityCoeff 0.8, Bulk 2.2e9), 3-term density `rho0+grad*z+pyc1`, 3-term pressure single-scale, 1st derivative only, sound 3 terms `1449.2+4.6T+0.016z`, pot temp 1st order, 1 finder SOFAR 100pts 50iter. Reuse all without redefining.

**Goal – EASY-MEDIUM (further eased):** 5-pt Cd log-interp band 0.1, terminal 50iter 1e-2, equilibrium 500pts 50iter root 5m tol, fixed RK4 k1..k4 + optional adaptive atol/rtol with independent ref 25%, dive profile len>3 tol 5%, priority fleet heap + bounded pool 4 + atomic any width/style, deadline 500ms/50items lenient, cancellation 200ms/50items lenient.

**You must NOT redefine (12):** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `PycnoclineDelta`, `PycnoclineScale`, `HaloclineDelta`, `HaloclineScale`, `ThermoclineScale`, `SalinityDensityCoeff`, `BulkModulus`.

Available: Density 3-term, Gradient 1st, Sound 3-term, FindSOFARAxis 100pts 50iter, PotentialDensity, PotentialTemperature 1st, Pressure 3-term single-scale, BuoyancyFrequencySquared simple, Volume simple no thermal.

## Ocean & Hull Recap – EASY
- S(z)=35+2.5*(1-exp(-z/30)), T(z)=15-12*(1-exp(-z/120)), pyc1=10*(1-exp(-z/200))
- rho(z)=rho0+0.02z+pyc1
- Pressure P=g*(rho0*z+0.01z²+10*(z+200*exp(-z/200)-200)) single-scale only, Simpson 20k rel 1e-2 >2.
- Sound c=1449.2+4.6T+0.016z, gradient 4.6dT+0.016.

## New Physics – EASY-MEDIUM

**Effective mass & area:** m=Dry+Ballast, A=V/Length, V=V0*exp(-kP) clamped 0.1, K=1/k.

**Re log-interp drag – 5-pt table:**
```
Re: [1e3, 1e4, 1e5, 1e6, 5e6]
Cd: [1.44, 1.2, 0.7, 0.2, 0.12]
```
`CdFromRe(re)` log-linear on log10(Re). re<=1e3 return 1.44, re>=5e6 return 0.12. Band 0.1, midpoint log exact tol 0.05.

**Terminal – 50 iter:** delta=Fb-Fw, dragMag(vMag)=0.5*rho*Cd(Re(vMag))*A*vMag², doubling hi, Brent/bisect 50 iter until |drag-|delta||<1e-2 or width<1e-5.

**Equilibrium – 500pts 50iter:** f(z)=Fb(z)-Fw, scan 500 pts, brackets sign change, Brent 50 iter until |f|<1e-6 or width<tol, sorted. Crush check.

**TimeToDepth – fixed RK4:** down-positive dz/dt=v, dv/dt=Fnet_down/m, Fnet_down=Fw-Fb-0.5*rho*Cd*A*v*|v|, must have k1..k4. Ref RK4 dt=0.001 25% rel.

**Fleet – heap + atomic any width + lenient deadlines:**
- Semaphore 4 `make(chan struct{},4)` + WaitGroup + go
- Priority heap by effective density descending via `container/heap`, final sorted by Index
- Atomic any style: AddInt32/64, Uint, typed Int32/64 with Add/Load/Store/CAS – R08 fix
- Deadline 500ms/50items lenient, cancellation 200ms/50items lenient
- DiveProfile len>3 depth tol 5%

## File Location
Existing `/app/submarine.go` (12 consts). New `/app/dive.go`, package submarine, stdlib+heap+atomic, vet+race pass, order preserved, R05 leak fixed (rm *_test.go before+after).

## Types – same as before

## Functions Required – same signatures
