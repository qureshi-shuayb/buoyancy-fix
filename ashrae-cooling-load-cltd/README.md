# ashrae-cooling-load-cltd

## Description
A dependency-free Python function that computes a building's **peak design cooling
load** using the ASHRAE **CLTD/SCL/CLF** method. The agent implements
`peak_cooling_load(building, design)` in `/app/cooling_load.py`, returning the
sensible, latent, and total load (in watts) at the hour the total load peaks.

The task is a **domain-knowledge trap**. All the design tables (CLTD, SCL, CLF,
latitude-month, color factors, hourly outdoor profile) are handed to the agent as
input data, so the numbers are unambiguous. The difficulty is recognizing that the
**cooling load is not the instantaneous heat gain**:

1. **Opaque + glass conduction** must use the **corrected** CLTD — the tabulated
   CLTD adjusted for the latitude-month (LM) value, the surface-color factor K, and
   the gap between the job's actual indoor/outdoor design temperatures and the CLTD
   tables' base design conditions (indoor 25.5 °C, mean outdoor 29.4 °C). A plain
   `U·A·ΔT` is wrong.
2. **Glass solar** uses `A·SC·SCL` (the SCL table already embeds transmission and
   thermal lag).
3. **Internal gains** (lights, people sensible, equipment) must be multiplied by
   the hourly **cooling-load factor (CLF)** — mass delays and smears them — not
   taken as the full instantaneous gain. **Latent** gains (people latent,
   ventilation latent) convert immediately and carry **no** CLF.
4. Because of thermal lag, the **total load peaks at a different hour than the
   instantaneous heat gain**; the agent must evaluate all 24 hours and report the
   true peak.

A naive implementation that sums instantaneous heat gains
(`U·A·ΔT` + raw solar + full internal gains during occupied hours) computes the
wrong magnitude *and* often the wrong peak hour, and fails the tolerances.

Outputs are graded against an **independent in-test ASHRAE-method reference**
across three fixed buildings (west-glass office, east-glass office, roof-dominated)
plus several **seeded randomized** buildings, so answers cannot be hardcoded.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 3/3 (validated locally in Docker) |
| Sonnet 4.6 | TBD (not run) |
| Opus 4.6 | TBD (not run) |
| Avocado (metacode) | TBD (not run) |

Oracle validated locally in `python:3.12-slim` via the codimango oracle flow
(`solve.sh` + `test.sh`): **FINAL_REWARD=1**. A naive instantaneous-heat-gain
implementation scores **FINAL_REWARD=0**. Codimango model rates to be populated
from platform runs.

## Model Analysis
TBD — to be populated from Codimango model runs. Expected failure mode (by design):
agents compute instantaneous heat gain (`U·A·ΔT` + raw solar + raw internal) and
miss (a) the CLTD design-condition/LM/color corrections, (b) the CLF lag on
internal gains, and (c) that the load peaks at a later hour than the gain.

## Anti-Cheating Analysis
- **Hardcoded outputs:** the function is graded on three fixed scenarios **plus**
  several seeded randomized buildings generated at test time; the random scenario's
  building geometry, U-values, colors, internal loads, and design conditions are
  not knowable in advance, so memorized constants cannot pass.
- **Overfitting to visible tests:** the grader and the golden reference live in
  `/tests` and are not present in `/app` during the solve; the agent never sees the
  scenario definitions or the reference implementation while coding.
- **Wrapping a library:** the method is computed from first principles over
  supplied tables; there is no building-energy library to wrap, and the task
  requires standard library only.
- **Modifying test files:** the agent only writes `/app/cooling_load.py`; tests
  live in `/tests` and are not editable by the agent.
- **Bypassing the intended solution:** correctness across all scenarios requires
  the real CLTD correction (LM + color + design-condition shift), `SC·SCL` solar,
  the CLF lag on internal gains, and a true 24-hour peak search. A naive
  instantaneous heat-gain sum fails the 1 W tolerance and frequently reports the
  wrong peak hour.
