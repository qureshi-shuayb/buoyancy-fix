# Step 1: Submarine Basic Buoyancy Control - Sink / Float / Neutral

## Overview
This is **Step 1 of 2** in a multi-turn submarine simulator T-Bench task. You are building a Go package that models submarine buoyancy via Archimedes' principle with ballast tank control.

Step 1 implements foundational types and basic sink/float/neutral decision with ballast. **Step 2 will extend the same package** to compute dive dynamics, vertical acceleration, equilibrium analysis and batch fleet processing. Step 2 must reuse your `Submarine` and `Seawater` types without redefining them — so define them cleanly now.

Goal for this step: Given submarine dry mass, volume, ballast capacity and current ballast level, plus seawater density, determine effective mass/density, buoyant vs weight forces, required ballast for neutral buoyancy, and whether submarine will float (positively buoyant, rise to surface), sink (negatively buoyant), or be neutrally buoyant.

## Physics Background
Archimedes' principle for fully submerged submarine:
```
EffectiveMass = DryMass + BallastLevel
EffectiveDensity = EffectiveMass / Volume
Fb = rho_fluid * Volume * g   (buoyant force upward)
Fw = EffectiveMass * g = EffectiveDensity * Volume * g  (weight downward)
Fnet = Fb - Fw
```

Decision rule:
- If `EffectiveDensity < FluidDensity - Tolerance` => Fb > Fw => **"float"** (positively buoyant, will rise / stay surfaced)
- If `EffectiveDensity > FluidDensity + Tolerance` => Fb < Fw => **"sink"** (negatively buoyant)
- If `|EffectiveDensity - FluidDensity| <= Tolerance` => **"neutral"**

Critical nuance: Simple `==` misses neutral buoyancy. MUST use tolerance. Tests include diff 5e-10 (neutral) vs 1e-5 (not neutral).

Required ballast for neutral buoyancy (physics derivation):
```
At neutral: EffectiveMass = rho_fluid * Volume
=> DryMass + RequiredBallast = rho_fluid * Volume
=> RequiredBallast = rho_fluid * Volume - DryMass
```
This may be outside [0, Capacity] meaning neutral impossible with current submarine (too heavy even empty, or too light even full). Return the computed value anyway; possibility check is separate function.

## File Location and Package
- Implement in single file: `/app/submarine.go`
- Package: `submarine` (i.e., `package submarine`)
- Go 1.23+, standard library only. No external imports beyond `math`, `fmt`, `errors` if needed.
- File must compile standalone (tests will `go test` importing it).
- Do not create go.mod with conflicting name; `go vet` must pass.

## Constants to Define

You MUST define and use these exported constants:
```go
const Tolerance = 1e-9               // absolute density tolerance kg/m3
const StandardGravity = 9.81         // m/s^2
const StandardSeawaterDensity = 1025.0 // kg/m3 typical seawater
```

## Types to Define

```go
// Submarine represents a submersible with ballast tanks.
// All fields have constraints >0 except BallastLevel which can be 0.
type Submarine struct {
    DryMass         float64 // kg, >0 mass without ballast water
    Volume          float64 // m^3, >0 total hull displacement volume
    Length          float64 // m, >0 overall length (needed Step2)
    BallastCapacity float64 // kg, >0 max ballast water mass
    BallastLevel    float64 // kg, >=0 and <= BallastCapacity current ballast
}

type Seawater struct {
    Density float64 // kg/m3, >0  e.g. 1025 seawater, 1000 fresh
}
```

Methods:
- `func (s Submarine) Validate() error` - error if DryMass<=0, Volume<=0, Length<=0, BallastCapacity<=0, BallastLevel<0, or BallastLevel > Capacity. Error message must contain "mass", "volume", "length", "capacity", or "ballast" case-insensitive for relevant case.
- `func (s Submarine) EffectiveMass() float64` - DryMass + BallastLevel (pure, no error)
- `func (s Submarine) EffectiveDensity() (float64, error)` - EffectiveMass/Volume, error if Validate fails or Volume<=0
- `func (f Seawater) Validate() error` - error if Density<=0

## Functions to Implement (Exact Signatures)

All exported.

```go
// BuoyantForce Fb = rho_fluid * Volume * g
func BuoyantForce(fluid Seawater, sub Submarine, g float64) (float64, error)

// WeightForce Fw = EffectiveMass * g
func WeightForce(sub Submarine, g float64) (float64, error)

// RequiredBallastForNeutral returns rho_fluid*Volume - DryMass (may be <0 or >Capacity)
// Error only if inputs invalid (DryMass, Volume, Length, BallastCapacity, fluid Density <=0)
// Do NOT validate BallastLevel for this function, only dry properties.
func RequiredBallastForNeutral(sub Submarine, fluid Seawater) (float64, error)

// CheckSubmarineState returns "float", "sink", or "neutral" via density tolerance rule
func CheckSubmarineState(sub Submarine, fluid Seawater) (string, error)

// IsNeutralBuoyancyPossible returns true if RequiredBallast in [0, Capacity]
func IsNeutralBuoyancyPossible(sub Submarine, fluid Seawater) (bool, error)
```

### Detailed Behavior

**BuoyantForce**:
- Validate fluid and sub via Validate(), g>0 else error, return 0
- Return fluid.Density * sub.Volume * g  (Newtons)

**WeightForce**:
- Validate sub, g>0 else error
- Return EffectiveMass * g

**RequiredBallastForNeutral**:
- Validate DryMass>0, Volume>0, Length>0, BallastCapacity>0, fluid.Density>0 else error
- Return fluid.Density*Volume - DryMass (float, may be negative or >Capacity)

**CheckSubmarineState**:
- Validate sub and fluid
- EffectiveDensity via EffectiveDensity()
- diff = effDensity - fluid.Density
- If |diff|<=Tolerance => "neutral"
- Else if diff<0 => "float"
- Else => "sink"
- Exact lower-case strings.

**IsNeutralBuoyancyPossible**:
- Validate dry properties + fluid (same as RequiredBallast)
- Compute required, return required>=0 && required<=Capacity, nil error. Error only if inputs invalid.

### Example Usage
```go
fluid := submarine.Seawater{Density: 1025}
sub := submarine.Submarine{DryMass:5000, Volume:10, Length:20, BallastCapacity:6000, BallastLevel:0}
// EffectiveMass 5000, EffectiveDensity 500 -> float
state, _ := submarine.CheckSubmarineState(sub, fluid) // "float"

sub2 := submarine.Submarine{DryMass:5000, Volume:10, Length:20, BallastCapacity:6000, BallastLevel:5250}
// EffectiveMass 10250, Density 1025 -> neutral
state2, _ := submarine.CheckSubmarineState(sub2, fluid) // "neutral"

req, _ := submarine.RequiredBallastForNeutral(sub, fluid) // 5250 = 1025*10 -5000
possible, _ := submarine.IsNeutralBuoyancyPossible(sub, fluid) // true

fb, _ := submarine.BuoyantForce(fluid, sub, submarine.StandardGravity) // 100552.5 N
fw, _ := submarine.WeightForce(sub, submarine.StandardGravity) // 49050 N
// Fb > Fw => float
```

## Requirements
1. File /app/submarine.go package submarine
2. Constants exactly Tolerance 1e-9, StandardGravity 9.81, StandardSeawaterDensity 1025.0
3. Structs exactly field names/types
4. All functions+methods exact signatures exported
5. Tolerance handling for neutral
6. Error handling non-nil on non-positive, ballast level > capacity
7. Stdlib only, deterministic pure functions, go vet passes
8. Step2 compatibility: do NOT rename fields/package. Step2 will have inherit_prior_session=true and will import same package, add file /app/dive.go using your types. If you change struct names, Step2 cascade fails.

## Grading (Hidden Tests)
- Constants values
- EffectiveMass = DryMass+BallastLevel
- EffectiveDensity = EffectiveMass/Volume, error cases mention mass/volume
- Validate errors for all invalid combos
- BuoyantForce and WeightForce formulas within 1e-6, error cases
- RequiredBallastForNeutral = rho*V - DryMass, many combos, outside capacity still returns value
- IsNeutralBuoyancyPossible checks range
- CheckSubmarineState float/sink/neutral including Tolerance boundary 5e-10 neutral vs 1e-5 not neutral
- No hardcoded lookup table, must compute via formulas

## Anti-Cheating
- Do NOT hardcode return per mass lookup; must compute via formulas
- Do NOT skip tolerance with ==
- Do NOT modify test files; they are read-only in evaluation
