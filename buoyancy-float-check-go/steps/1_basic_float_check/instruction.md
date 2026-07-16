# Step 1: Basic Buoyancy Float / Sink / Neutral Check in Go

## Overview
This is **Step 1 of 2** in a multi-turn T-Bench task. You are building a Go package that models buoyancy via Archimedes' principle.

Step 1 implements the foundational types and basic float/sink/neutral decision. **Step 2 will extend the same package** to compute submerged volume fraction, equilibrium depth for partially submerged bodies, and batch processing. Step 2 must reuse your `Object` and `Fluid` types without redefining them — so define them cleanly now.

Goal for this step: Given an object's mass/volume (hence density) and a fluid's density, determine whether the object floats, sinks, or is neutrally buoyant.

## Physics Background
Archimedes' principle: an object immersed in fluid experiences an upward buoyant force:

```
Fb = rho_fluid * V_displaced * g
Fw = m_object * g = rho_object * V_object * g
```

Where:
- `rho_fluid` = fluid density (kg/m^3)
- `rho_object` = object density = mass / volume (kg/m^3)
- `V_displaced` = volume of fluid displaced; for fully immersed check use object volume
- `g` = gravitational acceleration (m/s^2)

Decision rule (for fully immersed comparison):
- If `rho_object < rho_fluid` → `Fb > Fw` → **"float"** (object rises, will partially submerge at equilibrium)
- If `rho_object > rho_fluid` → `Fb < Fw` → **"sink"**
- If `|rho_object - rho_fluid| <= Tolerance` → **"neutral"** (neutral buoyancy)

**Critical nuance:** Simple `==` misses neutral buoyancy. You MUST use a tolerance. A naive `rho_obj == rho_fluid` check will fail grading — use absolute tolerance constant below.

## File Location and Package

- Implement in single file: `/app/buoyancy.go`
- Package: `buoyancy` (i.e., `package buoyancy`)
- Go 1.23+, standard library only. No external imports beyond `math`, `fmt`, `errors` (if needed).
- File must compile standalone (tests will `go test` with `package buoyancy` importing it).
- Do not create `go.mod` with conflicting module name; if needed, `go mod tidy` should still allow `go vet`.

## Constants to Define

You MUST define and use these exported constants:

```go
const Tolerance = 1e-9          // absolute density tolerance for neutral buoyancy (kg/m^3)
const StandardGravity = 9.81    // m/s^2, Earth's standard gravity
```

`Tolerance` is the maximum absolute difference between object and fluid density that still counts as neutral. Use `math.Abs(objDensity - fluidDensity) <= Tolerance`.

## Types to Define

```go
// Object represents a physical body.
// All fields must be > 0 to be valid.
type Object struct {
    Mass   float64 // kg, >0
    Volume float64 // m^3, >0
    Height float64 // m, total vertical height when upright, >0
                 // Height is not needed for basic float check, but STEP 2 requires it.
                 // Validate it now so Step 2 can reuse without refactoring.
}

// Fluid represents a surrounding fluid.
type Fluid struct {
    Density float64 // kg/m^3, >0 (e.g., water ~1000, seawater ~1025, air ~1.225)
}
```

Methods:
- `func (o Object) Density() (float64, error)` — returns `o.Mass / o.Volume`. Error if `Volume <= 0` or `Mass <= 0`. Error message must contain "volume" or "mass" (case-insensitive) for invalid cases.
- `func (o Object) Validate() error` — error if any of Mass, Volume, Height <= 0.
- `func (f Fluid) Validate() error` — error if Density <= 0.

Use `errors.New` or `fmt.Errorf`; exact wording not checked, but must be non-nil errors.

## Functions to Implement (Exact Signatures)

All functions must be exported (capitalized).

```go
// BuoyantForce computes Fb = rho_fluid * volume * g
func BuoyantForce(fluid Fluid, volume float64, g float64) (float64, error)

// WeightForce computes Fw = mass * g
func WeightForce(mass float64, g float64) (float64, error)

// CheckBuoyancyByDensity core decision logic via densities.
// Returns "float", "sink", or "neutral". Error if either density <=0.
func CheckBuoyancyByDensity(objDensity, fluidDensity float64) (string, error)

// CheckBuoyancy full check via Object and Fluid structs.
// Validates inputs, computes density internally, then delegates to CheckBuoyancyByDensity.
// Returns "float", "sink", or "neutral".
func CheckBuoyancy(obj Object, fluid Fluid) (string, error)
```

### Detailed Behavior

**BuoyantForce**:
- Validate `fluid.Density >0`, `volume >0`, `g >0`. If invalid, return 0 and non-nil error.
- Otherwise return `fluid.Density * volume * g`.
- Unit: Newtons (N).

**WeightForce**:
- Validate `mass >0`, `g >0`. Else return 0 and error.
- Return `mass * g`.

**CheckBuoyancyByDensity**:
- Validate `objDensity >0` and `fluidDensity >0`, else error.
- Compute `diff = objDensity - fluidDensity`
- If `math.Abs(diff) <= Tolerance` => `"neutral"`
- Else if `diff < 0` => `"float"`
- Else => `"sink"`
- Return strings exactly lower-case as listed.

**CheckBuoyancy**:
- Call `obj.Validate()` and `fluid.Validate()` first; propagate error if any.
- Compute object density via `obj.Density()`; propagate error.
- Delegate to `CheckBuoyancyByDensity(density, fluid.Density)`.
- Optionally compute forces for internal consistency check, but decision MUST be via density tolerance rule (equivalent to force comparison when volume same).

### Example Usage

```go
package main
import (
  "fmt"
  "yourmodule/buoyancy" // or relative import if local
)

obj := buoyancy.Object{Mass: 500, Volume: 1.0, Height: 2.0} // density 500 kg/m3
fluid := buoyancy.Fluid{Density: 1000} // water

state, err := buoyancy.CheckBuoyancy(obj, fluid)
// state == "float", err == nil

fb, _ := buoyancy.BuoyantForce(fluid, obj.Volume, buoyancy.StandardGravity) // 9810 N
fw, _ := buoyancy.WeightForce(obj.Mass, buoyancy.StandardGravity)          // 4905 N
fmt.Println(fb > fw) // true -> float

state2, _ := buoyancy.CheckBuoyancyByDensity(1000, 1000) // "neutral" within Tolerance
state3, _ := buoyancy.CheckBuoyancyByDensity(1000.0000000005, 1000) // still "neutral" (diff 5e-10 <= 1e-9)
state4, _ := buoyancy.CheckBuoyancyByDensity(1000.00001, 1000) // "sink" (diff 1e-5 > Tolerance)
```

## Requirements

1. **File location** `/app/buoyancy.go`, `package buoyancy`.
2. Define constants `Tolerance` and `StandardGravity` exactly with those values.
3. Define `Object` and `Fluid` structs exactly as specified (field names and types).
4. Implement all 4 functions + 3 methods with exact signatures; keep them exported.
5. **Tolerance handling** for neutral: `math.Abs(diff) <= Tolerance`. Tests include cases where densities differ by 1e-10 (should be neutral) and 1e-5 (should NOT be neutral).
6. **Error handling**: Return non-nil error on any non-positive input. Don't panic.
7. **No external dependencies**: stdlib only.
8. **Deterministic, pure functions**: No randomness, no I/O, no global state mutation.
9. **Step 2 compatibility**: Do NOT rename fields or package. Step 2 ( `2_partial_submersion` ) will have `inherit_prior_session = true` and will import same package to compute submerged fraction = rho_obj / rho_fluid and equilibrium depth = fraction * height for floating case. If you change struct names, Step 2 fails cascade.
10. Clean `go vet` must pass.

## Grading (Hidden Tests)

Tests in `/tests` (not visible to agent during Step 1) will check:
- Constants exist and have correct values (Tolerance 1e-9, StandardGravity 9.81)
- `Object.Density()` computes mass/volume correctly, errors on zero/negative volume
- `Validate()` errors on negative zero fields
- `BuoyantForce` and `WeightForce` formulas correct within 1e-6 tolerance, error cases
- `CheckBuoyancyByDensity` for float/sink/neutral including edge near Tolerance boundary: e.g., 999.999 vs 1000.0 should be float if diff > Tolerance, neutral if within.
- Many parameterized density pairs (wood 600 in water 1000 -> float, iron 7874 in water -> sink, exact equal -> neutral)
- Use of Archimedes physics, not hardcoded strings per object name.
- `CheckBuoyancy` integrating struct validation.

## What NOT to Do (Anti-Cheating)

- Do NOT hardcode return values per object name or density lookup table; must compute via formulas.
- Do NOT skip tolerance check with `==`. Must use `Tolerance`.
- Do NOT define additional module that hides `/app/buoyancy.go`; tests import `/app/buoyancy.go` directly.
- Do NOT modify test files; they are read-only in evaluation.

## Notes for Multi-Turn

- This step establishes context. Step 2 will rely on file still existing at `/app/buoyancy.go` and same package/import path.
- Keep implementation extensible: Step 2 will add functions like `SubmergedFraction`, `EquilibriumDepth`, `BatchCheck` in same package, likely new file `/app/partial.go` that uses your types.
- Do NOT redefine `Object`/`Fluid` in Step 2; reuse.
