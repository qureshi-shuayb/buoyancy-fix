# Step 2: Submarine Dive Dynamics, Vertical Motion & Fleet Batch Analysis

## Overview
This is **Step 2 of 2** in submarine simulator task. Builds directly on Step 1.

Step 1 file `/app/submarine.go` is preserved (`inherit_prior_session=true`). You MUST inspect it first:
```
cat /app/submarine.go
```
Do NOT redefine `Submarine`, `Seawater`, `Tolerance`, `StandardGravity`, `StandardSeawaterDensity` — Go will fail duplicate declaration. Add new logic in new file `/app/dive.go` same package `submarine` reusing existing types.

Goal: extend from sink/float decision to quantitative dive dynamics: submerged fraction, net vertical force, vertical acceleration, equilibrium analysis and batch fleet mission processing.

## Physics - Dive Dynamics

For fully submerged submarine:
```
EffectiveMass = DryMass + BallastLevel
EffectiveDensity = EffectiveMass / Volume
Fb = rho_fluid * Volume * g   (upward buoyant)
Fw = EffectiveMass * g       (downward weight)
Fnet = Fb - Fw  (positive = upward tendency to float/surface, negative = sink, ~0 = neutral)
Acceleration a = Fnet / EffectiveMass  (Newton 2nd law) m/s^2
  Positive a = accelerating upward
  Negative a = accelerating downward (sinking)
SubmergedFraction (for surfaced submarine analogy) = EffectiveDensity / FluidDensity clamped [0,1]
  <1 => positively buoyant, only fraction of volume needs submerging to balance (surfaced case)
  =1 => neutral or negative buoyant, fully submerged at equilibrium
  >1 raw would mean needs more than volume, clamp to 1.0
```

Interpretation:
- "float" => Fnet>0, a>0, Fraction<1
- "neutral" => |Fnet|~0 within tolerance, Fraction=1.0, a~0
- "sink" => Fnet<0, a<0, Fraction=1.0 clamped
- Edge: clamp Fraction to [0,1] always.

## File Location
- Reuse: /app/submarine.go MUST stay
- New file: /app/dive.go package submarine stdlib only
- Both compile together as package submarine
- Do NOT duplicate Object types constants

## Types to Define in /app/dive.go

Exact struct, field names case-sensitive:

```go
type DiveResult struct {
    Index            int     // position in batch input
    State            string  // "float", "sink", "neutral" or "invalid" for bad entry in batch
    Fraction         float64 // effectiveDensity / fluidDensity clamped [0,1]
    RequiredBallast  float64 // ballast needed for neutral = rho*V - DryMass
    IsPossible       bool    // required in [0,Capacity]
    EffectiveDensity float64 // effective density
    NetForce         float64 // Fb - Fw in Newtons (positive upward)
    Acceleration     float64 // m/s^2 = NetForce / EffectiveMass
}
```

You may define helper error types, but this struct must exist exactly.

## Functions to Implement (Exact Signatures)

All exported in package submarine, in /app/dive.go:

```go
// SubmergedFraction returns effectiveDensity/fluidDensity clamped [0,1]
func SubmergedFraction(sub Submarine, fluid Seawater) (float64, error)

// NetVerticalForce returns Fb - Fw (positive upward)
func NetVerticalForce(sub Submarine, fluid Seawater, g float64) (float64, error)

// VerticalAcceleration returns Fnet / EffectiveMass
func VerticalAcceleration(sub Submarine, fluid Seawater, g float64) (float64, error)

// AnalyzeDive combines all metrics for single submarine
func AnalyzeDive(sub Submarine, fluid Seawater) (DiveResult, error)

// BatchAnalyzeFleet analyzes many subs in same fluid preserving order
// If fluid invalid returns nil, error. If individual sub invalid, its result State="invalid" Fraction 0, continue.
func BatchAnalyzeFleet(subs []Submarine, fluid Seawater) ([]DiveResult, error)
```

### Detailed Behavior

**SubmergedFraction**:
1. Validate sub via Validate() and fluid Validate(). If invalid 0, error.
2. Compute effectiveDensity via EffectiveDensity() propagate error.
3. fraction = effectiveDensity / fluid.Density
4. Clamp: if <0 =>0, if >1 =>1
5. Return.

**NetVerticalForce**:
1. Validate fluid, sub, g>0 else error
2. Fb via BuoyantForce or fluid.Density*Volume*g
3. Fw via WeightForce
4. Return Fb - Fw

**VerticalAcceleration**:
1. Call NetVerticalForce
2. Divide by EffectiveMass (must be >0 else error)
3. Return.

**AnalyzeDive**:
1. Validate sub, fluid
2. effectiveDensity via EffectiveDensity()
3. state via CheckSubmarineState (MUST reuse Step1 function, not duplicate logic with different tolerance)
4. requiredBallast via RequiredBallastForNeutral
5. isPossible via IsNeutralBuoyancyPossible
6. fraction via SubmergedFraction
7. netForce via NetVerticalForce with StandardGravity (use constant, not hardcoded 9.81, to prove reuse)
8. acceleration = netForce / EffectiveMass
9. Return DiveResult{Index:0, State, Fraction, RequiredBallast, IsPossible, EffectiveDensity, NetForce, Acceleration}
10. If any validation fails return zero-value result and error.

**BatchAnalyzeFleet**:
- First validate fluid, if invalid return nil, error.
- If subs nil or empty return empty slice []DiveResult{} and nil error (not error)
- For each i produce DiveResult Index:i
  - If sub i invalid (Validate fails) => State="invalid", Fraction 0, NetForce 0, etc and continue. Do NOT fail whole batch.
  - Else compute via AnalyzeDive and set Index=i
- Return slice same order as input.
- Never return fraction >1, always clamped.
- Deterministic, sequential.

### Example Usage

```go
fluid := submarine.Seawater{Density: 1025}
sub := submarine.Submarine{DryMass:5000, Volume:10, Length:20, BallastCapacity:6000, BallastLevel:0}
frac, _ := submarine.SubmergedFraction(sub, fluid) // 0.487...

fnet, _ := submarine.NetVerticalForce(sub, fluid, submarine.StandardGravity) // ~51502.5 N upward
acc, _ := submarine.VerticalAcceleration(sub, fluid, submarine.StandardGravity) // ~10.3 m/s^2

res, _ := submarine.AnalyzeDive(sub, fluid)
// res.State=="float", Fraction~0.487, RequiredBallast 5250, IsPossible true, NetForce>0

fleet := []submarine.Submarine{
  {DryMass:5000, Volume:10, Length:20, BallastCapacity:6000, BallastLevel:0}, // float
  {DryMass:5000, Volume:10, Length:20, BallastCapacity:6000, BallastLevel:5250}, // neutral
  {DryMass:11000, Volume:10, Length:20, BallastCapacity:2000, BallastLevel:1000}, // sink
}
results, _ := submarine.BatchAnalyzeFleet(fleet, fluid)
// results[0].State float, [1] neutral, [2] sink

bad := submarine.Submarine{DryMass:0, Volume:10, Length:20, BallastCapacity:1000, BallastLevel:0}
results2, _ := submarine.BatchAnalyzeFleet([]submarine.Submarine{sub, bad, fleet[1]}, fluid)
// results2[1].State=="invalid"
```

## Requirements
1. Context-following: File /app/submarine.go exists, read it, reuse types/constants/functions.
2. File /app/dive.go package submarine, both files go vet passes.
3. Struct DiveResult must exist exact fields.
4. Functions exact signatures exported.
5. Physics: Fraction = rho_eff/rho_fluid clamped [0,1], Fnet=Fb-Fw, Acceleration=Fnet/EffectiveMass
6. Tolerance: Must use existing Tolerance constant via CheckSubmarineState, not define new tolerance or hardcode 1e-6.
7. Error handling: non-positive mass/volume/gravity etc non-nil error. Batch: fluid invalid => whole error, individual invalid => State "invalid" with zeros not whole error.
8. Deterministic pure stdlib only no network file I/O.
9. Batch order preserves input.
10. No hardcoding lookup table.
11. Go module: keep same, go test ./... works from /app.
12. Anti-cheating: AST check ensures dive.go does NOT contain "type Submarine struct" nor "type Seawater struct" nor "const Tolerance" redefinition. If duplicates exist tests fail.

## Grading (Hidden)
- SubmergedFraction many combos: 500/1025 ~0.487, neutral 1025/1025 1.0 clamped, sink 1200/1025 1.0 clamped
- NetVerticalForce = Fb-Fw within 1e-6, positive for float negative for sink ~0 for neutral
- VerticalAcceleration = Fnet/EffectiveMass
- AnalyzeDive returns correct State matching Step1, Fraction, RequiredBallast, IsPossible, NetForce, Acceleration
- BatchAnalyze mixed float/sink/neutral + invalid entry handling order index correct fluid invalid error empty input
- Reuse check no redefinition, tolerance reuse neutral boundary 5e-10 vs 1e-5 consistent
- No external deps go vet passes both files compile together

## What NOT to Do
- Do NOT duplicate Submarine/Seawater types or Tolerance; will cause compile error redeclared
- Do NOT assume BallastLevel 0; use EffectiveMass
- Do NOT return fraction >1 for sink; clamp
- Do NOT drop invalid objects in batch; keep length same mark "invalid"
- Do NOT modify /app/submarine.go to break Step1 tests; cascade grading Step2 verifier also runs Step1 tests
- Do NOT change package name or file locations
