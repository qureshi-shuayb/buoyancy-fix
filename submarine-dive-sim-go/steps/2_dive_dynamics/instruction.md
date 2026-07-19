# Step 2: Submarine Dive Dynamics, Equilibrium Search, RK4 Integration & Concurrent Fleet Analysis

## Overview
This is **Step 2 of 2** in submarine simulator task. Builds directly on Step 1.

Step 1 file `/app/submarine.go` is preserved (`inherit_prior_session=true`). You MUST inspect it first:
```
cat /app/submarine.go
```
Do NOT redefine `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity`, `DepthDensityGradient`, `MinimumVolumeFraction` — Go will fail duplicate declaration. Add new logic in new file `/app/dive.go` same package `submarine` reusing existing types/constants/methods.

Goal: extend from surface sink/float decision to realistic dive dynamics: depth-dependent buoyancy, quadratic drag, terminal velocity, equilibrium depth via numerical root-finding, time-to-depth via RK4 integration, and concurrent fleet batch processing.

## Physics - Dive Dynamics (no spoilers, derive yourself)

### Buoyancy with Depth and Drag
Your Step1 already implements density at depth growing linearly with depth and hull volume shrinking under pressure, plus hydrostatic pressure as integral of density*g. Reuse those.

For dynamics, consider vertical motion. Effective mass is dry plus ballast, constant.

Forces (choose sign convention consistently and document):
- Buoyancy is upward, arising from weight of displaced fluid at local depth (use local density and local volume).
- Weight is downward.
- Drag is quadratic, opposing direction of motion, magnitude proportional to fluid density, reference cross-sectional area, drag coefficient, and square of speed. Reference area is derived from submarine geometry: approximate cross-section as volume divided by length (like cylinder volume = A*L). Drag coefficient comes from Submarine.DragCoefficient field.

Net vertical force is buoyant minus weight minus drag contribution where drag sign opposes velocity. If you adopt upward positive, drag term is proportional to v*|v| and subtracted with appropriate sign so it always opposes motion. If you adopt downward positive, flip signs accordingly — but you must be consistent across functions and document choice. Hidden tests check sign consistency, not absolute sign, but we define expected convention below for terminal velocity and time-to-depth.

For surface functions (original spec) positive was defined as upward (Fb - Fw). Keep that for backward compatibility: NetVerticalForce surface returns upward positive. For new depth-aware functions we also require upward positive for simplicity, unless you explicitly convert for time-to-depth integration.

### Terminal Velocity
When a submarine moves steadily, buoyancy, weight, and drag balance. The velocity at which net force zero (with drag) is terminal velocity. It must be signed: positive upward means floating up, negative downward means sinking, zero when neutral. If drag coefficient is zero, terminal velocity conceptually is infinite (no drag to balance) — return error in that case. Derive expression relating drag magnitude to imbalance |Fb - Fw|.

### Equilibrium Depth
At zero velocity, net force depends only on depth via rho(z) and V(z). At surface, a heavy submarine sinks (negative net). At deeper depth, density increases (more buoyancy) but volume decreases under pressure (less buoyancy). For small compressibility, the density increase may dominate and net may become less negative or even positive, meaning there is a depth where forces balance. Conversely a light submarine may float at surface but become neutral deeper.

Finding this equilibrium has no closed form when both density gradient and compressibility are present (pressure appears quadratically). You must implement iterative root-finding — bisection is recommended. Search interval [0, maxDepth]. Check that net force at ends brackets zero (opposite signs). If not, return error indicating no equilibrium in range. Iterate until interval width < tolerance or |Fnet| small. Must validate inputs: g>0, maxDepth>0, tolerance>0, depth within crush.

### Time to Depth via RK4
To know how long it takes to sink to a target depth, integrate equations of motion:

We use depth positive downward, velocity positive downward for intuitive dive time (or you may use upward positive with conversion dz/dt = -v — document). State is (z, v). Derivatives: dz/dt = velocity (if velocity positive down) or -velocity (if velocity positive up) — pick one and be consistent. dv/dt = net force (in consistent sign) divided by effective mass.

Because forces depend on depth (rho, volume) and velocity (drag), no analytic solution exists. Implement classic 4th-order Runge-Kutta (RK4) with fixed timestep dt. Start at rest: z=0, v=0 at t=0. Step forward until z >= targetDepth or time exceeds maxTime. Return elapsed time. If target beyond crush depth, error. If dt<=0 or maxTime<=0, error. If never reaches target within maxTime, error.

RK4 must be implemented with four evaluations per step (k1..k4) for both depth and velocity. Using Euler will not meet accuracy tests — tests compare your RK4 result to a reference small-dt RK4 and require within 5% relative error and also more accurate than Euler would be for large dt.

### Fleet Batch Analysis with Concurrency
Real missions involve many submarines. BatchAnalyzeFleet must analyze a fleet concurrently:

- Must use goroutines, sync.WaitGroup, and a semaphore channel limiting max concurrency to 4 (or min(len,4)).
- Preserve input order: result[i] corresponds to subs[i].
- If fluid is invalid, return nil, error.
- If slice nil or empty, return empty slice and nil error.
- For each submarine: if invalid (Validate fails), produce DiveResult with State="invalid", Index=i, and continue — do NOT fail whole batch.
- If valid, compute via AnalyzeDive and set Index=i.
- Must be race-safe: `go test -race` must pass.
- AST check will verify source contains concurrent primitives: "go " (goroutine), "WaitGroup", and channel usage for semaphore.

This adds Go-specific difficulty beyond physics.

## File Location
- Reuse: /app/submarine.go MUST stay
- New file: /app/dive.go package submarine stdlib only (allow sync, math, errors, fmt, sort, etc but no external deps)
- Both files compile together as package submarine
- Do NOT duplicate types/constants

## Types to Define in /app/dive.go

Exact struct, field names case-sensitive, but you may add additional fields beyond required minimum. Required fields must exist with exact types; extra fields allowed.

```go
type DiveResult struct {
    Index            int     // position in batch input
    State            string  // "float", "sink", "neutral" or "invalid" for bad entry in batch
    StateAtDepth     string  // state at reference depth 100m (float/sink/neutral/invalid)
    Fraction         float64 // submerged fraction at surface: effectiveDensity/fluidDensity clamped [0,1]
    RequiredBallast  float64 // ballast needed for neutral at surface
    IsPossible       bool    // required in [0,Capacity] at surface
    EffectiveDensity float64 // at surface
    NetForce         float64 // at surface, upward positive (Fb-Fw)
    Acceleration     float64 // at surface, upward positive
    EquilibriumDepth float64 // depth where Fnet=0 at zero velocity, -1 if none found
    TerminalVelocity float64 // signed, upward positive (negative means sinking)
    TimeToDepth      float64 // time to reach 100m target via RK4, or 0 if not computed
    MaxPressure      float64 // pressure at equilibrium or at 100m
    VolumeAtDepth    float64 // volume at 100m reference depth
    CrushRisk        bool    // true if target or equilibrium beyond crush depth
}
```

You may define helper error types, but this struct must exist exactly with at least those fields. Tests check field existence via compilation.

## Functions to Implement (Exact Signatures)

All exported in package submarine, in /app/dive.go:

Old (must keep, extended behavior):
```go
// SubmergedFraction returns effectiveDensity/fluidDensity clamped [0,1] at surface
func SubmergedFraction(sub Submarine, fluid Seawater) (float64, error)

// NetVerticalForce returns Fb - Fw at surface, upward positive
func NetVerticalForce(sub Submarine, fluid Seawater, g float64) (float64, error)

// VerticalAcceleration returns Fnet / EffectiveMass at surface
func VerticalAcceleration(sub Submarine, fluid Seawater, g float64) (float64, error)

// AnalyzeDive combines all metrics for single submarine at surface plus equilibrium, terminal, time
func AnalyzeDive(sub Submarine, fluid Seawater) (DiveResult, error)

// BatchAnalyzeFleet analyzes many subs in same fluid preserving order, concurrent worker-pool
func BatchAnalyzeFleet(subs []Submarine, fluid Seawater) ([]DiveResult, error)
```

New depth-aware dynamics:
```go
// NetVerticalForceAtDepth returns net upward force at depth with velocity (including drag), upward positive
func NetVerticalForceAtDepth(sub Submarine, fluid Seawater, depth float64, velocity float64, g float64) (float64, error)

// TerminalVelocity returns signed terminal velocity at given depth, upward positive (negative sinking)
// Error if drag coefficient <=0, or invalid inputs
func TerminalVelocity(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error)

// FindEquilibriumDepth finds depth in [0,maxDepth] where net force zero at zero velocity via bisection/tolerance
// Returns depth, error if no root in interval or invalid inputs or beyond crush
func FindEquilibriumDepth(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) (float64, error)

// TimeToDepth returns time to reach targetDepth from rest at surface using RK4 integration
// dt is timestep, maxTime is cutoff. Error if not reached within maxTime, or invalid inputs, or beyond crush
func TimeToDepth(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) (float64, error)

// BatchAnalyzeFleetWithTargets per-sub target depths, concurrent, order preserved
func BatchAnalyzeFleetWithTargets(subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult, error)
```

### Detailed Behavior (qualitative)

**SubmergedFraction**:
- Validate sub and fluid. If invalid return 0, error.
- Effective density surface divided by fluid density, clamped to [0,1].

**NetVerticalForce**:
- Validate fluid, sub, g>0 else error.
- Compute buoyant and weight at surface, return difference upward positive.

**VerticalAcceleration**:
- Call NetVerticalForce, divide by EffectiveMass.

**NetVerticalForceAtDepth**:
- Validate fluid, sub, depth>=0, g>0, depth <= CrushDepth else crush error. Velocity may be any real (can be 0).
- Compute density at depth, volume at depth, buoyant force at depth.
- Weight force.
- Cross-sectional area = Volume / Length (surface volume over length, approximate).
- Drag magnitude proportional to 0.5 * rhoAtDepth * DragCoefficient * Area * v^2, direction opposing velocity. If DragCoefficient==0, drag 0.
- Net upward = buoyant - weight - dragTerm where dragTerm = 0.5*rho*Cd*A*v*|v| (since v*|v| carries sign). Ensure when v=0 drag 0, reduces to Fb-Fw at depth.
- Return.

**TerminalVelocity**:
- Validate fluid, sub, depth>=0, g>0, depth <= CrushDepth, DragCoefficient>0 else error containing "drag".
- Compute Fb at depth, Fw, difference. If difference near zero (within tolerance of force?), terminal 0.
- Terminal magnitude solves drag = |Fb-Fw|: 0.5*rho*Cd*A*v^2 = |Fb-Fw|. So |v_term| = sqrt(2*|Fb-Fw|/(rho*Cd*A)).
- Signed: positive upward if Fb>Fw (floats up), negative downward if Fb<Fw (sinks). Return signed.
- If denominator zero (rho or Cd or A zero) error.

**FindEquilibriumDepth**:
- Validate fluid, sub, g>0, maxDepth>0, tolerance>0 else error. tolerance e.g., 1e-6.
- If sub's crush depth < maxDepth, max search is min(maxDepth, crushDepth) ? But return error if equilibrium beyond crush? Simpler: if maxDepth > CrushDepth, still search up to CrushDepth, but if no root within, error. If depth beyond crush needed, error crush.
- Define function f(z) = NetVerticalForceAtDepth(z, velocity=0). Upward positive.
- Evaluate f(0) and f(maxDepth). If same sign and not zero, no root → return 0, error containing "no equilibrium" or "no root".
- Else bisection: mid = (lo+hi)/2, evaluate f(mid). Narrow interval keeping bracket. Stop when hi-lo < tolerance or |f(mid)| small. Max iterations e.g., 100 or until tolerance.
- Return mid depth. If f fails due to crush within interval, error crush.
- For nearly neutral at surface (f(0) within tolerance of zero), return 0 as equilibrium.

**TimeToDepth**:
- Validate fluid, sub, targetDepth>0, g>0, dt>0, maxTime>0 else error. targetDepth must <= CrushDepth else error crush. Also Depth must >=0.
- Start state: time=0, depth=0, velocity=0 (velocity upward positive? but we use upward positive, so initial velocity 0).
- For RK4 with state (z, v) where z is depth positive downward for target tracking, but v is velocity upward positive? Need conversion. Choose either:
  Option: keep v upward positive, then dz/dt = -v (since depth down increases when v negative). dv/dt = Fnet_up / mass.
  Option alternative: use v positive down for integration, with Fnet_down = -Fnet_up. Either works as long as you reach target.
  Expected behavior: heavy submarine sinks (Fnet negative up) => v becomes negative (down in up frame) => depth increases. Light floats up => never reaches target depth >0, should return error "target not reachable" or timeout.
- Implement RK4: For each step, compute k1 = derivative at current, k2 at half step, etc. For system of two ODEs, you need k for both z and v.
- Step until z >= targetDepth or time > maxTime. Return time when crossed (interpolate linear between steps for better accuracy).
- If not reached within maxTime, error.
- Must handle crush: if z exceeds crush during integration, error crush.
- Tests check accuracy: with dt=0.1 vs reference dt=0.01, results within 5% for a heavy case. Also check that using Euler would fail accuracy for larger dt, enforcing RK4.

**AnalyzeDive**:
- Validate sub, fluid.
- Compute surface effective density, state, required ballast, possible, fraction, net force, acceleration using surface methods or reuse Step1 functions (must reuse CheckSubmarineState, RequiredBallastForNeutral, etc., not duplicate logic).
- Compute equilibrium depth up to maxDepth = CrushDepth or 1000m, tolerance 1e-6 via FindEquilibriumDepth. If no equilibrium, set EquilibriumDepth = -1.
- Compute terminal velocity at surface depth 0 (or at equilibrium depth if exists) — we define at surface depth 0 for simplicity.
- Compute time to reach 100m via TimeToDepth with g=StandardGravity, dt=0.1, maxTime=10000. If error, set TimeToDepth=0 and handle crush risk.
- MaxPressure = pressure at equilibrium if exists else at 100m.
- VolumeAtDepth at 100m reference.
- StateAtDepth = state at 100m via CheckSubmarineStateAtDepth.
- CrushRisk = target 100m > CrushDepth or equilibrium beyond crush.
- Return DiveResult with all fields.

**BatchAnalyzeFleet**:
- First validate fluid, if invalid return nil, error.
- If subs nil or empty return empty slice []DiveResult{} and nil error.
- Must use concurrent worker pool: create semaphore channel with capacity min(len(subs),4), WaitGroup, results slice pre-allocated.
- For each index, launch goroutine that acquires semaphore, computes AnalyzeDive, sets result Index=i, handles invalid subs => State="invalid" etc., releases semaphore.
- Preserve order.
- Must not data race.
- Return slice same order.

**BatchAnalyzeFleetWithTargets**:
- Validate fluid, g>0, subs and targetDepths same length else error.
- If fluid invalid return nil error.
- Else similar concurrent pool but for each sub uses targetDepths[i] for TimeToDepth.
- Invalid sub => State="invalid".
- CrushRisk true if target beyond crush.
- Preserve order.

### No Numeric Spoilers
This instruction gives no expected numeric outputs. You must compute everything.

## Requirements
1. Context-following: File /app/submarine.go exists, read it, reuse types/constants/functions.
2. File /app/dive.go package submarine, both files go vet passes, go test -race passes.
3. Struct DiveResult must exist exact at least required fields.
4. Functions exact signatures exported.
5. Physics: density at depth linear, pressure integral, volume compression clamped, drag quadratic, terminal velocity sqrt, equilibrium via bisection, time via RK4.
6. Tolerance: Must use existing Tolerance constant via CheckSubmarineState, not define new tolerance for state.
7. Error handling: detailed as above, crush handling.
8. Deterministic pure stdlib only no network file I/O.
9. Concurrency: Batch must contain goroutine + WaitGroup + channel semaphore. AST check enforces.
10. Anti-cheating: AST check ensures dive.go does NOT contain "type Submarine struct" nor "type Seawater struct" nor "const Tolerance" redefinition.
11. Go module: keep same, go test ./... works from /app, with -race.
12. RK4 required: file must contain k1,k2,k3,k4 or similar RK4 pattern; simple Euler will fail accuracy tests.

## Grading (Hidden)
- SubmergedFraction clamped [0,1] many combos including depth version
- NetVerticalForce surface and at depth: upward positive, drag zero when v=0, drag opposes motion sign check with both positive and negative velocities
- TerminalVelocity: magnitude solves drag balance, sign correct, zero drag error, inverse check F_drag at v_term ≈ |Fb-Fw|
- FindEquilibriumDepth: bisection correctness vs brute-force scan with step 0.1, tolerance handling, no equilibrium error, crush error, returns 0 when neutral at surface
- TimeToDepth: RK4 accuracy within 5% vs small dt reference, Euler would fail, crush detection, unreachable (float) error, dt/maxTime validation
- AnalyzeDive returns correct State, Fraction, RequiredBallast, IsPossible, NetForce, Acceleration plus equilibrium, terminal, time, volume, pressure, crush risk, state at depth
- Batch fleet concurrent: order preserved, invalid handling, fluid invalid whole error, empty, race detector passes, concurrency primitives present
- Reuse check no redefinition
- No external deps

## What NOT to Do
- Do NOT duplicate Submarine/Seawater types or Tolerance; will cause compile error redeclared
- Do NOT assume compressibility 0 or drag 0; tests include varied values
- Do NOT use Euler for time integration; accuracy tests require RK4
- Do NOT return fraction >1 for sink; clamp
- Do NOT drop invalid objects in batch; keep length same mark "invalid"
- Do NOT sequential batch; must use concurrent worker pool
- Do NOT modify /app/submarine.go to break Step1 tests
