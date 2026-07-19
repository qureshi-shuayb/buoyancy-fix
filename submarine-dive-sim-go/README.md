## Description
Hardened two-step submarine buoyancy simulator in Go with realistic ocean physics.

**Why this is hard (post-hardening):**
- No numeric spoilers or code-ready formulas in instructions. Agent must derive hydrostatic integral, hull compression, drag, terminal velocity, RK4, bisection from qualitative physics descriptions.
- Depth-dependent ocean: density grows linearly with depth (gradient 0.02 kg/m4), pressure is integral of rho*g dz (quadratic), not constant rho*g*z.
- Compressible hull: volume at depth V(z)=V0*(1 - k*P(z)) clamped to MinimumVolumeFraction, crush depth handling.
- New types: HullCompressibility, CrushDepth, DragCoefficient fields make validation complex.
- Equilibrium depth has no closed form when both density gradient and compressibility present — requires bisection/root-finding with bracketing and tolerance.
- Quadratic drag: F_drag = 0.5*rho*Cd*A*v*|v| with cross-section A=V/L derivation, signed handling for terminal velocity.
- Terminal velocity: solving drag balance sqrt(2|Fb-Fw|/(rho*Cd*A)) with sign.
- Time-to-depth: RK4 integration of coupled ODEs (dz/dt = velocity, dv/dt = Fnet/m) with depth-dependent rho and volume, crush detection, interpolation.
- Fleet batch: concurrent worker-pool with semaphore limited to 4, WaitGroup, order preservation, race-safe, crush risk marking.
- Property-based tests: monotonic density, pressure, volume, integral checks, brute-force equilibrium scan, RK4 accuracy vs small dt, inverse drag check.

**Step 1 - Depth-Aware Buoyancy Control**: 
Implements package submarine with constants Tolerance, StandardGravity, StandardSeawaterDensity, DepthDensityGradient, MinimumVolumeFraction. Types Submarine (DryMass, Volume, Length, BallastCapacity, BallastLevel, HullCompressibility, CrushDepth, DragCoefficient) and Seawater(Density). Methods: Validate, EffectiveMass, EffectiveDensity, DensityAtDepth, PressureAtDepth, VolumeAtDepth, EffectiveDensityAtDepth. Functions: BuoyantForce, WeightForce, BuoyantForceAtDepth, RequiredBallastForNeutral, RequiredBallastForNeutralAtDepth, CheckSubmarineState, CheckSubmarineStateAtDepth, IsNeutralBuoyancyPossible, IsNeutralBuoyancyPossibleAtDepth. Pressure requires deriving integral for linear rho(z). Volume clamping and crush error.

**Step 2 - Dive Dynamics, Equilibrium & Fleet**:
File /app/dive.go reusing Step1 types (inherit_prior_session=true). Must NOT redefine types/constants. DiveResult expanded with EquilibriumDepth, TerminalVelocity, TimeToDepth, MaxPressure, VolumeAtDepth, CrushRisk, StateAtDepth etc. Functions: SubmergedFraction, NetVerticalForce, VerticalAcceleration, NetVerticalForceAtDepth (with drag), TerminalVelocity (sqrt, signed), FindEquilibriumDepth (bisection, tolerance 1e-6, no closed form), TimeToDepth (RK4 with k1..k4), AnalyzeDive (combines all), BatchAnalyzeFleet (concurrent worker-pool), BatchAnalyzeFleetWithTargets (per-sub targets, concurrent).

Tests context-following: checking prior file exists and types not redefined, concurrency primitives present (go, WaitGroup, chan), RK4 k1..k4 present, sqrt usage, no hardcoded lookup.

## Completion Rates (to be filled after codimango runs)
| Model | Step | Pass Rate | Updated |
|---|---|---|---|
| Oracle | 1_basic_buoyancy_control | TBD | TBD |
| Oracle | 2_dive_dynamics | TBD | TBD |
| meta/avocado_dvsc_tester | 1_basic_buoyancy_control | TBD | TBD |
| meta/avocado_dvsc_tester | 2_dive_dynamics | TBD | TBD |
| claude-opus-4-6 | 1_basic_buoyancy_control | TBD | TBD |
| claude-opus-4-6 | 2_dive_dynamics | TBD | TBD |

## Model Analysis
TBD - populate after trials. Expected low pass rate due to numerical methods and concurrency.

## Anti-Cheating Analysis
- Hardcoded outputs: many mass/volume/ballast/compressibility/depth combos parameterized, not enumerable. Pressure integral quadratic term checked, volume clamping, drag sign, equilibrium brute-force comparison.
- No formula spoilers: instruction gives qualitative physics, not code-ready formulas or numeric answers.
- Overfitting to visible tests: tests hidden in /tests, not visible in /app during solving.
- Modifying test files: tests in separate read-only mount.
- Bypassing intended path: tolerance check enforced by 5e-10 vs 1e-5 edge cases, bisection required (AST checks), RK4 required (k1..k4 and accuracy vs Euler), concurrency required (WaitGroup+chan+go).
- AST checks: dive.go must NOT contain type Submarine struct nor const Tolerance, must contain DensityAtDepth, PressureAtDepth, VolumeAtDepth, WaitGroup, chan, go, Sqrt, k1/k2/k3/k4.

## Notes
Hardened from trivial one-line Archimedes to realistic ocean stratification + compressible hull + drag + root-finding + RK4 + concurrency. Addresses HIGH novelty risk: unique API surface (FindEquilibriumDepth, TerminalVelocity, TimeToDepth, DensityAtDepth, PressureAtDepth, VolumeAtDepth, HullCompressibility, CrushDepth) has no public benchmark match. Schema 1.1, format terminal_bench_multi_turn, inherit_prior_session true on step2.
