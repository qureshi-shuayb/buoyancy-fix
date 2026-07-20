# Step 2: Ultra-Hard Dive Dynamics - Continuous Drag Crisis, Added Mass, Adaptive RK4 & Context-Aware Fleet

## Overview
This is **Step 2 of 2**. `inherit_prior_session=true`. File `/app/submarine.go` exists from Step 1 — you MUST reuse its types, constants, and methods without redefining them. Inspect existing file with `cat /app/submarine.go`. It now contains dual exponential pycnocline (shallow + deep), thermocline temperature with thermal hull contraction, density gradient, buoyancy frequency.

Goal: dive dynamics where drag coefficient is continuous Clift-Gauvin correlation with logistic crisis drop, terminal velocity implicit and potentially bistable requiring velocity scanning, equilibrium depth is non-monotonic with hump up to 2-3 roots requiring scanning + bisection + stability classification, time-to-depth needs adaptive RK4 with step-doubling error control and added mass, and fleet batch must be bounded worker-pool with context cancellation, order preservation, and race safety.

**You must NOT redefine:** `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction`, `PycnoclineDelta`, `PycnoclineScale`, `DeepPycnoclineDelta`, `DeepPycnoclineScale`, `SeawaterViscosity`, `ThermoclineScale`, `HullThermalExpansionCoeff`.

## Ocean & Hull Recap (From Step 1, Reuse)

You already implemented:
- Seawater density dual pycnocline: `rho(z)=rho0+grad*z+D1*(1-exp(-z/S1))+D2*(1-exp(-z/S2))`
- Density gradient: `drho/dz = grad + D1/S1*exp(-z/S1)+D2/S2*exp(-z/S2)`
- Temperature: `T(z)=15-12*(1-exp(-z/ThermScale))`
- Buoyancy frequency: `N^2 = g/rho * drho/dz`
- Pressure: integral analytic with dual exponentials (quadratic + two exp terms)
- Volume: exponential `V(z)=V0*exp(-k*P(z))*(1+alpha*(T(z)-15))` clamped to MinimumVolumeFraction*V0, alpha=HullThermalExpansionCoeff
- Methods DensityAtDepth, DensityGradientAtDepth, TemperatureAtDepth, BuoyancyFrequencySquared, PressureAtDepth, VolumeAtDepth, EffectiveDensityAtDepth, BuoyantForceAtDepth, etc.

Reuse these; do not re-derive incorrectly. You must use them for dynamics.

## New Physics for Step 2 (No Code Spoilers, Derive Yourself)

**Effective mass and added mass:**
Effective mass `m = DryMass+BallastLevel`. For dive dynamics, total inertia includes added mass of displaced fluid: `m_total(z) = m + 0.5*rho(z)*V(z)` where 0.5 is added mass coefficient for roughly cylindrical body. This makes acceleration depth-dependent and increases inertia at depth. For terminal velocity (zero acceleration) added mass does not matter, but for `TimeToDepth` integration it does: `dv/dt = Fnet_down / m_total`.

**Cross-section area:** `A(z)=V(z)/Length` via VolumeAtDepth.

**Reynolds number dependent continuous drag with crisis:**
Dynamic viscosity `mu=SeawaterViscosity=0.001`. Reynolds `Re = rho(z)*|v|*Length / mu`.

Drag coefficient `Cd(Re)` is not a table but continuous Clift-Gauvin correlation for a sphere-like body with logistic crisis drop around `3e5`:
- For `Re <1e-6` return `1.2` (avoid division by zero)
- Base correlation: `Cd_base = 24/Re*(1+0.15*Re^0.687) + 0.42/(1+42500*Re^-1.16)` using `math.Pow`
- Crisis factor: `f_crisis = 0.2 + 0.8/(1+exp((Re-3e5)/4e4))` which transitions from ~1 at low Re to ~0.2 at high Re, modeling boundary layer drag crisis around 300k. Sharp drop ~80%.
- Final `Cd = Cd_base * f_crisis` clamped to `[0.08, 1.2]` min 0.08 max 1.2.

This continuous model produces: low Re (Re~100) Cd~1.1, medium Re~1e5 Cd~0.45-0.55, high Re~1e6 Cd~0.08-0.15, and crisis dip around 250k-400k where Cd drops from ~0.4 to ~0.1. You must implement `CdFromRe(Re)` exactly as described to pass band checks. Must use `math.Exp`, `math.Pow`.

**Drag force:** `drag = 0.5*rho(z)*Cd(Re)*A(z)*v*|v|`. Up-positive convention: `Fnet(z,v)=Fb(z)-Fw - drag`, where `v` up-positive. When `v=0` drag zero. When moving up (v>0) drag down, when moving down (v negative up) drag up opposing motion: formula `-0.5*rho*Cd*A*v*|v|` already opposes.

For `TimeToDepth` you may use down-positive: `Fnet_down = Fw - Fb(z) - 0.5*rho*Cd* A * v*|v|` with v down-positive.

**Terminal velocity: Implicit with velocity scanning**

Terminal velocity where zero acceleration `Fnet(z,v_term)=0` at given depth. Because `Cd` depends on `|v|` via `Re`, equation `Fb-Fw = 0.5*rho*Cd(Re(v))*A*v|v|` has no closed form and moreover drag vs v is non-monotonic due to crisis drop, potentially giving 1-3 solutions around crisis.

Characteristics:
- If `|Fb-Fw| <=1e-12` => terminal 0.
- If `DragCoefficient field <=0` => error containing "drag" (error contract from earlier)
- Otherwise find magnitude: search velocity magnitude interval where drag exceeds |delta|. Start low 0, high 1 m/s doubling until drag at high exceeds |delta| or high huge 1e4. However because drag may dip due to crisis, simple monotonic doubling may skip? Safer to scan velocity magnitude for sign changes of `h(v)=drag(v)-|delta|`: sample N=2000 points logarithmically or linearly up to high bound, look for sign changes, then bisect each bracket for up to 200 iterations until |h|<1e-9 or interval width <1e-9.
- Return signed terminal: sign = sign(Fb-Fw) positive up for light floating, negative down for heavy sinking. Return smallest magnitude root that satisfies? Actually if multiple roots due to crisis, physical terminal is usually smallest stable after crisis? For this task return smallest magnitude positive root (lowest speed) that satisfies drag=|delta|. Tests will accept any root within tight inverse tolerance 0.05 but will check inverse property using Re model.
- Depth validation: depth>=0,g>0,depth<=CrushDepth else error "crush".
- Must handle both heavy (negative) and light (positive) and crisis case high Re.

No explicit sqrt formula will pass because Cd varies.

**Equilibrium depth: Multi-root scanning + bisection + stability**

Zero-velocity net force `f(z)=Fb(z)-Fw` at zero velocity (drag zero). Find z where f(z)=0.

Because rho(z) increases (dual pycnocline) but V(z) decreases exponentially with pressure plus thermally, product rho*V can be non-monotonic with hump, leading to 0-3 equilibria. Naive bisection over [0,maxDepth] requiring f(lo)*f(hi)<0 fails when both ends same sign but interior hump crosses. You must implement robust scanning.

- Validate g>0, maxDepth>0, tolerance>0, maxDepth<=CrushDepth else error "crush".
- If |f(0)| <= Tolerance return 0.
- Scan interval [0,maxDepth] with sufficient resolution (e.g., at least 2000 equally spaced points) computing f at each. Look for sign changes: if f_i * f_{i+1} <=0 then bracket containing root. Also collect near-zero points where |f_i| < Tolerance.
- For each bracket, bisection up to 200 iterations until |f(mid)|<1e-9 or interval width < tolerance. Collect roots, deduplicate within tolerance*10.
- Return shallowest root for FindEquilibriumDepth. If no root error containing "no equilibrium".
- FindEquilibriumDepths returns all distinct roots sorted increasing. If no root error.
- FindEquilibriumDepthsWithStability returns slice of EquilibriumPoint with stability.

**Stability classification:**
For each equilibrium depth z_eq, compute derivative dF/dz via central difference (delta 0.1m): `dF = (f(z+0.1)-f(z-0.1))/0.2`. Stable if small downward displacement creates upward restoring force: i.e., `f(z+delta) >0` (up) when deeper, meaning dF/dz >0. So stable when derivative >0. Alternatively test via perturbation ±1m: if f(z+1)>0 and f(z-1)<0 then stable else unstable. Implement `FindEquilibriumDepthsWithStability` returning `[]EquilibriumPoint` sorted, each with Depth, Stable bool, FPrime derivative.

**Time to depth via adaptive RK4 with added mass:**

Integrate coupled ODEs from rest at surface z=0,v=0 to targetDepth>0 down-positive.

Equations: `dz/dt = v`, `dv/dt = Fnet_down / m_total(z)` where `Fnet_down = Fw - Fb(z) - 0.5*rho*Cd(Re)*A*v*|v|`, `m_total = m +0.5*rho*V`.

Start (0,0), step dt, loop until time exceeds maxTime. Adaptive error control via step doubling:
- For each step, compute one full step dt via RK4 to get (z1,v1)
- Compute two half steps dt/2 via RK4 to get (z2,v2)
- Error estimate `err = |z2-z1| + |v2-v1|` (or similar)
- If err > atol (1e-6) halve dt and retry
- If err < atol/4 double dt (capped to initial dt*2 or max) for next step
- Accept z2,v2 when err <= atol
- Interpolate time when z crosses target (linear interpolation between steps)
Return interpolated time.

Requirements:
- Validate targetDepth>0,g>0,dt>0,maxTime>0 else error
- If targetDepth>CrushDepth error "crush"
- If never reaches within maxTime error containing "not reached" or "time" or "unreachable"
- If during integration z exceeds CrushDepth error "crush"
- RK4 must be proper 4th order with k1..k4 and error estimation; Euler will fail accuracy test requiring within 2% of small-dt reference (tight). Tests compare dt=0.1 start vs dt=0.001 reference with added mass and crisis; Euler error >25%, fixed RK4 may be borderline.
- Must handle equilibrium blocking: heavy sink may have equilibrium before target where velocity decays; then will not reach => error.
- No explicit RK4 code block given; you must know method.

**Fleet batch with bounded worker pool and context cancellation:**

Functions preserve order, handle invalid inputs, must be race-safe and use concurrency primitives.

- BatchAnalyzeFleet(subs, fluid): If fluid invalid return nil,error. If subs nil or empty return empty slice. For each index i, if sub invalid => DiveResult{Index:i, State:"invalid"}. Else result of AnalyzeDive with Index=i. Preserve input order. To meet ultra-hard concurrency, implementation must use at least one goroutine with sync.WaitGroup and channel for ordering, plus semaphore to limit concurrency to 4 (bounded worker pool). Use `make(chan struct{}, 4)` as semaphore, acquire/release. Must be race-safe (run with -race). Must import context even if not used via context.Background? Tests check for "context", "WaitGroup", "chan", "go " substrings.

- BatchAnalyzeFleetWithTargets(subs, fluid, targetDepths, g): Validates fluid,g>0,len(subs)==len(targetDepths) else error containing "length" or "mismatch". Empty => empty. For each i, if invalid sub or target<0 => invalid state. If target>CrushDepth => result CrushRisk true and State "invalid". Else AnalyzeDive plus TimeToDepth to its specific target to populate TimeToDepth field. Preserve order, bounded worker pool similar.

- BatchAnalyzeFleetWithContext(ctx, subs, fluid, targetDepths, g): Same as WithTargets but accepts context.Context for cancellation. Must:
  - Check `ctx.Err()` before start, if cancelled return nil, ctx.Err()
  - Each worker must select on `ctx.Done()` channel: if cancelled, abort and return ctx error
  - Use same semaphore 4, WaitGroup, order preservation
  - If ctx cancelled during processing, return partial results and error containing "context" (e.g., `ctx.Err()`)
  - Tests will check immediate cancellation (context.WithCancel then cancel immediately) returns error containing "context", and normal background context works order preserved. Must contain `ctx.Done()` or `select` and `make(chan struct{}, 4)` and `WaitGroup` and `go`
  - Must be race-safe

- Worker pool limit 4 means at most 4 goroutines running analysis concurrently. Implement via semaphore channel.

## File Location
- Existing /app/submarine.go from Step1 must remain.
- New file /app/dive.go, package submarine, stdlib only (math, errors, sync, context). Both go vet and race must pass with -count=10.

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

Field order may vary but names/types must match.

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

Additional helper `DiveEnergyToDepth` may be defined but not required.

Detailed (no explicit formulas, you derive):

- **SubmergedFraction**: effective density / fluid density clamped [0,1], validate.

- **NetVerticalForce**: Fb-Fw at surface up positive, validate.

- **VerticalAcceleration**: Fnet/EffectiveMass.

- **NetVerticalForceAtDepth**: Includes continuous Re-dependent Cd via CdFromRe: compute rho via DensityAtDepth, vol via VolumeAtDepth, area vol/Length, mass EffectiveMass, Fb=rho*vol*g, Fw=mass*g, Re=rho*|velocity|*Length/mu with mu=SeawaterViscosity, Cd=CdFromRe(Re), drag=0.5*rho*Cd*area*velocity*|velocity|, Fnet=Fb-Fw - drag, up positive. Validate depth>=0,g>0,crush,fluid,sub.

- **CdFromRe**: continuous as described, Clift-Gauvin base + crisis logistic, clamped [0.08,1.2], handle Re<1e-6 return 1.2. Must use math.Exp, math.Pow.

- **TerminalVelocity**: Solves Fnet(z,v)=0 for v given depth. Implicit due to Cd(Re). Use scanning + bisection over velocity magnitude as described. Signed result. Error if DragCoefficient<=0 contains "drag". Validate depth,g,crush.

- **FindEquilibriumDepth**: Scanning + bisection as described, returns shallowest equilibrium. Validate.

- **FindEquilibriumDepths**: Returns all equilibria sorted ascending. Same validation, returns error if none.

- **FindEquilibriumDepthsWithStability**: Returns all equilibria with stability classification via derivative.

- **TimeToDepth**: Adaptive RK4 with added mass, error-controlled step doubling, interpolation for target crossing, crush and unreachable handling, tight 2% accuracy.

- **AnalyzeDive**: Validate sub+fluid, g=StandardGravity, surface calcs via reuse, ref depth 100m (or 0.9*CrushDepth if Crush smaller), compute EffectiveDensityAtDepth, RequiredBallastAtDepth, IsPossibleAtDepth, NetForceAtDepth at ref, StateAtDepth, VolumeAtDepth, equilibrium search up to min(CrushDepth,2000) tol 1e-3 (use FindEquilibriumDepth, if error set EquilibriumDepth=-1), terminal at surface depth 0 (if error 0), time to 100m via TimeToDepth dt 0.1 max 10000 (if error 0), MaxPressure at equilibrium depth if found else at ref depth via PressureAtDepth, CrushRisk if 100>CrushDepth.

- **BatchAnalyzeFleet** and **WithTargets** and **WithContext** as described with bounded worker pool, order preservation, invalid handling, context cancellation.

## Requirements
1. Reuse types/constants from submarine.go, do NOT redefine them (AST check: dive.go must NOT contain "type Submarine struct" nor "type Seawater struct" nor "const Tolerance").
2. File /app/dive.go package submarine, go vet passes, race passes with -count=10.
3. Struct DiveResult and EquilibriumPoint required fields present.
4. Functions exact signatures.
5. Stdlib only (math, errors, sync, context, etc).
6. No hardcoding; must compute via physics helpers.
7. Concurrency: must contain "go ", "sync.WaitGroup" or "WaitGroup", "chan", "context" substring, and semaphore pattern `make(chan struct{` or worker pool, and `ctx.Done()` or `select` for WithContext.
8. RK4: must contain "k1", "k2", "k3", "k4" and accuracy within 2% of small-dt reference (Euler fails), and error estimation handling (e.g., "err" or "atol" etc) for adaptive.
9. TerminalVelocity: must involve bisection loop and handle Re-dependent Cd via CdFromRe; simple sqrt constant Cd fails inverse check where Cd changes and crisis case.
10. Equilibrium: scanning + bisection required; naive f(lo)*f(hi) only fails multi-root case where both ends same sign but interior root exists.
11. Dual pycnocline and thermal hull must be reused via helpers, not reimplemented incorrectly.
12. CdFromRe must use math.Exp and math.Pow and produce bands: Re~100 => 0.8-1.5, Re~1e5 => 0.35-0.65, Re~1e6 => 0.08-0.25, crisis drop around 3e5.

## Grading (Hidden, Ultra Hard)
- SubmergedFraction clamped 500 random cases.
- NetForce surface and at depth with continuous Re drag sign, zero-velocity equals Fb-Fw.
- CdFromRe bands verification, crisis drop check around 3e5.
- TerminalVelocity inverse drag check tight tolerance 0.05 (not 0.1), signed, error drag, Re-crisis case where Cd switches, scanning required for bistable velocity.
- FindEquilibriumDepth: surface neutral 0, heavy sink no root error, sink-to-float with dual pycnocline brute-force within 0.3m (was 0.5), multi-root hump case where f(lo)*f(hi)>0 but root inside (requires scanning), crush error, tolerance small convergence.
- FindEquilibriumDepths: returns 2 roots sorted for hump case, empty error when none.
- FindEquilibriumDepthsWithStability: stability via perturbation ±1m, derivative sign.
- TimeToDepth: heavy reaches, light fails, accuracy 2% vs ref dt/10, Re-crisis accuracy, added mass effect (ignoring added mass fails >3% delta), crush error, interpolation, adaptive error control AST check.
- AnalyzeDive fields: State, Fraction, NetForce, EquilibriumDepth -1 when no root, MaxPressure, VolumeAtDepth, CrushRisk.
- BatchFleet: order preservation 50 subs, invalid marking, empty, mismatched lengths error, concurrency primitives present, semaphore limited to 4 (check source contains "4" and chan struct), race -count=10, context import, ctx.Done check.
- BatchWithContext: immediate cancel returns context error, background context works order preserved.
- No redefinition, go vet, race.
