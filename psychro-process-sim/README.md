# psychro-process-sim

## Description
A psychrometric process simulator driven by a tiny text **DSL**. The agent
implements a parser and a moist-air state machine in `/app/process_sim.py`,
exposing a single `simulate(program: str) -> dict` function. A program is a
sequence of air-process commands applied to a moist-air state:

```
set 35C 40%        # initial state: dry-bulb + relative humidity
heat 10            # sensible heating (+10 C)
cool 5             # sensible cooling
humidify 0.002     # isothermal humidification: add humidity ratio (kg/kg)
mix 0.3 @ 20C/60%  # adiabatically mix in 30% of an external stream
```

`simulate` returns the **final air state** (`t_db`, `w`, `rh`, `h`) plus
cumulative **net sensible energy** (`q_sensible`), **latent energy**
(`q_latent`), and **total water added** (`water_added`).

The task is calibrated so a naive attempt fails. The difficulty is the
**parser + per-step bookkeeping**, not one-shot library recall — no library
implements this DSL. The three things that trip up shortcuts:

1. **Humidification is latent, not sensible.** `humidify` adds water at constant
   dry-bulb; the energy goes into `q_latent = dW*(2501 + 1.86*t)`, and relative
   humidity / enthalpy must reflect the new humidity ratio. Treating it as a
   sensible step gets the energy split, RH, and enthalpy wrong.
2. **Mixing is an enthalpy/humidity-ratio balance.** Streams are blended on a
   dry-air basis in `W` and `h`, then the temperature is recovered from
   `t = (h - 2501*W)/(1.006 + 1.86*W)`. A linear temperature average is wrong
   whenever the streams differ in humidity (≈0.58 °C error on the graded
   `set 40C 80%` → `mix 0.5 @ 5C/20%` case).
3. **RH must be recomputed after sensible steps.** Heating at constant `W`
   lowers relative humidity (saturation pressure rises); a solution that carries
   RH unchanged through `heat`/`cool` fails.

## Grading
Outputs are graded against an **independent in-task oracle** implemented inside
the verifier (`tests/test_outputs.py`) — **no** psychrometrics library is used
at grade time. The oracle parses the same DSL and applies the documented
semantics. Programs cover heating, isothermal humidification, high-contrast
mixing, sensible cooling, and a multi-step program with two mixes plus parser
edge cases (comments, irregular whitespace, varied `@` / `/` / `C` / `%`
spacing). Tolerances: `t_db` 0.01 °C, `w` 1e-5 kg/kg, `rh` 0.002, enthalpy and
energy totals 0.02 kJ/kg, `water_added` 1e-6 kg/kg.

Three test groups must all pass:
1. `test_programs_match_oracle` — final state + energy/water totals on 5 programs.
2. `test_parser_edge_cases` — whitespace/comment/delimiter robustness, multiple
   mixes, the enthalpy-vs-linear-T mixing guard, and the RH-drops-on-heating guard.
3. `test_no_library_wrapping` — anti-cheating source check.

## Completion Rates
| Agent | Pass rate |
|-------|-----------|
| Oracle | 3/3 (validated locally) |
| Naive stub (humidify-as-sensible + linear-T mix) | 0/3 (validated locally) |

## Anti-Cheating Analysis
- **Wrapping a library:** the verifier reads `/app/process_sim.py` and fails the
  solution if it contains `psychrolib`, `coolprop`, or `pyromat`. The agent must
  implement the relations directly (also stated in `instruction.md`).
- **Hardcoded outputs:** the grader runs multiple programs (and equivalent
  messy/clean variants), so constants cannot be memorized; every reported field
  is checked against the independent oracle within tight tolerances.
- **Overfitting to visible tests:** the grader and oracle live in `/tests` and
  are installed only by the verifier; they are not present in `/app` during the
  solve, so the agent cannot read or import them.
- **Modifying test files:** the agent only writes its module under `/app`; tests
  live in `/tests` and are not editable by the agent.
- **Bypassing the intended solution:** dedicated guards ensure mixing uses the
  enthalpy balance (not a linear temperature average) and that relative humidity
  drops after sensible heating, so the intended state-machine semantics are
  required to pass.
