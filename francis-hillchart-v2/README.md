# Francis Hill-Chart Operating Point Solver

## Description
Implement a Francis turbine hill-chart solver in Python that performs Delaunay barycentric interpolation on scattered efficiency data and nested optimization to locate discharge and speed meeting a power target under cavitation margin constraints. Tests use randomized hill charts generated per seed to prevent hardcoding, enforce 1e-5 interpolation accuracy, 1% Q/n tolerance, and 0.005 eta absolute tolerance. Naive nearest-neighbor, griddata, constant-eta, wrong unit formulas, insufficient iterations, extrapolation outside hull, and missing clamp are caught by dedicated test cases including clamp branch test with out-of-range hill values and banned interpolator AST whitelist check.

## Completion Rates
- Oracle: 3 / 3
- Sonnet 4.6: TBD / 5
- Opus 4.6: 0 / 5
- Avocado: 2 / 5
- GPT-5.5: 3 / 5
- Codex: 5 / 5

## Model Analysis
After v3 hardening with softened instruction removing paste-ready code, pinned Dockerfile numpy scipy versions, improved test quality including agent-invoking naive catch, banned interpolator AST whitelist, cavitation unsafe test, clamp test, and test isolation defense via chmod 700 on tests directory at verify time, oracle passes reliably. Opus improved from 0/5 to 5/5 then back to 2/5 across runs indicating sensitivity to spec wording — dominant failure modes are barycentric weight math transcription errors and cavitation unsafe branch omission. Avocado 2/5 shows good hard band targeting. GPT at 3/5 and Codex at 5/5 indicate solvable by strong models but not trivial. Expected failure modes: nearest-neighbor fallback, using scipy.interpolate.griddata instead of Delaunay, missing clamp to [0,1], insufficient optimization iterations, ignoring cavitation margin zeroing, wrong Q11 n11 formula, extrapolating outside hull.

## Anti-Cheating Analysis
- Hardcoded outputs: hill chart randomized per test seed 30-80 points with smooth single peak; hard-coded Q n eta fail 1% tolerance across 3 randomized geometries.
- Overfitting to visible tests: no visible tests in repo beyond contract shape in TBR policy; grader uses independent reference. Tests directory permission restricted via chmod 700 at verify time in test.sh and Dockerfile ensures separation; verifier runs as root but agent workspace at solve time treats tests as hidden per Harbor TBR policy with separate mount namespaces for verifier vs agent phases.
- Modifying test files: verifier runs in isolated container, tests hidden in TBR review environment with restricted permissions.
- Bypassing intended solution path: barycentric interpolation required for 1e-5 accuracy against Delaunay reference; alternative interpolators deviate beyond tolerance and are banned via AST import whitelist check allowing only numpy scipy.spatial math typing imports. Nested optimization with sufficient iterations required for 1% precision; coarse search fails tolerance. Cavitation unsafe branch tested separately with varied Hs sigma_crit expecting eta zero. Clamp branch tested separately with out-of-range hill values expecting clamped output.
