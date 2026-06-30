# surge-tank-transient-v2

## Description
Implement rigid water-column ODE simulation of surge tank mass oscillation after turbine load rejection in Python. Tests cover explicit Euler integration order, Swamee-Jain friction factor, turbine closure ramp, steady-state initialization, peak/min/steady levels, and damping time scan. Naive frictionless, wrong-sign momentum, RK4 instead of Euler, wrong initial Z0, and wrong update order are caught by dedicated test cases with tight tolerances.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | _not yet run_ |
| Avocado | _not yet run_ |
| GPT-5.5 | _not yet run_ |
| Sonnet 4.6 | _not yet run_ |

## Model Analysis

No model evaluation runs found yet for latest version. Run models with codimango bench commands to populate. Prior versions indicated moderate difficulty with agent pass rates to be determined after hardening.

## Anti-Cheating Analysis

Outputs depend on continuous physical inputs across transient scenarios with stateful ODE coupling; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently.

- **Hardcoded outputs**: Tests use continuous physical parameters across multiple transient scenarios generated at runtime with tight tolerances; pre-computed answers cannot match without implementing full model.
- **Overfitting to visible tests**: Test inputs parameterized across multiple regimes covering edge cases of friction, damping, steady state, and transient behavior.
- **Modifying test files**: Tests mounted read-only by Codimango at `/tests/`; test.sh applies chmod 700 defense during pytest to mitigate C18 in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories not just final output, so shortcutting is detected by numeric drift. Stdlib-only check enforced to prevent external library bypass.
