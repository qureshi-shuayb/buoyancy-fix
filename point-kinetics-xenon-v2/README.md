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

## Grading
`tests/test_outputs.py` imports agent's `/app/reactor_kinetics.py` and compares outputs against independent reference over four scenarios:
- **step reactivity insertion** – small positive step, power excursion limited by Doppler,
- **ramp load-follow** – power ramp down then up, xenon transient overshoot,
- **rod withdrawal** – rapid withdrawal with Doppler limiting peak,
- **iodine pit restart** – shutdown then attempted restart into xenon peak, power suppressed.

Plus contract checks and scalar-vs-list equivalence. Verifier writes `/logs/verifier/reward.txt`.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 5/5 local validate.py |
| Sonnet | TBD |

## Anti-Cheating Analysis
Outputs depend on continuous physical inputs across four distinct transient scenarios with stateful stiff ODE coupling; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently; matching requires full specified model.

## v2 Note
Initial scaffold for nuclear plant simulator task suite.
