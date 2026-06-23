# chiller-plant-discovery

Spec-discovery (inference) task in **Julia**. The agent must reverse-engineer the
missing cross-subsystem coupling and sequencing logic of a chilled-water plant
model from a battery of golden operating points — the equations are deliberately
not stated.

## Layout

```
environment/            # shipped to the agent (becomes /app)
  Project.toml          # ChillerPlant package (no deps, offline)
  Dockerfile            # julia:1-slim, WORKDIR /app, COPY src + data
  src/
    ChillerPlant.jl     # module: includes the files below
    chiller.jl          # COP curves (correct, fixed)
    tower.jl            # cooling-tower approach (correct, fixed)
    pumps.jl            # pump power (correct, fixed)
    plant.jl            # coupling + sequencing  <-- STUBBED, agent implements
  data/
    golden_vectors.csv  # 10 visible evidence rows (input -> expected outputs)
solution/
  solve.sh             # ORACLE: writes the complete correct src/ into /app
tests/
  test.sh              # runs the verifier, writes 1/0 to /logs/verifier/reward.txt
  runtests.jl          # independent golden battery (16 rows) + anti-cheat; stdlib Test
instruction.md
task.toml              # schema 1.1, name codimango/chiller-plant-discovery
README.md
```

## The rule to discover

For a configuration of `n` equally-loaded chillers meeting cooling `demand` at
ambient `wetbulb`:

- **Equal split:** each chiller runs at `plr = (demand / n) / Q_RATED`.
- **Energy-balance coupling:** the tower must reject the evaporator load **plus**
  the compressor work, `q_reject = demand + demand/cop`. Since `cop` depends on
  the condenser-water temperature `cwt = wetbulb + approach(q_reject)`, the
  operating point is implicit and is solved by a **fixed-point iteration** on
  `cwt`.
- **Min-power sequencing:** among all chiller counts keeping `plr` within
  `[PLR_MIN, PLR_MAX]`, run the one that **minimises total electric power**
  (compressor + pumps), ties to fewer chillers.

This is uniquely determined by the vectors (boundary rows at demand ≈ 1000 kW and
≈ 1800 kW pin the staging decision; the `cwt` column pins the compressor-heat
term), yet not stated. The shipped stub — which ignores compressor heat in the
tower load and runs the fewest feasible chillers — fails, as does a "most
efficient part-load" guess.

## Difficulty lever

Discovery / inference: the agent must infer the governing coupling rules from
input→output evidence rather than transcribe a given formula.

## Validation

- Oracle (`solution/solve.sh`) → all tests pass → reward 1.
- Shipped stub (partial `src/plant.jl`) → tests fail → reward 0.
- Naive guesses (no compressor heat; fewest-chillers staging) → fail.

Every code, script, and data file carries the t-bench canary GUID.
