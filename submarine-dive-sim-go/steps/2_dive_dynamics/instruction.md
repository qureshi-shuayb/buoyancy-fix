# Step 2: Dive Dynamics – EASY – 5-pt Drag, 500pts Equilibrium, Fixed RK4, Priority Fleet

## Overview
Step 2 of 2, `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 **EASY** – 8 constants (Tolerance 1e-9, Gravity 9.81, SeawaterDensity 1025, DepthGrad 0.02, MinVol 0.1, Bulk 2.2e9, PycDelta 10/Scale 200), 2-term density `rho0+grad*z` linear, 2-term pressure `g*(rho0*z+0.5*grad*z²)`, 1st derivative constant only, sound quadratic `1500-0.1z+0.0002z²` min at 250m, pot temp 1st `T*(1-x)`, 1 finder SOFAR 100pts 50iter. Reuse all without redefining.

**Goal – EASY (further eased to hit 5/10 step1):** 5-pt Cd log-interp band 0.1, terminal 50iter 1e-2, equilibrium 500pts 50iter root 5m tol, fixed RK4 k1..k4 + optional adaptive atol/rtol with independent ref 25%, dive profile len>3 tol 5%, priority fleet heap + bounded pool 4 + atomic any width/style, deadline 500ms/50items lenient, cancellation 200ms/50items lenient.

**You must NOT redefine (8):** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `BulkModulus`, `PycnoclineDelta`, `PycnoclineScale`.

Available: Density 2-term linear, Gradient constant, Sound quadratic, FindSOFARAxis 100pts 50iter trivial 250m, Pressure 2-term linear, Volume simple exp(-kP) no thermal, Steric simple.

## New Physics – EASY

**Effective mass & area:** m=Dry+Ballast, A=V/Length, V=V0*exp(-kP) clamped 0.1, K=1/k.

**Re log-interp drag – 5-pt table:**
```
Re: [1e3, 1e4, 1e5, 1e6, 5e6]
Cd: [1.44, 1.2, 0.7, 0.2, 0.12]
```
`CdFromRe` log-linear on log10(Re). re<=1e3 return 1.44, re>=5e6 return 0.12. Band 0.1, midpoint tol 0.05. Re=rho*|v|*Length / 0.001 (literal, not SeawaterViscosity constant which is removed for easiness).

Drag `0.5*rho*Cd*A*v*|v|`, Fnet up: `Fb-Fw - drag`

**Terminal – 50 iter 1e-2:** delta=Fb-Fw, dragMag(vMag)=0.5*rho*Cd(Re(vMag))*A*vMag², doubling hi, Brent/bisect 50 iter.

**Equilibrium – 500pts 50iter:** f(z)=Fb(z)-Fw, scan 500 pts, Brent 50 iter, sorted, crush check.

**TimeToDepth – fixed RK4 k1..k4:** down-positive, fnetDown=Fw-Fb-0.5*rho*Cd*A*v*|v|, k1..k4 required, ref RK4 dt=0.001 25% rel.

**Fleet – heap + atomic any width + lenient deadlines:**
- Semaphore 4 `make(chan struct{},4)` + WaitGroup + go
- Priority heap by effective density descending via container/heap, final sorted by Index
- Atomic any style: AddInt32/64, Uint, typed Int32/64 with Add/Load/Store/CAS – R08 fix
- Deadline 500ms/50items lenient, cancellation 200ms/50items lenient
- DiveProfile len>3 depth tol 5%

## File Location
Existing `/app/submarine.go` (8 consts). New `/app/dive.go`, package submarine, stdlib+heap+atomic, vet+race pass, R05 leak fixed.

## Functions Required – same signatures
