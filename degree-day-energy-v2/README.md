# degree-day-energy-v2

## Description
A pure-Python tool that estimates a building's annual heating and cooling
**electricity** use (kWh) from a year of hourly outdoor temperatures. The agent
implements `/app/degree_days.py` with functions to parse the hourly temperature CSV
(`read_temps`), interpolate equipment-efficiency curves (`interp`), derive the
schedule-dependent balance points (`balance_points`), and produce the headline annual
heating/cooling electricity (`annual_energy`).

The difficulty is in **four interacting features**, not scaffolding — a solution that
implements any single feature but misses a coupling drifts past a tight 0.5% tolerance:

- **Bin method.** Energy is accumulated over **temperature bins** (kept separately per
  occupancy state), evaluated at each bin center — not as one running sum over raw hours.
- **Time-varying setback schedule.** Occupied and unoccupied hours use different setpoints
  and internal/solar gains, so the **derived** heating and cooling balance points
  (`heat_sp - gain_w/UA`, `cool_sp - gain_w/UA`) **change by hour-of-day**. A single fixed
  balance point misclassifies many hours' regime and load.
- **Part-load / temperature-dependent equipment.** The heating COP is a convex
  `[temp_c, cop]` curve interpolated per bin, but **below a lockout temperature** the heat
  pump is replaced by electric-resistance backup (COP 1.0). Cooling uses its own
  temperature-dependent COP curve. A constant average COP drifts because load concentrates
  at the cold, low-COP hours.
- **Economizer (free cooling).** Cooling bins **below the changeover temperature** are met
  with free outdoor air and draw **zero** compressor electricity. Counting them as
  compressor cooling overshoots cooling energy.

These couple: the setback shifts which hours need heating vs free cooling vs compressor
cooling; the backup engages only below the (schedule-dependent) heating regime; and
economizer availability depends on the active cooling balance point. The grader includes a
shoulder-season climate whose diurnal swing exercises heating, economizer free cooling,
and compressor cooling **within the same day**.

Other requirements: 8760- and 8784-row (leap) files are both valid; malformed CSV rows are
skipped; hour-of-day derives from position within the valid temperatures; all conversions
(W→kW, hour→energy) must reconcile.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 1.0 (verified locally in Docker; FINAL_REWARD=1) |
| Sonnet 4.6 | TBD |
| Opus 4.6 | TBD |
| Avocado | TBD |

The reference oracle passes the full grader in the `python:3.12-slim` container
(FINAL_REWARD=1). A naive implementation that drops the economizer, uses a fixed balance
point (ignoring the setback schedule), and applies a constant average COP fails the tight
0.5% energy tolerance (verified locally: FINAL_REWARD=0). Model rates to be populated from
Codimango runs.

## Model Analysis
TBD - from Codimango model runs.

## Anti-Cheating Analysis
- **Hardcoded outputs:** golden values are computed in-test by an independent reference
  over deterministic synthetic climates (fixed-seed seasonal + diurnal sinusoid + noise).
  There is no fixed constant to memorize; UA, schedule setpoints/gains, COP curves,
  lockout, economizer changeover, and bin width are parametrized across cases, and both a
  normal-year and a leap-year-length climate are graded.
- **Overfitting to visible tests:** the grader lives in `/tests` and is not present in
  `/app` during the solve; the agent only writes `degree_days.py`.
- **Modifying test files:** tests are mounted read-only and separate from the agent's
  working directory.
- **Bypassing the intended solution:** correctness requires all four interacting features
  — the bin accumulation, the schedule-dependent balance points, the interpolated heating
  and cooling COP curves with the resistance-backup lockout, and the economizer exclusion.
  The grader additionally asserts that each single-miss shortcut (no economizer, fixed
  balance point, constant average COP, ignoring the backup lockout) drifts more than 4× the
  0.5% tolerance away from the reference, so no partial solution can pass.

## v2 Clean Redo Note
This v2 scaffold replaces v1 due to policy violation in oracle development using third-party model. Task specification and difficulty calibration preserved from v1 to maintain tight 0.5% tolerance and four interacting features difficulty. All test tolerances grids anti-cheating checks identical to v1. Oracle reimplemented clean using approved models only.
