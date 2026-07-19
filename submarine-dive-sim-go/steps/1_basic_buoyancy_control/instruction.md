# Step 1: Submarine Buoyancy with Depth-Dependent Ocean & Compressible Hull

## Overview
This is **Step 1 of 2** in a multi-turn submarine simulator T-Bench task. You are building a Go package that models submarine buoyancy with realistic ocean stratification and pressure-comppressible hull.

Step 1 implements foundational types plus depth-aware buoyancy: surface sink/float/neutral decisions, plus how density, pressure, hull volume, buoyant force, and required ballast change with depth. **Step 2 will extend the same package** to include quadratic drag, terminal velocity, equilibrium depth search via root-finding, RK4 time-to-depth integration, and concurrent fleet batch processing. Step 2 must reuse your `Submarine` and `Seawater` types without redefining them — so define them cleanly now with extensibility.

Goal: model a fully submerged submarine where seawater density is not constant but increases with depth due to salinity/compressibility, and where hull volume shrinks under hydrostatic pressure.

## Ocean & Physics Background

### Effective Mass & Density (surface)
A submarine's total mass includes structure plus ballast water. Its effective average density is total mass divided by hull displacement volume. The decision to float, sink, or be neutrally buoyant depends on comparing effective density to surrounding seawater density within a tolerance — exact equality is rare and numerically fragile, so absolute tolerance must be used.

### Depth-Dependent Ocean
In this simplified ocean model, seawater density grows linearly with depth due to compressibility stratification. Surface density is given per locale, and a constant vertical gradient determines how fast density increases per meter depth. This gradient is small but non-negligible for deep dives.

- Density is a function of depth z >=0 (positive downward from surface). At surface z=0 density equals surface value. At depth z, density equals surface plus gradient times depth.
- Hydrostatic pressure at depth is not simply rho*g*z with constant rho. Because rho varies with depth, pressure is the integral from surface to depth of local density times gravity. For a linear density profile this integral yields a quadratic dependence on depth. You must derive and implement this integral yourself — the instruction does not give the final closed form.
- Both density and pressure are monotonic increasing with depth. Pressure at zero depth is zero.

### Compressible Hull
Submarine hull compresses slightly under external pressure. Volume at depth is surface volume reduced proportionally to pressure times hull compressibility factor (1/Pa). This linear model is clamped so volume never shrinks below a minimum fraction of original volume (to avoid non-physical zero or negative volume). If hull compressibility is zero, volume remains constant with depth (incompressible).

- Beyond crush depth, volume model is invalid and must error.

### Buoyancy at Depth
Archimedes principle: buoyant force equals weight of displaced fluid. Because density and hull volume both depend on depth, buoyant force is depth-dependent: use local density at depth and local volume at depth to compute weight of displaced water, times gravity for force.

Weight force uses effective mass (dry plus ballast) times gravity and is depth-independent (mass does not change with depth), but effective density at depth uses depth-dependent volume.

Required ballast for neutral buoyancy at a given depth is the ballast that makes effective mass equal to mass of displaced fluid at that depth. It may be outside [0, Capacity] — meaning neutral cannot be achieved with current capacity at that depth. Return computed value anyway; possibility check is separate.

State at depth: compare effective density at depth to local seawater density at same depth using absolute tolerance. If within tolerance -> neutral; if effective less than fluid minus tolerance -> float (positively buoyant, tends upward); else sink.

## File Location and Package
- Implement in single file: `/app/submarine.go`
- Package: `submarine` (i.e., `package submarine`)
- Go 1.23+, standard library only. No external imports beyond `math`, `fmt`, `errors`, etc.
- File must compile standalone (`go test` importing it).
- Do not create go.mod with conflicting name; `go vet` must pass.
- Step2 compatibility: DO NOT rename fields/package. Step2 will have inherit_prior_session=true and will import same package, adding file `/app/dive.go` using your types, constants, and methods. If you change struct names, Step2 cascade fails.

## Constants to Define

You MUST define and use these exported constants (exact names and values):

```go
const Tolerance = 1e-9                // absolute density tolerance kg/m3 for neutral check
const StandardGravity = 9.81          // m/s^2
const StandardSeawaterDensity = 1025.0 // kg/m3 typical surface seawater
const DepthDensityGradient = 0.02     // kg/m4 — increase of density per meter depth
const MinimumVolumeFraction = 0.1     // minimum volume as fraction of surface volume
```

## Types to Define

```go
// Submarine represents a submersible with ballast tanks and compressible hull.
type Submarine struct {
    DryMass            float64 // kg, >0 mass without ballast water
    Volume             float64 // m^3, >0 surface displacement volume
    Length             float64 // m, >0 overall length (for drag cross-section in Step2)
    BallastCapacity    float64 // kg, >0 max ballast water mass
    BallastLevel       float64 // kg, >=0 and <= BallastCapacity, current ballast
    HullCompressibility float64 // 1/Pa, >=0 compressibility factor (0 = incompressible)
    CrushDepth         float64 // m, >0 depth beyond which hull fails
    DragCoefficient    float64 // dimensionless, >=0 drag coefficient for Step2 (0 = no drag)
}

type Seawater struct {
    Density float64 // kg/m3, >0 surface density
}
```

Methods:
- `func (s Submarine) Validate() error` - error if DryMass<=0, Volume<=0, Length<=0, BallastCapacity<=0, BallastLevel<0, BallastLevel > Capacity, HullCompressibility<0, CrushDepth<=0, DragCoefficient<0. Error message must contain relevant keyword case-insensitive: "mass", "volume", "length", "capacity", "ballast", "compressibility", "crush", "drag" for respective failures.
- `func (s Submarine) EffectiveMass() float64` - DryMass + BallastLevel (pure, no error)
- `func (s Submarine) EffectiveDensity() (float64, error)` - EffectiveMass/Volume at surface, error if Validate fails or Volume<=0
- `func (f Seawater) Validate() error` - error if Density<=0

Depth-aware methods (new):
- `func (f Seawater) DensityAtDepth(depth float64) (float64, error)` - density at depth z. Validate fluid and depth>=0 else error. Return surface + gradient*depth.
- `func (f Seawater) PressureAtDepth(depth float64, g float64) (float64, error)` - hydrostatic pressure at depth via integral of rho(z)*g dz from 0 to depth. Validate fluid, depth>=0, g>0 else error. Return 0 at depth 0. Must be monotonic increasing.
- `func (s Submarine) VolumeAtDepth(depth float64, fluid Seawater, g float64) (float64, error)` - volume at depth accounting for compression: surface volume reduced proportionally to pressure * compressibility, clamped to at least MinimumVolumeFraction * surface volume. Validate sub, fluid, g>0, depth>=0, check crush: if depth > CrushDepth error containing "crush". Return surface volume if compressibility 0.
- `func (s Submarine) EffectiveDensityAtDepth(depth float64, fluid Seawater, g float64) (float64, error)` - EffectiveMass / VolumeAtDepth. Use VolumeAtDepth logic.

## Functions to Implement (Exact Signatures)

All exported, in submarine.go.

Surface versions (depth 0, for backward compat):
```go
func BuoyantForce(fluid Seawater, sub Submarine, g float64) (float64, error)
func WeightForce(sub Submarine, g float64) (float64, error)
func RequiredBallastForNeutral(sub Submarine, fluid Seawater) (float64, error)
func CheckSubmarineState(sub Submarine, fluid Seawater) (string, error)
func IsNeutralBuoyancyPossible(sub Submarine, fluid Seawater) (bool, error)
```

Depth-aware versions:
```go
func BuoyantForceAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error)
func RequiredBallastForNeutralAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error)
func CheckSubmarineStateAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (string, error)
func IsNeutralBuoyancyPossibleAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (bool, error)
```

### Detailed Behavior (qualitative, you must derive exact math)

**Seawater.DensityAtDepth**:
- Validate fluid Density>0 else error. Depth must be >=0 else error containing "depth".
- Return surface density plus gradient times depth.

**Seawater.PressureAtDepth**:
- Validate fluid, depth>=0, g>0 else error.
- Pressure is definite integral from 0 to depth of local density * g. Derive closed form for linear density profile. Must be 0 at depth 0, monotonic increasing, and for zero gradient reduces to rho0*g*z.
- Return pressure in Pascals (N/m2).

**Submarine.VolumeAtDepth**:
- Validate sub via Validate(), fluid Validate(), g>0, depth>=0.
- If depth > CrushDepth => return 0, error containing "crush".
- Compute pressure via PressureAtDepth, then reduction factor = compressibility * pressure. Volume = surface * (1 - reduction). Clamp lower bound to MinimumVolumeFraction * surface. Never return <=0 beyond clamp.
- If HullCompressibility==0 return surface volume.

**Submarine.EffectiveDensityAtDepth**:
- Via EffectiveMass / VolumeAtDepth.

**BuoyantForce (surface)**:
- Validate fluid and sub via Validate(), g>0 else error.
- Buoyant force equals weight of displaced fluid at surface (use surface density and surface volume). Return in Newtons.

**WeightForce**:
- Validate sub, g>0.
- Weight equals effective mass times gravity.

**BuoyantForceAtDepth**:
- Validate fluid, sub, depth>=0, g>0.
- Use density at depth and volume at depth to get displaced mass, times g.

**RequiredBallastForNeutral (surface)**:
- Validate DryMass>0, Volume>0, Length>0, BallastCapacity>0, CrushDepth>0, HullCompressibility>=0, DragCoefficient>=0, fluid Density>0 else error. Do NOT validate BallastLevel for this function (only dry properties).
- Return displaced mass at surface minus DryMass.

**RequiredBallastForNeutralAtDepth**:
- Same validation as above for dry properties plus depth>=0, g>0.
- Displaced mass at depth = densityAtDepth * volumeAtDepth. Required = displaced - DryMass. May be negative or >Capacity. Return value even if outside range.

**CheckSubmarineState (surface)**:
- Validate sub and fluid.
- Effective density at surface vs fluid surface density via tolerance: |eff - fluid| <= Tolerance => "neutral", else if eff < fluid => "float", else "sink". Exact lower-case strings.

**CheckSubmarineStateAtDepth**:
- Validate sub, fluid, depth>=0, g>0, depth <= CrushDepth else error crush.
- Compute effective density at depth vs density at depth same tolerance logic.

**IsNeutralBuoyancyPossible (surface)** and **IsNeutralBuoyancyPossibleAtDepth**:
- Validate dry properties + fluid (+ depth,g for AtDepth version).
- Compute required ballast (surface or at depth) and check if in [0, Capacity] inclusive.

### No Numeric Spoilers
Instruction contains no expected numeric outputs. You must derive formulas yourself from physics description. Hidden tests use many combos, not enumerable.

## Requirements
1. File /app/submarine.go package submarine
2. Constants exact names/values: Tolerance 1e-9, StandardGravity 9.81, StandardSeawaterDensity 1025.0, DepthDensityGradient 0.02, MinimumVolumeFraction 0.1
3. Structs exact field names/types (7+1 fields)
4. All functions+methods exact signatures exported
5. Tolerance handling for neutral at surface and at depth
6. Error handling: non-positive mass/volume/length/crush, negative ballast/compressibility/drag, ballast > capacity, negative depth, non-positive g, crush depth exceeded must error. Error messages contain relevant keywords.
7. Stdlib only, deterministic pure functions, go vet passes
8. Pressure must be integral of varying density, not simplified rho0*g*z when gradient present — tests check quadratic term.
9. Volume clamping to MinimumVolumeFraction and crush depth check.
10. Step2 compatibility: do NOT rename fields/package/constants. Step2 will add file dive.go reusing your types.

## Grading (Hidden Tests)
- Constants values exact
- EffectiveMass = DryMass+BallastLevel
- EffectiveDensity surface and at depth
- Validate errors for all invalid combos including new fields, keywords in messages
- DensityAtDepth = Density + gradient*depth, error depth<0
- PressureAtDepth = g*(Density*depth + 0.5*gradient*depth^2) within 1e-6, monotonic, 0 at 0, error cases
- VolumeAtDepth = Volume * (1 - compressibility*pressure) clamped to MinimumVolumeFraction*Volume, incompressible case, crush depth error, monotonic decreasing with depth
- EffectiveDensityAtDepth monotonic increasing if volume shrinks
- BuoyantForce surface and at depth within 1e-6
- RequiredBallastForNeutral surface and at depth many combos, outside capacity still returns value
- IsNeutralBuoyancyPossible checks range at surface and depth
- CheckSubmarineState float/sink/neutral including tolerance boundary 5e-10 neutral vs 1e-5 not neutral at surface and at depth
- No hardcoded lookup table, must compute

## Anti-Cheating
- Do NOT hardcode returns per mass lookup; must compute via formulas and integrals
- Do NOT skip tolerance with ==
- Do NOT modify test files
- Do NOT assume ballast 0 or compressibility 0; tests cover varied compressibility and drag
- AST check ensures file contains DensityAtDepth, PressureAtDepth, VolumeAtDepth logic and not just constants
