# Psychrometric Process Simulator (mini-DSL)

Implement a small **process simulator** for moist (humid) air, driven by a tiny
text **DSL**. A program is a sequence of air-conditioning process steps applied
to a moist-air state — set an initial condition, then heat, cool (optionally
through the dew point, condensing water out), humidify, mix in other air
streams, drive to a target condition, and recirculate. Your simulator parses the
program, runs the state machine step by step, and reports the **final air state**
plus cumulative **energy** and **water** totals.

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
| `q_latent`     | cumulative **net** latent energy (humidify +, condensate −)    | kJ / kg dry air  |
| `water_added`  | cumulative **net signed** water (humidify +, condensate −)     | kg / kg dry air  |

> Note the sign conventions: `q_latent` and `water_added` are **net** totals.
> Removing water (condensation when cooling past saturation, or dehumidifying
> with `process to` toward a drier target) makes **negative** contributions.

## Units and constants

- Temperatures in **°C**, pressures in **Pa**.
- Atmospheric pressure is **constant** at `P = 101325 Pa` for all programs.
- Humidity ratio `W` in **kg water vapor / kg dry air**.
- Relative humidity is a **fraction in [0, 1]**. In the DSL it is written as a
  percent (e.g. `40%` → `0.40`).
- Enthalpy in **kJ / kg dry air**.

## Governing psychrometric relations

Use exactly these relations (do **not** substitute a different correlation or a
rounded constant, or your relative humidity, enthalpy and energy totals will not
match the grader's tight tolerances).

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

**Saturation humidity ratio** at temperature `t` is just `W_sat(t) = hum_ratio(t, 1.0)`.

**Moist-air specific enthalpy** [kJ / kg dry air]:

```
h = 1.006 * t + W * (2501 + 1.86 * t)
```

**Recover dry-bulb temperature from `h` and `W`** (algebraic inverse of the
enthalpy relation — needed after mixing/recirc):

```
t = (h - 2501 * W) / (1.006 + 1.86 * W)
```

## DSL grammar

- The program is a sequence of lines, **one command per line**.
- Leading/trailing whitespace is ignored. Any run of spaces/tabs separating
  tokens is treated as a single separator.
- A `#` begins a **comment**: everything from the first `#` to the end of the
  line is discarded **before** parsing. So `heat 10  # warm up` is just
  `heat 10`, and a line whose first non-blank character is `#` is a full-line
  comment.
- **Blank lines** (after comment stripping) are ignored.
- Command keywords are **case-insensitive** (`SET`, `Set`, `set` all work).
- Numbers are ordinary decimals (`10`, `10.0`, `0.0035`, `-3`, `1e-3`).
- The **first** non-ignored command must be `set`. Exactly one `set` per program.
- Any non-ignored line that does **not** match one of the commands below — or a
  command that appears before the first `set` — is a **hard error**: `simulate`
  must raise an exception (e.g. `ValueError`) and must **not** return a result.

Commands:

| syntax                         | example                  | effect |
|--------------------------------|--------------------------|--------|
| `set <T>C <RH>%`               | `set 35C 40%`            | Initialize state: `t_db = T`, `W = hum_ratio(T, RH)`. Resets all accumulators to 0 and records the **supply state** for `recirc`. |
| `heat <x>`                     | `heat 10`                | Sensible heating by `x` °C. |
| `cool <x>`                     | `cool 5`                 | Sensible cooling by `x` °C (no condensation). |
| `cool <x> sat`                 | `cool 15 sat`            | Cooling by `x` °C **with condensation** if the air reaches saturation. |
| `humidify <dW>`                | `humidify 0.002`         | **Isothermal** humidification: add `dW` kg/kg at constant dry-bulb. |
| `mix <frac> @ <T>C/<RH>%`      | `mix 0.3 @ 20C/60%`      | Adiabatically mix in an external stream. |
| `process to <T>C/<RH>%`        | `process to 24C/55%`     | Drive to a target dry-bulb **and** RH: sensible first, then (de)humidify. |
| `recirc <frac>`                | `recirc 0.4`             | Adiabatically mix the current air back with the **original supply state**. |

In the `set`, `mix` and `process to` forms the `C` (after a temperature) and `%`
(after a relative humidity) suffixes are **required**. In `mix` and `process to`,
`/` separates temperature from relative humidity; in `mix` the `@` separates the
fraction from the stream state. The `@`, `/`, `C` and `%` tokens may have
optional surrounding whitespace, so all of these are valid and equivalent:

```
mix 0.3 @ 20C/60%
mix 0.3@20C/60%
mix 0.3 @ 20 C / 60 %
process to 24C/55%
process  to  24 C / 55 %
```

## Exact process semantics (state machine)

State: dry-bulb `t`, humidity ratio `W`. Accumulators: `q_sensible`, `q_latent`,
`water_added` (all start at 0, reset by `set`). `set` also stores the supply
state `(t0, W0)`.

**`set T RH`**
```
t  = T
W  = hum_ratio(T, RH)
t0, W0 = t, W                       # remembered for recirc
q_sensible = q_latent = water_added = 0
```

**`heat x`** (sensible, `W` unchanged)
```
q_sensible += (1.006 + 1.86 * W) * x      # positive
t += x
```

**`cool x`** (sensible, `W` unchanged, no condensation)
```
q_sensible += (1.006 + 1.86 * W) * (-x)   # negative
t -= x
```

**`cool x sat`** (cooling with possible condensation)
```
t2     = t - x
W_sat2 = hum_ratio(t2, 1.0)               # saturation W at the final temp
if W > W_sat2:                            # air reached saturation -> condensation
    dW          = W - W_sat2              # condensed water (positive)
    q_latent   -= dW * (2501 + 1.86 * t2) # latent removed (negative contribution)
    q_sensible += (1.006 + 1.86 * W_sat2) * (-x)   # sensible at the FINAL W
    water_added -= dW                     # signed: water leaves the air
    W = W_sat2                            # air leaves saturated (rh = 1.0)
else:                                     # never reached saturation -> pure sensible
    q_sensible += (1.006 + 1.86 * W) * (-x)
t = t2
```

**`humidify dW`** (isothermal: dry-bulb does **not** change)
```
q_latent    += dW * (2501 + 1.86 * t)
W           += dW
water_added += dW
```

**`mix frac @ T2 / RH2`** — `frac` is the **mass fraction (of dry air) of the
incoming stream in the resulting mixture**, in `(0, 1)`. Adiabatic energy/mass
balance on a dry-air basis; it does **not** touch `q_sensible`, `q_latent`, or
`water_added`:
```
W2    = hum_ratio(T2, RH2)
h_new = (1 - frac) * enthalpy(t, W) + frac * enthalpy(T2, W2)
W     = (1 - frac) * W              + frac * W2
t     = (h_new - 2501 * W) / (1.006 + 1.86 * W)
```

**`process to T_tar / RH_tar`** — combined conditioning, **order matters**:
sensible to the target dry-bulb first (booked with the current `W`), then
isothermal humidify/dehumidify to the target RH at the new temperature:
```
x           = T_tar - t                   # may be negative (net cooling)
q_sensible += (1.006 + 1.86 * W) * x      # uses the CURRENT W
t           = T_tar
W_tar       = hum_ratio(T_tar, RH_tar)
dW          = W_tar - W                   # signed (negative => dehumidify)
q_latent   += dW * (2501 + 1.86 * t)
W           = W_tar
water_added += dW
```
> `process to` sets `W` directly to the target; it does **not** apply the
> `cool .. sat` condensation rule even when the sensible part cools the air.

**`recirc frac`** — adiabatically mix the current air back with the **original
supply state** `(t0, W0)` captured at `set`. `frac` is the mass fraction (of dry
air) of the supply state in the result; it does **not** touch the accumulators:
```
h_new = (1 - frac) * enthalpy(t, W) + frac * enthalpy(t0, W0)
W     = (1 - frac) * W              + frac * W0
t     = (h_new - 2501 * W) / (1.006 + 1.86 * W)
```

After running all commands, report the final state computed from `t` and `W`:
`rh = rel_hum(t, W)`, `h = enthalpy(t, W)`, alongside the three accumulators.

## Worked micro-examples

```
set 20C 50%
heat 10
```
- `set`: `W = hum_ratio(20, 0.50) ≈ 0.007293`.
- `heat 10`: `q_sensible = (1.006 + 1.86*0.007293)*10 ≈ 10.195`, `t = 30`.
- Final: `t_db = 30`, `w ≈ 0.007293`, `rh ≈ 0.275`, `h ≈ 48.75`,
  `q_sensible ≈ 10.195`, `q_latent = 0`, `water_added = 0`.

```
set 30C 70%
cool 15 sat
```
- `set`: `W ≈ 0.01880` (above `W_sat(15) ≈ 0.01065`).
- `cool 15 sat`: condensation. `dW ≈ 0.00815` of water condenses out,
  `W` clamps to `W_sat(15)`, `t = 15`, `rh ≈ 1.0`,
  `q_latent ≈ -dW*(2501+1.86*15) < 0`, `water_added ≈ -0.00815 < 0`.

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
several DSL programs that exercise every command — heating, isothermal
humidification, high-contrast mixing, cooling **with condensation**, `process to`
both humidifying and dehumidifying, `recirc`, and a multi-step combo with inline
comments and irregular whitespace. The verifier also checks that malformed or
out-of-order programs raise. Tolerances:

| Quantity                     | Tolerance        |
|------------------------------|------------------|
| `t_db`                       | 0.005 °C         |
| `w`                          | 5e-6 kg/kg       |
| `rh`                         | 0.001            |
| `h`, `q_sensible`, `q_latent`| 0.01 kJ/kg       |
| `water_added`                | 5e-7 kg/kg       |

All test groups must pass.
