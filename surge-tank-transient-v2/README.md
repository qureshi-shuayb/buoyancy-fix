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

Oracle passes 100% locally with reference solution matching pinned explicit Euler order and Swamee-Jain friction. Task targets difficulty band 2-3/5 after hardening applied similar to sister tasks control-rod-worth-scram-v2 and pwr-primary-loop-v2 which are now passing. Hardening includes chmod 700 test defense, enhanced stdlib-only check blocking dynamic imports open eval exec, tightened tolerances peak 0.5m/2% min 0.5m steady 0.05m damping 2dt, and naive failure traps for frictionless, wrong sign, RK4, wrong Z0, wrong update order. Prior AI assessment _not yet run_ after af38cce; proactive fixes address test quality and spec-test alignment to calibrate toward moderate difficulty not too easy 5/5 nor too hard 0/5.

## Anti-Cheating Analysis

Outputs depend on continuous physical inputs across transient scenarios with stateful ODE coupling; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently.

- **Hardcoded outputs**: Tests use continuous physical parameters across multiple transient scenarios generated at runtime with tight tolerances; pre-computed answers cannot match without implementing full model.
- **Overfitting to visible tests**: Test inputs parameterized across multiple regimes covering edge cases of friction, damping, steady state, and transient behavior.
- **Modifying test files**: Tests mounted read-only by Codimango at `/tests/`; test.sh applies chmod 700 defense during pytest to mitigate C18 in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories not just final output, so shortcutting is detected by numeric drift. Stdlib-only check enforced to prevent external library bypass.
