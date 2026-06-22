# Psychrometric Process Simulator (mini-DSL)

Implement a small **process simulator** for moist (humid) air, driven by a tiny
text **DSL**. A program is a sequence of air-conditioning process steps applied
to a moist-air state — set an initial condition, then heat, cool, humidify, and
mix in other air streams. Your simulator parses the program, runs the state
machine step by step, and reports the **final air state** plus cumulative
**energy** and **water** totals.

There is no library that implements this DSL — you must write the parser and the
per-step energy/mass bookkeeping yourself.

## Where to put your code

Create a single module at exactly:

```
/app/process_sim.py
```

It must expose one **module-level function**:

```python
def simulate(program: str) -> dict:
    ...
```

`program` is the full DSL source as a single string (with embedded newlines).
The return value is a `dict` with **exactly** these seven keys (all `float`):

| key            | meaning                                                        | units            |
|----------------|----------------------------------------------------------------|------------------|
| `t_db`         | final dry-bulb temperature                                     | °C               |
| `w`            | final humidity ratio                                           | kg water / kg dry air |
| `rh`           | final relative humidity (fraction, **0..1**, not percent)      | —                |
| `h`            | final moist-air specific enthalpy                              | kJ / kg dry air  |
| `q_sensible`   | cumulative **net** sensible energy (heating +, cooling −)      | kJ / kg dry air  |
| `q_latent`     | cumulative latent energy added by humidification               | kJ / kg dry air  |
| `water_added`  | cumulative water added by humidification                       | kg / kg dry air  |

## Units and constants

- Temperatures in **°C**, pressures in **Pa**.
- Atmospheric pressure is **constant** at `P = 101325 Pa` for all programs.
- Humidity ratio `W` in **kg water vapor / kg dry air**.
- Relative humidity is a **fraction in [0, 1]**. In the DSL it is written as a
  percent (e.g. `40%` → `0.40`).
- Enthalpy in **kJ / kg dry air**.
- All test programs keep temperatures in the range `0 °C < T < 100 °C`, and never
  cool air below its dew point (no condensation — cooling is purely sensible).

## Governing psychrometric relations

Use exactly these relations (do **not** substitute a different correlation, or
your relative humidity and enthalpy will not match the grader).

**Saturation vapor pressure over water** `p_ws(t)` [Pa], with `T = t + 273.15` in
kelvin — the ASHRAE 2017 Fundamentals over-water correlation:

```
ln(p_ws) = C8/T + C9 + C10*T + C11*T**2 + C12*T**3 + C13*ln(T)

C8  = -5.8002206e3
C9  =  1.3914993
C10 = -4.8640239e-2
C11 =  4.1764768e-5
C12 = -1.4452093e-8
C13 =  6.5459673
```

**Humidity ratio from relative humidity** (`p_w` = partial pressure of vapor):

```
p_w = rh * p_ws(t)
W   = 0.621945 * p_w / (P - p_w)
```

**Relative humidity from humidity ratio** (inverse of the above):

```
p_w = P * W / (0.621945 + W)
rh  = p_w / p_ws(t)
```

**Moist-air specific enthalpy** [kJ / kg dry air]:

```
h = 1.006 * t + W * (2501 + 1.86 * t)
```

**Recover dry-bulb temperature from `h` and `W`** (algebraic inverse of the
enthalpy relation — needed after mixing):

```
t = (h - 2501 * W) / (1.006 + 1.86 * W)
```

## DSL grammar

- The program is a sequence of lines, **one command per line**.
- Leading/trailing whitespace is ignored. Any run of spaces/tabs separating
  tokens is treated as a single separator.
- **Blank lines** and lines whose first non-whitespace character is `#` (full
  comment lines) are ignored.
- Command keywords are **case-insensitive** (`SET`, `Set`, `set` all work).
- Numbers are ordinary decimals (`10`, `10.0`, `0.0035`, `-3`, `1e-3`).
- The **first** non-ignored command must be `set`. Exactly one `set` per program.

Commands:

| syntax                         | example                  | effect |
|--------------------------------|--------------------------|--------|
| `set <T>C <RH>%`               | `set 35C 40%`            | Initialize state: `t_db = T`, `W = hum_ratio(T, RH)`. Resets all accumulators to 0. |
| `heat <x>`                     | `heat 10`                | Sensible heating by `x` °C. |
| `cool <x>`                     | `cool 5`                 | Sensible cooling by `x` °C. |
| `humidify <dW>`                | `humidify 0.002`         | **Isothermal** humidification: add `dW` kg/kg at constant dry-bulb. |
| `mix <frac> @ <T>C/<RH>%`      | `mix 0.3 @ 20C/60%`      | Adiabatically mix in an external stream. |

In the `set` and `mix` forms the `C` (after a temperature) and `%` (after a
relative humidity) suffixes are **required**. In `mix`, the `@` separates the
fraction from the stream state and the `/` separates the stream's temperature
from its relative humidity. The `@` and `/` delimiters and the `C`/`%` suffixes
may have optional surrounding whitespace, so all of these are valid and
equivalent:

```
mix 0.3 @ 20C/60%
mix 0.3@20C/60%
mix 0.3 @ 20 C / 60 %
```

## Exact process semantics (state machine)

State: dry-bulb `t`, humidity ratio `W`. Accumulators: `q_sensible`,
`q_latent`, `water_added` (all start at 0, reset by `set`).

**`set T RH`**
```
t = T
W = hum_ratio(T, RH)
q_sensible = q_latent = water_added = 0
```

**`heat x`** (sensible, `W` unchanged)
```
q_sensible += (1.006 + 1.86 * W) * x      # net heat; positive
t += x
```

**`cool x`** (sensible, `W` unchanged)
```
q_sensible += (1.006 + 1.86 * W) * (-x)   # net heat; negative for cooling
t -= x
```

**`humidify dW`** (isothermal: dry-bulb does **not** change)
```
q_latent    += dW * (2501 + 1.86 * t)
W           += dW
water_added += dW
```

**`mix frac @ T2 / RH2`** — `frac` is the **mass fraction (of dry air) of the
incoming stream in the resulting mixture**, in `(0, 1)`. Mix is an adiabatic
energy/mass balance on a dry-air basis; it does **not** add to `q_sensible`,
`q_latent`, or `water_added`:
```
W2 = hum_ratio(T2, RH2)
h2 = enthalpy(T2, W2)
h_cur = enthalpy(t, W)

W = (1 - frac) * W   + frac * W2
h = (1 - frac) * h_cur + frac * h2
t = (h - 2501 * W) / (1.006 + 1.86 * W)    # recover dry-bulb from h and W
```

> Mixing must use the **enthalpy / humidity-ratio balance** above and then
> recover the temperature. A linear temperature average
> `t = (1 - frac)*t + frac*T2` is **wrong** and will fail the grader whenever
> the two streams differ in humidity.

After running all commands, report the final state computed from `t` and `W`:
`rh = rel_hum(t, W)`, `h = enthalpy(t, W)`, alongside the three accumulators.

## Worked micro-example

```
set 20C 50%
heat 10
```
- `set`: `W = hum_ratio(20, 0.50) ≈ 0.007293`.
- `heat 10`: `q_sensible = (1.006 + 1.86*0.007293)*10 ≈ 10.195`, `t = 30`, `W` unchanged.
- Final: `t_db = 30`, `w ≈ 0.007293`, `rh ≈ 0.275` (heating dropped RH),
  `h ≈ 48.75`, `q_sensible ≈ 10.195`, `q_latent = 0`, `water_added = 0`.

## Constraints (important)

- **Pure standard library only.** You may use Python's `math` and `re`
  modules. You may **not** import or call any psychrometrics / thermodynamic
  property package. In particular, importing **`psychrolib`**, **`CoolProp`**,
  or **`pyromat`** is forbidden — the verifier reads your source and rejects the
  solution if any of these appear. Implement the relations yourself.
- Do not hardcode answers; your simulator is run on programs you cannot see in
  advance.

## How you are graded

Your `simulate(...)` outputs are compared against an **independent in-task
oracle** (implemented inside the verifier, not a third-party library) across
several DSL programs, including parser edge cases (extra whitespace, comment
lines, varied delimiter spacing) and programs with multiple `mix` steps.
Tolerances:

| Quantity                     | Tolerance        |
|------------------------------|------------------|
| `t_db`                       | 0.01 °C          |
| `w`                          | 1e-5 kg/kg       |
| `rh`                         | 0.002            |
| `h`, `q_sensible`, `q_latent`| 0.02 kJ/kg       |
| `water_added`                | 1e-6 kg/kg       |

All three test groups must pass.
