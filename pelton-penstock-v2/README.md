# Pelton Penstock Governor Steady Power

## Description
Implement Pelton turbine penstock steady-state solver in Python with Darcy-Weisbach Colebrook-White friction iteration, outer Q implicit loop, Pelton Euler power formula, and droop governor discrete rate-limit simulation. Tests cover laminar override, ValueError on non-positive net head, deadband zero branch, clamp to [0,2 Nrated], and naive constant-f catch. Five randomized steady geometries plus three governor scenarios prevent hardcoding. Tolerances tightened to 0.5% Hn, 0.8% Q, 1% P to increase discrimination.

## Completion Rates
- Oracle: 3 / 3
- Sonnet 4.6: TBD / 5
- Opus 4.6: TBD / 5
- Avocado: TBD / 5
- GPT-5.5: TBD / 5
- Codex: TBD / 5

## Model Analysis
v3 revision softens specification to reduce over-specification warning: removed Naive Failure Modes hints, Anti-Cheating Notes, and example usage from instruction, restructured as engineering physics problem rather than coding recipe. Tests expanded from 3 to 5 steady cases and governor multi-case suite, tolerances tightened from 1%/1.5%/2% to 0.5%/0.8%/1% for Hn/Q/P, N_eq tolerance halved to 0.2 rpm. Expected difficulty shifts from prior 5/5 too-easy toward target 2-3/5 band by increasing reasoning burden: agents must derive Colebrook fixed-point, implicit Q loop, Euler power factor 2, deadband and rate-limit discrete simulation without step-by-step hints. Dominant failure modes anticipated: Haaland approximation deviation beyond 1e-9, missing factor 2 in Pelton power, ignoring deadband, analytic bypass of rate limit failing iteration count, single-iteration Q loop, incorrect laminar override. Oracle passes 3/3 locally.

## Anti-Cheating Analysis
- Hardcoded outputs: randomized penstock geometries per seed across 5 steady cases plus 3 governor scenarios prevent hardcoding.
- Overfitting: no visible expected values beyond contract shape; grader uses independent reference.
- Modifying test files: verifier isolated, tests hidden.
- Bypassing solution path: Colebrook pinned to exactly 5 fixed-point iterations; Haaland deviates beyond 1e-9 tolerance. Pelton power formula pinned; factor errors caught by 1% P tolerance tightened from 2%. Governor rate-limit pinned to discrete 1s steps with exact iteration count assertion. Naive constant f test asserts agent beats naive by >0.0004 relative head difference.
