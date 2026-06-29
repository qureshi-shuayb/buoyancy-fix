# Francis Hill-Chart Operating Point Solver

## Description
Implement a Francis turbine hill-chart solver in Python that performs Delaunay barycentric interpolation on scattered efficiency data and nested optimization to locate discharge and speed meeting a power target under cavitation margin constraints. Tests use randomized hill charts generated per seed to prevent hardcoding, enforce 1e-6 interpolation accuracy, 1% Q/n tolerance, and 0.005 eta absolute tolerance. Naive nearest-neighbor, griddata, constant-eta, wrong unit formulas, insufficient iterations, extrapolation outside hull, and missing clamp are caught by dedicated test cases including clamp branch test with out-of-range hill values and banned interpolator AST whitelist check.

## Completion Rates
- Oracle: 3 / 3
- Sonnet 4.6: TBD / 5
- Opus 4.6: 0 / 5
- Avocado: 2 / 5
- GPT-5.5: 3 / 5
- Codex: 5 / 5

## Model Analysis
After v2 hardening with softened instruction removing paste-ready code, pinned Dockerfile numpy scipy versions, improved test quality including agent-invoking naive catch, banned interpolator AST whitelist, cavitation unsafe test, and clamp test, oracle passes reliably. Opus 4.6 fails 0/5 on earlier run and 5/5 on latest indicating sensitivity to spec wording — dominant failure modes are over-specified spec misinterpretation leading to incomplete Delaunay implementation or wrong golden-section bounds, and barycentric weight math transcription errors. Avocado 2/5 shows improved solvability after softening but still in hard band targeting 1-4/5. GPT-5.5 at 3/5 and Codex at 5/5 indicate task is solvable by strong code models but not trivial. Expected failure modes: nearest-neighbor fallback, using scipy.interpolate.griddata instead of Delaunay transform, missing clamp to [0,1], insufficient optimization iterations causing 1% tolerance miss, ignoring cavitation margin zeroing, wrong Q11 n11 formula missing D or sqrt H, extrapolating outside hull.

## Anti-Cheating Analysis
- Hardcoded outputs: hill chart randomized per test seed 30-80 points with smooth single peak; hard-coded Q n eta fail 1% tolerance across 3 randomized geometries.
- Overfitting to visible tests: no visible tests in repo beyond contract shape in TBR policy; grader uses independent reference with same pinned algorithm but different seeds. Tests directory permission restricted via Dockerfile chmod 600 for isolation defense at build time; verifier runs as root but agent workspace at solve time treats tests as hidden per TBR policy.
- Modifying test files: verifier runs in isolated container, tests hidden in TBR review environment.
- Bypassing intended solution path: barycentric interpolation required for 1e-6 accuracy against Delaunay reference; alternative interpolators deviate beyond tolerance and are banned via AST import whitelist check allowing only numpy scipy.spatial math typing imports. Nested optimization with sufficient iterations required for 1% precision; coarse search fails tolerance. Cavitation unsafe branch tested separately with varied Hs sigma_crit expecting eta zero. Clamp branch tested separately with out-of-range hill values expecting clamped output.
