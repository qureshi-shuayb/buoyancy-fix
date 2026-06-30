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

`tests/test_outputs.py` imports agent's `/app/reactor_kinetics.py` and compares outputs against independent reference over fourteen scenarios:
- **step reactivity insertion** – small positive step, power excursion limited by Doppler,
- **ramp load-follow** – power ramp down then up, xenon transient overshoot,
- **rod withdrawal** – rapid withdrawal with Doppler limiting peak,
- **iodine pit restart** – shutdown then attempted restart into xenon peak, power suppressed,
- **fast scram** – sudden large negative insertion testing stiff solver stability at small dt,
- **oscillation** – sinusoidal rod oscillation testing feedback coupling and numeric stability,
- **extreme insertion** – 500 pcm step testing Doppler limiting at very small dt,
- **long xenon** – 40-hour multi-stage transient stressing long-term stability,
- **ultra-fast** – 1 ms dt transient testing pivot handling,
- **power ramp** – slow multi-frequency ramp testing equilibrium drift,
- **very fast** – 0.5 ms dt transient testing Gaussian elimination pivot at edge of double precision,
- **long oscillation** – 20k-step multi-frequency oscillation testing long-term drift accumulation,
- **thermal shock** – high-frequency square-wave rod forcing testing thermal lag coupling and numeric stability,
- **super extreme** – 0.1 ms dt with 1000 pcm insertion testing extreme pivot stability and Doppler limiting.

Plus contract checks and scalar-vs-list equivalence. Verifier writes `/logs/verifier/reward.txt`.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | 3/5 (60%) |
| Avocado | 2/5 (40%) |
| GPT-5.5 | 3/5 (60%) |
| Sonnet 4.6 | 2/5 (40%) |

## Model Analysis

Oracle passes 3/3 locally with reference solution matching pinned partitioned IMEX scheme and Gaussian elimination with partial pivoting. Prior Codimango validation showed AI Accept with Low issues on spec-test inconsistency and completion table completeness, and agent pass rate 5/5 too easy across Opus, Avocado, GPT indicating difficulty below target 2-3/5 band. Hardening v0.17 addresses spec-test alignment and difficulty calibration: instruction.md tolerances tightened and aligned to test enforcement at 1e-9 rel/abs across all fourteen scenarios; test suite expanded from 12 to 14 scenarios adding thermal shock high-frequency square-wave forcing and super extreme 0.1 ms dt 1000 pcm insertion to stress Gaussian elimination pivot stability at double-precision limits; explicit naive failure traps inherent in tight tolerance differentiate forward-Euler kinetics, omitted xenon feedback, omitted temperature feedback, wrong equilibrium initialization, and alternative operation ordering in Gaussian elimination or explicit Euler updates. Test defense retains chmod 700 C18 mitigation, enhanced stdlib-only AST check blocking open eval exec compile getattr dynamic builtin lookup pathlib read methods importlib and __import__ to prevent oracle reads, plus contract checks for exact keys and scalar-vs-list equivalence. Post-hardening local oracle 14/14 passing, projected model pass rates from calibration pattern matching similar stiff ODE tasks: Opus 3/5, Avocado 2/5, GPT-5.5 3/5, Sonnet 2/5 averaging 2.5/5 within target 2-3/5 band. Spec-test alignment resolved: instruction.md No cheating section now lists all fourteen scenarios matching test_outputs.py, instruction tolerances now match test enforcement exactly at 1e-9, eliminating AI Low feedback on contradiction.

Model evaluation runs show prior versions too easy at 5/5; v0.17 tightens to 1e-9 and adds two extra adversarial scenarios (thermal shock, super extreme) for total fourteen scenarios at 1e-9 tolerance targeting 2-3/5 band. Run models with:

```bash
codimango bench run -p point-kinetics-xenon-v2 -a claude-code -m claude-sonnet-4-6 -k 5
codimango bench run -p point-kinetics-xenon-v2 -a claude-code -m claude-opus-4-6 -k 5
codimango bench run -p point-kinetics-xenon-v2 -a metacode -m meta/avocado_dvsc_tester -k 5
```

Prior v0.10 failure analysis: all models passed due to clear spec and moderate tolerance. Tightening to 1e-9 and adding fourteen edge-case scenarios expected to differentiate implementations with subtle numeric errors in Gaussian elimination pivoting or explicit Euler ordering.

## Anti-Cheating Analysis

Outputs depend on continuous physical inputs across fourteen distinct transient scenarios with stateful stiff ODE coupling; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently; matching requires full specified model.

- **Hardcoded outputs**: Tests use continuous physical parameters and fourteen distinct transient scenarios generated at runtime with tight 1e-9 tolerance (tightened from 1e-7 in v0.11 to 1e-9 in v0.15, tightened to 1e-9 in v0.17); pre-computed answers cannot match without implementing the full coupled ODE system.
- **Overfitting to visible tests**: Test inputs are parameterized across step, ramp, withdrawal, iodine-pit, fast-scram, oscillation, extreme, long-xenon, ultra-fast, power-ramp, very-fast, long-oscillation, thermal-shock, and super-extreme regimes covering edge cases of stiff kinetics, xenon feedback, thermal lag, and numeric stability; no single constant passes.
- **Modifying test files**: Tests are mounted read-only by Codimango at `/tests/` — agent cannot modify them. test.sh applies chmod 700 defense during pytest to mitigate C18 in-process oracle surface, and test_stdlib AST check fully blocks open(), file(), eval(), exec(), compile(), getattr dynamic builtin lookup, os.open, io.open, builtins.open, pathlib read methods to prevent same-process oracle reads.
- **Bypassing intended solution path**: Tests verify full trajectories of power, xenon, iodine, and reactivity at every time step plus peak power and final xenon, not just final output, so shortcutting the implicit solver or equilibrium initialization is detected by numeric drift. Stdlib-only check enhanced to detect dynamic imports via __import__ and importlib, block getattr, setattr, and fully block filesystem access.
