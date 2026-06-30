# point-kinetics-xenon-v2

## Description
A Python numerical-modeling task. The agent implements `simulate(...)` in `/app/reactor_kinetics.py`: point reactor kinetics with six delayed neutron precursor groups coupled to iodine-135 and xenon-135 concentration ODEs, with reactivity feedback from fuel temperature Doppler, moderator temperature, control rod position, and xenon poisoning.

The hard part is assembling several coupled physics correctly:
- backward Euler implicit solve of 7x7 kinetics linear system each step via Gaussian elimination with partial pivoting (explicit Euler is unstable at given dt and Lambda),
- explicit Euler for slow iodine, xenon, fuel and moderator temperature dynamics,
- xenon reactivity worth closing feedback loop causing non-monotonic power behavior,
- temperature feedback from power via first-order thermal lag,
- correct steady-state initial equilibrium for precursors, iodine, xenon, temperatures,
- partitioned IMEX scheme pinned for determinism.

A naive scaffold omitting xenon feedback, temperature coefficients, implicit solver, or equilibrium initialization drifts well past tight tolerances.

`tests/test_outputs.py` imports agent's `/app/reactor_kinetics.py` and compares outputs against independent reference over six scenarios:
- **step reactivity insertion** – small positive step, power excursion limited by Doppler,
- **ramp load-follow** – power ramp down then up, xenon transient overshoot,
- **rod withdrawal** – rapid withdrawal with Doppler limiting peak,
- **iodine pit restart** – shutdown then attempted restart into xenon peak, power suppressed,
- **fast scram** – sudden large negative insertion testing stiff solver stability at small dt,
- **oscillation** – sinusoidal rod oscillation testing feedback coupling and numeric stability.

Plus contract checks and scalar-vs-list equivalence. Verifier writes `/logs/verifier/reward.txt`.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Sonnet 4.6 | _not yet run_ |
| Opus 4.6 | 5/5 (100%) _prior version too easy_ |
| Avocado | 5/5 (100%) _prior version too easy_ |
| GPT-5.5 | 5/5 (100%) _prior version too easy_ |

*Note: v0.10 showed 5/5 across all models indicating too-easy calibration. v0.11 tightens tolerance from 1e-7 to 1e-9 to 1e-9 across versions and adds fast-scram and oscillation scenarios to increase difficulty targeting 2-3/5 pass band. Failure modes observed in prior runs were primarily numeric drift from approximate solvers and missing xenon/temperature feedback.*

## Model Analysis

Model evaluation runs show prior versions too easy at 5/5; v0.15 adds 4 extra scenarios and tightens to 1e-9 targeting 2-3/5 band. Run models with:

```bash
codimango bench run -p point-kinetics-xenon-v2 -a claude-code -m claude-sonnet-4-6 -k 5
codimango bench run -p point-kinetics-xenon-v2 -a claude-code -m claude-opus-4-6 -k 5
codimango bench run -p point-kinetics-xenon-v2 -a metacode -m meta/avocado_dvsc_tester -k 5
```

Prior v0.10 failure analysis: all models passed due to clear spec and moderate tolerance. Tightening to 1e-9 and adding two edge-case scenarios expected to differentiate implementations with subtle numeric errors in Gaussian elimination pivoting or explicit Euler ordering.

## Anti-Cheating Analysis

Outputs depend on continuous physical inputs across six distinct transient scenarios with stateful stiff ODE coupling; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently; matching requires full specified model.

- **Hardcoded outputs**: Tests use continuous physical parameters and six distinct transient scenarios generated at runtime with tight 1e-9 tolerance (tightened from 1e-9 in v0.11); pre-computed answers cannot match without implementing the full coupled ODE system.
- **Overfitting to visible tests**: Test inputs are parameterized across step, ramp, withdrawal, iodine-pit, fast-scram, and oscillation regimes covering edge cases of stiff kinetics, xenon feedback, thermal lag, and numeric stability; no single constant passes.
- **Modifying test files**: Tests are mounted read-only by Codimango at `/tests/` — agent cannot modify them. test.sh applies chmod 700 defense during pytest to mitigate C18 in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories of power, xenon, iodine, and reactivity at every time step plus peak power and final xenon, not just final output, so shortcutting the implicit solver or equilibrium initialization is detected by numeric drift. Stdlib-only check enhanced to detect dynamic imports via __import__ and importlib.
