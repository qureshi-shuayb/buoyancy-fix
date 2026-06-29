# Francis Hill-Chart Operating Point Solver

## Description
Implement a Francis turbine hill-chart solver in Python that performs Delaunay barycentric interpolation on scattered efficiency data and nests two golden-section searches to locate discharge and speed meeting a power target under cavitation margin constraints. Tests randomized hill charts generated per seed to prevent hardcoding, enforce 1e-6 interpolation accuracy, 1% Q/n tolerance, and 0.005 eta absolute tolerance. Naive nearest-neighbor, griddata, constant-eta, wrong unit formulas, insufficient iterations, and extrapolation outside hull are caught by dedicated test cases.

## Completion Rates
- Oracle: 3 / 3
- Sonnet 4.6: TBD / 5
- Opus 4.6: 0 / 5
- Avocado: 1 / 5
- GPT-5.5: 5 / 5
- Codex: 5 / 5

## Model Analysis
After v2 hardening with pinned Dockerfile numpy scipy and improved test quality, oracle passes reliably. Opus 4.6 fails 0/5 dominant mode is over-specified spec misinterpretation leading to incomplete Delaunay implementation or wrong golden-section bounds. Avocado 1/5 shows similar difficulty with barycentric weight math transcription errors and cavitation unsafe branch omission. GPT-5.5 and Codex achieve 5/5 indicating task is solvable by strong code models but not trivial — good difficulty spread in hard band targeting 1-4/5. Sonnet pending. Expected failure modes: nearest-neighbor fallback, using scipy.interpolate.griddata instead of Delaunay transform, missing clamp to [0,1], fewer than 40 golden iterations causing 1% tolerance miss, ignoring cavitation margin zeroing.

## Anti-Cheating Analysis
- Hardcoded outputs: hill chart randomized per test seed 30-80 points with smooth single peak; hard-coded Q n eta fail 1% tolerance across 3 randomized geometries.
- Overfitting to visible tests: no visible tests in repo beyond contract shape; grader uses independent reference with same pinned algorithm but different seeds.
- Modifying test files: verifier runs in isolated container, tests hidden in TBR review; agent workspace is /app only.
- Bypassing intended solution path: barycentric interpolation pinned via 1e-6 accuracy requirement against Delaunay reference; alternative interpolators deviate beyond tolerance and are banned via AST import whitelist check for scipy.spatial.Delaunay only. Golden-section 40 iterations pinned via tolerance; coarse search fails 1% Q/n band. Cavitation unsafe branch tested separately with varied Hs sigma_crit requiring eta zero-out.
