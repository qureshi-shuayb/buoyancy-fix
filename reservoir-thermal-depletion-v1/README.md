# reservoir-thermal-depletion-v1

## Description
Implement lumped 0D geothermal reservoir thermal depletion ODE in Python with explicit Euler integration. Model accounts for rock heat capacity, porosity-defined fluid mass, reinjection enthalpy inflow, production enthalpy outflow, and linear heat loss to ambient. Tests cover temperature trajectory elementwise, thermal breakthrough year detection, lifetime extracted thermal energy in MWh, and average temperature. Naive implementations ignoring heat loss, omitting rock thermal mass, using wrong Euler order, or mis-defining breakthrough are caught by dedicated test cases with tightened tolerances targeting medium difficulty.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.1 | TBD |
| Avocado | TBD |
| GPT-5 | TBD |
| Sonnet 4 | TBD |

## Model Analysis

Oracle passes locally with reference solution matching pinned explicit Euler order and energy balance. Projected difficulty medium based on similar ODE tasks requiring careful mass and energy bookkeeping, list vs scalar schedule handling, and exact breakthrough scan definition. Tolerances set to 1e-3 relative or 0.01 absolute for temperature, 1e-6 years breakthrough, 0.1% lifetime, 0.01 avg_T to discriminate naive variants while allowing floating rounding.

## Anti-Cheating Analysis

Outputs depend on continuous physical inputs across transient scenarios with stateful ODE coupling; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently.

- **Hardcoded outputs**: Tests use continuous physical parameters across multiple transient scenarios generated at runtime with tight tolerances; pre-computed answers cannot match without implementing full model.
- **Overfitting to visible tests**: Test inputs parameterized across multiple regimes covering edge cases of heat loss, varying production schedule, no-breakthrough case, and large dt explicit Euler sensitivity.
- **Modifying test files**: Tests mounted read-only by Codimango at `/tests/`; test.sh applies chmod 700 defense during pytest to mitigate C18 in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories not just final output, so shortcutting is detected by numeric drift. Stdlib-only check enforced to prevent external library bypass.
