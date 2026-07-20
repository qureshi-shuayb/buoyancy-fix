# Step 2: Moderate Dive Dynamics - Simple Re Table Drag, Fixed RK4 & Fleet

## Overview
This is **Step 2 of 2**. `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 — you MUST reuse its types, constants, and methods without redefining them. Inspect existing file with `cat /app/submarine.go`. It now contains triple pycnocline + halocline salinity + thermocline T/S coupling, sound speed, potential density, second derivative, Turner angle.

Goal: dive dynamics where drag coefficient is simple Re table (1.2/0.5/0.2), terminal velocity implicit via bisection, equilibrium depth may have 0-2 roots requiring scanning + bisection (hump still exists due to triple pycnocline + exponential hull), time-to-depth via fixed RK4 (not adaptive), and fleet batch bounded worker-pool with simple context handling, order preservation, and race safety. This step is intentionally easier than previous ultra-hard version.

**You must NOT redefine:** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `PycnoclineDelta`, `PycnoclineScale`, `DeepPycnoclineDelta`, `DeepPycnoclineScale`, `MidPycnoclineDelta`, `MidPycnoclineScale`, `HaloclineDelta`, `HaloclineScale`, `ThermoclineScale`, `HullThermalExpansionCoeff`, `SeawaterViscosity`, `SalinityDensityCoeff`, `BulkModulus`.

## Ocean & Hull Recap (From Step 1, Reuse)

You already implemented:
- Salinity `S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale))`
- Temperature `T(z)=15-12*(1-exp(-z/ThermoclineScale))`
- Density `rho(z)=rho0+grad*z+D1(1-exp(-z/S1))+D2(1-exp(-z/S2))+D3(1-exp(-z/S3))+beta*(S-35)+gamma*(15-T)` with 5 exps, beta=SalinityDensityCoeff 0.8, gamma=0.15 fixed
- Gradient `drho/dz` with 5 terms, second derivative negative, salinity/temperature gradients, sound speed `c=1449.2+4.6T-0.055T²+1.34(S-35)+0.016z` with SOFAR min, potential density without grad term, potential temperature, N², Turner angle
- Pressure integral analytic with 5 exps (quadratic + 5 exp terms)
- Volume `V(z)=V0*exp(-kP)*(1+alpha*(T-15))` clamped, alpha=HullThermalExpansionCoeff
- Methods DensityAtDepth, Gradient, SecondDerivative, Salinity, Temperature, SoundSpeed, PotentialDensity, PotentialTemperature, BuoyancyFrequency, TurnerAngle, PressureAtDepth, VolumeAtDepth, etc.

Reuse these; do not re-derive incorrectly.

## New Physics for Step 2 (Easier)

**Effective mass:** `m = DryMass+BallastLevel`.

**Cross-section area:** `A(z)=V(z)/Length` via VolumeAtDepth.

**Reynolds number dependent simple table drag (easier):**
Dynamic viscosity `mu=SeawaterViscosity=0.001`. Reynolds `Re = rho(z)*|v|*Length / mu`.

Drag coefficient `Cd(Re)` simple table (no crisis, monotonic stepwise):
- If `Re < 1e5`: `Cd=1.2`
- Else if `Re < 5e5`: `Cd=0.5`
- Else: `Cd=0.2`

This models drag drop but without continuous crisis, easier to implement. For Re approaching 0, use `Cd=1.2`.

Drag force `drag=0.5*rho*Cd(Re)*A*v*|v|`. Up-positive: `Fnet(z,v)=Fb(z)-Fw - drag`, `v` up-positive. When `v=0` drag zero. For TimeToDepth down-positive: `Fnet_down = Fw - Fb(z) - 0.5*rho*Cd*A*v*|v|` with v down positive.

**Terminal velocity: Implicit bisection (easier, monotonic drag):**
Terminal where `Fnet=0` at given depth. Because Cd depends on Re which depends on |v|, equation `|Fb-Fw| = 0.5*rho*Cd(Re(v))*A*v²` has no closed form sqrt but drag vs v is monotonic increasing (since Cd stepwise decreasing but v² dominates, overall drag monotonic), so simple bisection after finding upper bound suffices (no need velocity interval scanning for bistability).

- If `|Fb-Fw| <=1e-12` => terminal 0
- If `DragCoefficient field <=0` => error containing "drag"
- Find hi via doubling from 1 m/s until drag(hi) >= |delta| or hi huge 1e4, then bisect on magnitude for up to 100 iterations until |drag-|delta||<1e-6 or interval <1e-6. Signed result: sign(Fb-Fw) * v_mag (positive up for light floating).
- Validate depth>=0,g>0,depth<=CrushDepth else "crush".

**Equilibrium depth: Multi-root scanning + bisection (moderate):**
Zero-velocity net force `f(z)=Fb(z)-Fw`. Find z where f(z)=0. Because rho increases (triple pycnocline+halocline+thermal) but V decreases exponentially, product rho*V non-monotonic hump, 0-2 equilibria. Naive bisection over [0,maxDepth] requiring f(lo)*f(hi)<0 fails when both ends same sign but interior root exists. Must scan.

- Validate g>0, maxDepth>0, tolerance>0, maxDepth<=CrushDepth else "crush"
- If |f(0)| <= Tolerance return 0
- Scan [0,maxDepth] with at least 1000 points equally spaced, compute f. Look for sign changes f_i*f_{i+1}<=0 or |f_i|<Tolerance. For each bracket, bisection up to 100 iterations until |f(mid)|<1e-9 or width < tolerance. Collect roots, deduplicate within tolerance*10.
- Return shallowest for FindEquilibriumDepth, all sorted for FindEquilibriumDepths. If none error.
- FindEquilibriumDepthsWithStability returns same depths with Stable=true (or via simple perturbation ±1m: stable if f(z+1)>0). For this easier version, tests only check depth sorted and not strict stability sign, but you must still return Stable field.

**Stability:** For easier version, stable if f(z+1)>0 (upward restoring when deeper). You may compute derivative via central diff 0.1m and stable if derivative>0, but tests will only check that Stable field present and not NaN for basic cases, not strict sign for multi-root.

**Time to depth via fixed RK4 (easier, no adaptive):**
Integrate coupled ODEs from rest at surface z=0,v=0 to targetDepth>0 down-positive.

Equations: `dz/dt=v`, `dv/dt=Fnet_down/m` where `m=EffectiveMass` (no added mass, easier), `Fnet_down=Fw-Fb(z)-0.5*rho*Cd(Re)*A*v*|v|`, `Re=rho*|v|*Length/mu`.

Start (0,0), step dt, loop until time exceeds maxTime. At each step perform classic RK4: k1_z=v, k1_v=F/m, k2_z=v+0.5dt*k1_v etc, update z+=dt/6*(k1+2k2+2k3+k4). Interpolate time when z crosses target (linear interpolation between steps). Return interpolated time.

Requirements:
- Validate targetDepth>0,g>0,dt>0,maxTime>0 else error
- If targetDepth>CrushDepth error "crush"
- If never reaches within maxTime error containing "not reached" or "time" or "unreachable"
- If during integration z exceeds CrushDepth error "crush"
- RK4 must be proper 4th order; Euler will fail accuracy test requiring within 5% of small-dt reference (looser than previous 2%). Tests compare dt=0.1 vs dt=0.01 ref, rel <0.05.
- Must handle equilibrium blocking: heavy sink may have equilibrium before target where velocity decays; then will not reach => error.

**Fleet batch with bounded worker pool and simple context:**

- BatchAnalyzeFleet(subs, fluid): If fluid invalid return nil,error. If subs nil or empty return empty slice. For each i, if sub invalid => DiveResult{Index:i, State:"invalid"}. Else AnalyzeDive with Index=i. Preserve order. Must use at least one goroutine with sync.WaitGroup and channel for ordering, plus semaphore limit 4 via `make(chan struct{},4)`, acquire/release. Must be race-safe, import context.

- BatchAnalyzeFleetWithTargets(subs, fluid, targetDepths, g): Validates fluid,g>0,len(subs)==len(targetDepths) else error "length" or "mismatch". Empty => empty. For each i, if invalid sub or target<0 => invalid state. If target>CrushDepth => CrushRisk true and State "invalid". Else AnalyzeDive plus TimeToDepth to populate TimeToDepth. Preserve order, bounded pool.

- BatchAnalyzeFleetWithContext(ctx, subs, fluid, targetDepths, g): Same as WithTargets but accepts context.Context. Must check `ctx.Err()` before start, if cancelled return nil, ctx.Err(). Workers should check context? For easier version, only pre-check ctx.Err() is sufficient, but must import context and contain `context` substring and `make(chan struct{},4)`. If ctx cancelled during processing, return partial results and error containing "context". Tests will check immediate cancellation returns error containing "context", and background context works order preserved. Must contain `go`, `WaitGroup`, `chan`, `context`.

## File Location
- Existing /app/submarine.go from Step1 must remain.
- New file /app/dive.go, package submarine, stdlib only (math, errors, sync, context). Both go vet and race must pass.

## Types
```go
type DiveResult struct {
    Index int
    State string
    StateAtDepth string
    Fraction float64
    RequiredBallast float64
    RequiredBallastAtDepth float64
    IsPossible bool
    IsPossibleAtDepth bool
    EffectiveDensity float64
    EffectiveDensityAtDepth float64
    NetForce float64
    NetForceAtDepth float64
    Acceleration float64
    EquilibriumDepth float64
    TerminalVelocity float64
    TimeToDepth float64
    MaxPressure float64
    VolumeAtDepth float64
    CrushRisk bool
}
type EquilibriumPoint struct {
    Depth float64
    Stable bool
    FPrime float64
}
```

## Functions Required (Exact Signatures)
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
1. Reuse types/constants from submarine.go, do NOT redefine them (AST check: dive.go must NOT contain "type Submarine struct" nor "type Seawater struct" nor "const Tolerance").
2. File /app/dive.go package submarine, go vet passes, race passes.
3. Structs required fields present.
4. Functions exact signatures.
5. Stdlib only (math, errors, sync, context, etc).
6. No hardcoding; must compute via physics helpers.
7. Concurrency: must contain "go ", "WaitGroup", "chan", "context", "make(chan struct{" and maybe "4"
8. RK4: must contain "k1", "k2", "k3", "k4" and accuracy within 5% (Euler fails >15%)
9. TerminalVelocity: bisection loop and handle Re-dependent Cd via CdFromRe; simple sqrt constant Cd fails where Re threshold crossed.
10. Equilibrium: scanning + bisection required; naive f(lo)*f(hi) only fails multi-root case where both ends same sign but interior root exists.
11. Triple pycnocline + halocline + thermocline must be reused via helpers.
12. CdFromRe must use table 1.2/0.5/0.2 based on Re.

## Grading (Hidden, Easier than before but still moderate)
- SubmergedFraction clamped 20 cases
- NetForce surface and at depth with Re table, zero-velocity equals Fb-Fw
- CdFromRe bands: Re<1e5 =>1.2 within 1.1-1.3, 1e5-5e5 =>0.5 within 0.4-0.6, >=5e5 =>0.2 within 0.15-0.3
- TerminalVelocity inverse check tol 0.1, signed, error drag, Re threshold case
- FindEquilibriumDepth: surface neutral 0, heavy no root error, sink-to-float brute-force within 0.5m tolerant, multi-root hump where f(lo)*f(hi)>0 but root inside, crush error
- FindEquilibriumDepths: returns 1-2 roots sorted
- FindEquilibriumDepthsWithStability: depth sorted, Stable field present
- TimeToDepth: heavy reaches, light fails, accuracy 5% vs ref dt/10, crush error
- AnalyzeDive fields, MaxPressure, VolumeAtDepth, CrushRisk
- BatchFleet: order preservation 20 subs (not 50), invalid marking, empty, mismatched lengths error, concurrency primitives present, sem 4, race -count=1 maybe 10, context import
- BatchWithContext: immediate cancel returns context error, background works order preserved
- No redefinition, go vet, race
