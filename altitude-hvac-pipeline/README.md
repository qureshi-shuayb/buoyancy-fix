# altitude-hvac-pipeline

T-Bench task. A high-altitude HVAC sizing pipeline in R whose air-density
(altitude) correction is applied inconsistently across stages, producing wrong
final chiller sizing. The agent must trace the density assumption through all
four stages and make it consistent.

## Layout

```
environment/            # shipped to the agent (broken pipeline)
  Dockerfile            # rocker/r-ver:4.4.2, WORKDIR /app, COPY R/ and data/
  R/
    air.R               # constants + site_pressure() + air_density() + load_inputs()
    load_calc.R         # stage 1  (BUG: density at standard pressure)
    coil.R              # stage 2  (correct: density at site pressure)
    fan_duct.R          # stage 3  (BUG: density at standard pressure)
    plant.R             # stage 4
    pipeline.R          # run_pipeline(): sources stages, orchestrates
    main.R              # demo runner (Rscript R/main.R)
  data/design_inputs.csv
solution/
  solve.sh             # ORACLE: rewrites load_calc.R + fan_duct.R with site density
tests/
  test.sh              # runs run_tests.R, writes 1/0 to /logs/verifier/reward.txt
  run_tests.R          # independent base-R reference, 3 scenarios, anti-cheat
instruction.md          # agent-facing brief (symptom only; no stage named)
task.toml               # schema 1.1, name codimango/altitude-hvac-pipeline
```

## The inconsistency

Air density should always be evaluated at the **site** (altitude) pressure,
`air_density(site_pressure(elev))`. Stage 1 (ventilation load) and stage 3
(fan/duct) instead call `air_density(STANDARD_PRESSURE)` (sea-level). Stage 2
correctly uses site density. The fix changes the two buggy call sites.

## Cascade / difficulty

- Stage 1 density error -> wrong ventilation load -> wrong total load -> wrong
  coil load (stage 2 output) and wrong chiller (stage 4).
- Stage 3 density error -> wrong duct pressure & fan power -> wrong fan heat ->
  wrong chiller (stage 4).
- Fixing only one stage leaves the other's error in the final sizing, so a
  partial fix still fails (and the per-stage assertions also catch it).

## Validation

See the orchestrator handoff / task #36 notes for broken=0, oracle=1, and
partial-fix=fail results.
