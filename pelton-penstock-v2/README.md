# Pelton Penstock Governor Steady Power

## Description
Implement Pelton turbine penstock steady-state solver in Python with Darcy-Weisbach Colebrook-White fixed-point friction iteration exactly 5 steps, outer Q implicit loop exactly 10 iterations, Pelton Euler power formula, and droop governor discrete rate-limit simulation. Tests cover laminar override, ValueError on non-positive net head, deadband zero branch, clamp to [0,2 Nrated], and naive constant-f catch. Randomized geometries per seed prevent hardcoding.

## Completion Rates
- Oracle: 3 / 3
- Sonnet 4.6: TBD / 5
- Opus 4.6: 5 / 5
- Avocado: 5 / 5
- GPT-5.5: 5 / 5
- Codex: 5 / 5

## Model Analysis
After v2 test expansion, oracle passes reliably and AI assessment improved from Revise Medium4 to Revise High1 Medium2 but still not Accept due to spec over-specified warning. All strong models achieve 5/5 indicating task remains too easy for hard band. Dominant failure mode for weaker models would be Haaland approximation instead of 5-iteration Colebrook, missing factor 2 in Pelton power, ignoring deadband or rate limit, or single-iteration Q loop. Current top models transcribe spec correctly. Further hardening may require softening spec to increase reasoning burden paradoxically making it harder by removing verbatim formulas, which was done in v2 instruction softening.

## Anti-Cheating Analysis
- Hardcoded outputs: randomized penstock geometries per seed across 3 steady cases plus governor cases prevent hardcoding.
- Overfitting: no visible expected values beyond contract shape; grader uses independent reference.
- Modifying test files: verifier isolated, tests hidden.
- Bypassing solution path: Colebrook pinned to exactly 5 fixed-point iterations; Haaland deviates beyond 1e-9 tolerance. Pelton power formula pinned verbatim; factor errors caught by 2% P tolerance. Governor rate-limit pinned to discrete 1s steps with exact iteration count assertion. Naive constant f test invokes agent and asserts agent beats naive by >0.0004 relative head difference.
