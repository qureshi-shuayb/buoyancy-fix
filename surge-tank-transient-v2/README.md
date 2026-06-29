# Surge Tank Mass Oscillation Transient

## Description
Implement rigid water-column ODE simulation of surge tank mass oscillation after turbine load rejection in Python. Tests cover explicit Euler integration order, Swamee-Jain friction factor, turbine closure ramp, steady-state initialization, peak/min/steady levels, and damping time scan. Naive frictionless, wrong-sign momentum, RK4 instead of Euler, wrong initial Z0, and wrong update order are caught by dedicated test cases with tight tolerances.

## Completion Rates
- Oracle: 3 / 3
- Sonnet 4.6: TBD / 5
- Opus 4.6: 5 / 5
- Avocado: 5 / 5
- GPT-5.5: 5 / 5
- Codex: 5 / 5

## Model Analysis
After v2 test quality improvements, oracle passes reliably and AI assessment is Accept. However all strong models still achieve 5/5 indicating task remains too easy for hard band target 1-4/5. Dominant failure mode for weaker models would be wrong Euler order or missing friction, but current top models transcribe spec correctly. Further hardening may require removing explicit Euler code snippet from instruction to increase reasoning burden, or adding decoy files to increase exploration cost, or tightening tolerances further.

## Anti-Cheating Analysis
- Hardcoded outputs: geometries randomized per seed across 3 test cases with 600-2400 steps; hard-coded peak/min fail tolerance.
- Overfitting: no visible tests beyond contract shape in repo; grader uses independent reference.
- Modifying test files: verifier runs isolated, tests hidden in TBR.
- Bypassing solution path: explicit Euler order pinned via tolerance against reference; higher-order integrators deviate beyond 0.5m peak tolerance by design. Swamee-Jain formula pinned with exact parentheses; Haaland approximation deviates. Naive no-friction test invokes agent and asserts agent output differs from frictionless reference by >0.4m proving friction implemented.
