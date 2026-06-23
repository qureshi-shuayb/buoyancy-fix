# Chiller Plant — Discover the Coupling

You are given a small, multi-file Julia model of a commercial **chilled-water
plant**:

- `src/chiller.jl` — identical water-cooled chillers. Electric COP is a rated COP
  scaled by a **part-load factor** and a **condenser-water temperature factor**.
- `src/tower.jl` — a single **cooling tower**. It supplies condenser water at the
  ambient **wet-bulb** temperature plus an **approach** that grows with the heat
  it must reject.
- `src/pumps.jl` — constant-speed **pumps**: a fixed parasitic draw per running
  chiller.
- `src/plant.jl` — the **plant coupling and the sequencing controller**.
  **This file is incomplete — it is your job to finish it.**

The three subsystem files are correct and must not be changed. What is missing is
how they fit together into a working plant, and how the controller decides how
many chillers to run.

## Your task

Implement the two functions in `src/plant.jl` so the plant reproduces the
provided golden operating points:

```julia
solve_stage(demand::Float64, wetbulb::Float64, n::Int)
#   -> (power, cwt, plr, cop)   or   nothing if n chillers cannot serve demand

solve_plant(demand::Float64, wetbulb::Float64)
#   -> (plant_power, cwt, n_chillers, plr)
```

Keep the function names, the argument order, and the returned **field names**
exactly as documented in `src/plant.jl`. All quantities are SI-ish:
demand and power in **kW**, temperatures in **°C**, `plr` is a fraction, and
`n_chillers` is an integer.

## What you must figure out

**The governing equations are intentionally not given.** You are given evidence
instead: `data/golden_vectors.csv` lists known-correct steady-state solutions —
for each cooling `demand` and ambient `wetbulb`, the true plant power, the
condenser-water supply temperature, the number of chillers the controller runs,
and the per-chiller part-load ratio.

Infer, from that evidence, the rules that connect the subsystems:

- how the cooling load is distributed across the running chillers,
- how the cooling tower, the chillers, and the pumps interact to set the
  condenser-water temperature and the total power (note that the tower and the
  chillers are *mutually* dependent — read the columns carefully), and
- how the controller chooses how many chillers to run.

A solution that merely chains the subsystems together in the obvious way will
**not** match the evidence. The rules are uniquely pinned down by the vectors —
find the ones that reproduce **every** row, then make sure they generalise.

## Constraints

- **Julia standard library only.** Do not add dependencies, do not access the
  network, and do not import third-party numerical or thermodynamics packages
  (e.g. `Roots`, `NLsolve`, `Clapeyron`, `Unitful`). Implement any iteration
  yourself.
- Do not hardcode the answers. You are graded on operating points that are not
  in the file you can see.

## How you are graded

A network-free verifier loads your package and runs `solve_plant` over an
independent battery of operating points — the visible evidence **plus held-out
demands and wet-bulbs** — and checks plant power, condenser-water temperature,
chiller count, and part-load ratio within tight tolerances. It also verifies the
condenser/chiller coupling you implemented is physically self-consistent, and
rejects external packages or embedded answer tables.
