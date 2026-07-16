## Description
Two-step buoyancy task: Step 1 implements basic float/sink/neutral decision using Archimedes principle in Go. Step 2 extends same package to compute submerged volume fraction and equilibrium depth for partially submerged bodies plus batch processing, relying on Step 1's types without redefining them. Tests buoyancy physics with context-following.

Why naive fails: simple density compare misses neutral buoyancy tolerance, partial submersion requires rho_obj/rho_fluid ratio with height, batch handling, and remembering prior struct conventions.

## Completion Rates
| Model | Step | Pass Rate (of trials reaching this step) | Last Updated |
|---|---|---|---|
| Oracle | 1_basic_float_check | TBD | TBD |
| Oracle | 2_partial_submersion | TBD | TBD |
| meta/avocado | 1_basic_float_check | TBD | TBD |
| meta/avocado | 2_partial_submersion | TBD | TBD |
| anthropic/opus | 1_basic_float_check | TBD | TBD |
| anthropic/opus | 2_partial_submersion | TBD | TBD |

Cascade verdict (this iteration): TBD

## Model Analysis
TBD — will be populated after agent trials.

## Anti-Cheating Analysis
- Hardcoded outputs: many density/mass combos parameterized, not in repo
- Overfitting to visible tests: tests in /tests not visible in /app during solve
- Modifying test files: tests separate, read-only mount
- Bypassing intended solution: must implement actual Archimedes physics, not shortcut

## Notes
Manually scaffolded due to codimango template fetch network error. Structure matches multi-step spec: schema_version 1.1, [[steps]], inherit_prior_session true on step 2.
