# Pelton Penstock Governor Steady Power

## Description
Implement Pelton turbine penstock steady-state solver in Python with Darcy-Weisbach Colebrook-White friction iteration, outer Q implicit loop, Pelton Euler power formula, and droop governor discrete rate-limit simulation. Tests cover laminar override, ValueError on non-positive net head, deadband zero branch, clamp to [0,2 Nrated], and naive constant-f catch. Five randomized steady geometries plus three governor scenarios prevent hardcoding. Tolerances tightened to 0.3% Hn, 0.5% Q, 0.7% P to increase discrimination.

## Completion Rates
- Oracle: 9 / 9
- Sonnet 4.6: TBD / 5
- Opus 4.6: TBD / 5
- Avocado: TBD / 5
- GPT-5.5: TBD / 5
- Codex: TBD / 5

## Model Analysis
v4 revision fully softens specification to address High1 Medium2 reviewer feedback on over-specified warning from v3. Removed all verbatim formulas, explicit Colebrook equation strings, exact iteration counts from instruction text, and replaced with conceptual physics descriptions: Colebrook-White implicit relationship solved iteratively via fixed-point, Darcy-Weisbach proportional loss, Torricelli-type jet velocity, Euler turbine momentum change with jet turning factor, droop proportional speed deviation with deadband and discrete rate-limited approach. API signatures unchanged but spec now requires reasoning derivation rather than copy-paste transcription. Tests tightened further from v3 0.5%/0.8%/1% to 0.3%/0.5%/0.7% for Hn/Q/P, Vj/U to 0.3%, f to 0.5%, N_eq to 0.1 rpm, naive threshold to 0.0003 to increase discrimination against approximate Haaland or single-iteration shortcuts while keeping oracle stable at 9/9. Expected difficulty shifts from historical 5/5 too-easy toward target 2-3/5 band: agents must infer fixed-point structure, implicit Q loop convergence, Euler factor 2, deadband logic, and discrete 1s step simulation without step-by-step recipe. Dominant failure modes anticipated: Haaland approximation deviation beyond 1e-9 Colebrook tolerance, missing factor 2 in Pelton power, ignoring deadband leading to wrong N_eq, analytic bypass of rate limit failing exact iteration count, single-iteration Q loop causing >0.3% Hn error, incorrect laminar override. Oracle passes 9/9 locally.

## Anti-Cheating Analysis
- Hardcoded outputs: randomized penstock geometries per seed across 5 steady cases plus 3 governor scenarios prevent hardcoding.
- Overfitting: no visible expected values beyond contract shape; grader uses independent reference.
- Modifying test files: verifier isolated, tests hidden.
- Bypassing solution path: Colebrook pinned to fixed-point iterations in reference; Haaland deviates beyond 1e-9 tolerance. Pelton power formula pinned; factor errors caught by 0.7% P tolerance tightened from 1%. Governor rate-limit pinned to discrete 1s steps with exact iteration count assertion. Naive constant f test asserts agent beats naive by >0.0003 relative head difference.
