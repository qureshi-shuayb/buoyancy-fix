# surge-tank-transient-v2

## Description
Implement rigid water-column ODE simulation of surge tank mass oscillation after turbine load rejection in Python. Tests cover explicit Euler integration order, Swamee-Jain friction factor, turbine closure ramp, steady-state initialization, peak/min/steady levels, and damping time scan. Naive frictionless, wrong-sign momentum, RK4 instead of Euler, wrong initial Z0, and wrong update order are caught by dedicated test cases with tight tolerances.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.6 | 5/5 (100%) |
| Avocado | 5/5 (100%) |
| GPT-5.5 | 5/5 (100%) |
| Sonnet 4.6 | _not yet run_ |

## Model Analysis

Oracle passes 3/3 locally with reference solution matching pinned explicit Euler order and Swamee-Jain friction. Codimango validation at f3558ea shows AI Accept C0 H0 M0 L2 with Low issues on undocumented test bans and completion table completeness, and agent pass rate 5/5 too easy across Opus, Avocado, GPT indicating difficulty below target 2-3/5 band. Hardening applied addresses Low feedback and difficulty calibration: README completion rates updated to reflect actual per-model outcomes from Codimango history (Oracle 3/3, Opus 5/5, Avocado 5/5, GPT 5/5), instruction spec-test contract alignment noted for stdlib-only enforcement blocking open eval exec dynamic imports, test suite expanded from 3 to 5 scenarios including high-friction low-surge-area edge case and long-tunnel slow-closure regime, tolerances tightened from peak 0.5m/2% to 0.3m/1% min 0.5 to 0.3 steady 0.05 to 0.03 damping 2dt to 1.5dt to increase sensitivity to numerical order errors and friction mis-modeling. Test defense includes chmod 700 C18 mitigation, enhanced stdlib-only check, naive failure traps for frictionless, wrong sign, RK4, wrong Z0, wrong update order, Ke branch coverage. Expected post-hardening difficulty targets 2-3/5 band similar to point-kinetics-v2 calibration pattern.

## Anti-Cheating Analysis

Outputs depend on continuous physical inputs across transient scenarios with stateful ODE coupling; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently.

- **Hardcoded outputs**: Tests use continuous physical parameters across multiple transient scenarios generated at runtime with tight tolerances; pre-computed answers cannot match without implementing full model.
- **Overfitting to visible tests**: Test inputs parameterized across multiple regimes covering edge cases of friction, damping, steady state, and transient behavior.
- **Modifying test files**: Tests mounted read-only by Codimango at `/tests/`; test.sh applies chmod 700 defense during pytest to mitigate C18 in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories not just final output, so shortcutting is detected by numeric drift. Stdlib-only check enforced to prevent external library bypass.
