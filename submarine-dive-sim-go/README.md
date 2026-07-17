## Description
Two-step submarine buoyancy simulator in Go.

**Step 1 - Basic Buoyancy Control**: Implements submarine sink/float/neutral physics with ballast tanks. Agent builds `package submarine` with `Submarine{DryMass, Volume, Length, BallastCapacity, BallastLevel}` and `Seawater{Density}`. Core physics Archimedes principle: EffectiveMass = DryMass+BallastLevel, EffectiveDensity = EffectiveMass/Volume, Fb = rho_fluid*Volume*g, Fw = EffectiveMass*g. State determination uses Tolerance 1e-9 for neutral buoyancy. Also computes required ballast for neutral: rho*V - DryMass and whether neutral achievable within capacity.

Why naive fails: forgetting ballast in mass, using == for neutral not tolerance, not validating BallastLevel <= Capacity, mixing up dry vs effective mass.

**Step 2 - Dive Dynamics**: `inherit_prior_session=true` preserves `/app/submarine.go`. Agent must NOT redefine types, must reuse Tolerance. Implements new file `/app/dive.go` with DiveResult struct and functions: SubmergedFraction (rho_eff/rho_fluid clamped), NetVerticalForce (Fb-Fw), VerticalAcceleration (Fnet/m), AnalyzeDive (combines all), BatchAnalyzeFleet (preserves order, marks invalid as "invalid", fluid invalid => whole error).

Tests context-following: checking that prior file still exists and types not redefined.

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
TBD - populate after trials.

## Anti-Cheating Analysis
- Hardcoded outputs: many mass/volume/ballast combos parameterized, not enumerable
- Overfitting to visible tests: tests hidden in /tests, not visible in /app during solving
- Modifying test files: tests in separate read-only mount
- Bypassing intended path: must implement Archimedes formulas, tolerance check enforced by 5e-10 vs 1e-5 edge cases, and reuse check prevents redefining types

## Notes
Scaffolded from buoyancy-float-check-go multi-turn template. Schema 1.1, format terminal_bench_multi_turn, inherit_prior_session true on step2.
