# Altitude HVAC Sizing Pipeline (debugging)

A multi-file **R** program sizes the cooling system for a commercial building
located at high altitude (about **3000 m** elevation, roughly **70 kPa**
barometric pressure). The pipeline runs four coupled stages and threads the
results of each into the next:

1. **Design load calculation** (`R/load_calc.R`) — fixed space gains plus the
   load from conditioning outdoor (ventilation) air; produces the design
   sensible, latent, and total cooling loads.
2. **Cooling-coil / supply-air sizing** (`R/coil.R`) — supply air mass flow to
   offset the space sensible load, the corresponding volumetric airflow, and the
   coil load.
3. **Fan / duct** (`R/fan_duct.R`) — duct system pressure drop and fan electrical
   power.
4. **Plant sizing** (`R/plant.R`) — chiller capacity, including fan motor heat,
   with a sizing safety factor.

`R/air.R` holds shared constants and air-property helpers; `R/pipeline.R`
orchestrates the stages via `run_pipeline(inputs)`.

## The problem

At this altitude the air is significantly less dense than at sea level, which
changes air mass flows, ventilation loads, duct pressure, and fan power. The
pipeline runs without error, but **the final chiller sizing comes out wrong** —
it does not match a correct hand calculation for the design conditions. The
sizing is off because the altitude air-density assumption is **not applied
consistently** across the stages.

## Your task

Find where the air-density / altitude assumption is handled inconsistently and
make it consistent across the whole pipeline, so that every stage and the final
plant sizing are correct for the building's actual elevation.

### Constraints

- Keep the existing module layout and the public function interfaces:
  `run_pipeline(inputs)`, `stage1_loads`, `stage2_coil`, `stage3_fan`,
  `stage4_plant`, and the helpers in `R/air.R` keep their names and signatures.
- `run_pipeline(inputs)` must keep returning a list with `stage1`, `stage2`,
  `stage3`, `stage4`, each a named list of the same fields it returns today.
- **Base R only.** Do not add or use any external/CRAN package (no
  psychrometrics or HVAC library).
- Inputs are read from `data/design_inputs.csv`; do not change the input data.

## Running it

```
Rscript R/main.R
```

prints the per-stage results for the shipped design inputs.

## How it is graded

An independent base-R reference recomputes every stage and the final sizing
using a single, consistent site-altitude air density, across several building
scenarios at different elevations, and compares against your pipeline under tight
tolerances. Hard-coding results or wrapping an external library will not pass.
