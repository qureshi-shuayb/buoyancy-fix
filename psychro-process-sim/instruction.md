# PsychroLang — a moist-air process **interpreter**

Implement an interpreter for **PsychroLang**, a small imperative programming
language whose statements drive a psychrometric (moist / humid air) state
machine. A program initializes a moist-air state, then transforms it with
air-conditioning processes (heat, cool, condense, humidify, mix, recirculate,
…) **under real control flow** — named variables, arithmetic over the live
state, conditionals, counted and conditional loops, an implicit **fixed-point
recycle** that must be solved to convergence, and an embedded **control** step
that root-finds an actuator value to hit a target.

This is **not** a flat list of commands: blocks are brace-delimited and may
nest, numeric arguments are arbitrary expressions, and two constructs
(`recycle`, `control`) define *implicit* equations that you must solve
numerically. A line-by-line / regex parser cannot work; you must build a real
**tokenizer + parser + tree-walking interpreter** with a variable environment
and control flow.

There is no library that implements this language; write the parser, the
interpreter, and the psychrometric/energy bookkeeping yourself.

## Where to put your code

Create a single module at exactly:

```
/app/process_sim.py
```

exposing one **module-level function**:

```python
def simulate(program: str) -> dict:
    ...
```

`program` is the full PsychroLang source as a single string (with embedded
newlines). The return value is a `dict` with **exactly** these seven keys (all
`float`):

| key            | meaning                                                        | units            |
|----------------|----------------------------------------------------------------|------------------|
| `t_db`         | final dry-bulb temperature                                     | °C               |
| `w`            | final humidity ratio                                           | kg water / kg dry air |
| `rh`           | final relative humidity (fraction, **0..1**, not percent)      | —                |
| `h`            | final moist-air specific enthalpy                              | kJ / kg dry air  |
| `q_sensible`   | cumulative **net** sensible energy (heating +, cooling −)      | kJ / kg dry air  |
| `q_latent`     | cumulative **net** latent energy (humidify +, condensate −)    | kJ / kg dry air  |
| `water_added`  | cumulative **net signed** water (humidify +, condensate −)     | kg / kg dry air  |

> Sign conventions: `q_latent` and `water_added` are **net** totals. Removing
> water (condensation, or dehumidifying toward a drier target) contributes
> **negative** amounts.

On any malformed program (see *Errors*), `simulate` must **raise** an exception
(e.g. `ValueError`) and must **not** return a result.

## Units and constants

- Temperatures in **°C**; pressure in **Pa**, constant `P = 101325 Pa`.
- Humidity ratio `W` in **kg water vapor / kg dry air**.
- Relative humidity is a **fraction in [0, 1]** everywhere — in the source too
  (write `0.40`, **not** `40%`).
- Enthalpy in **kJ / kg dry air**.

## Governing psychrometric relations

Use **exactly** these relations (do not substitute a different correlation or a
rounded constant, or your RH / enthalpy / energy totals will miss the grader's
tight tolerances).

**Saturation vapor pressure over water** `p_ws(t)` [Pa], with `T = t + 273.15`
(ASHRAE 2017 Fundamentals, over-water):

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

**Relative humidity from humidity ratio** (inverse):

```
p_w = P * W / (0.621945 + W)
rh  = p_w / p_ws(t)
```

**Saturation humidity ratio** at temperature `t`: `W_sat(t) = hum_ratio(t, 1.0)`.

**Moist-air specific enthalpy** [kJ / kg dry air]:

```
h = 1.006 * t + W * (2501 + 1.86 * t)
```

**Recover dry-bulb from `h` and `W`** (algebraic inverse, needed after mixing):

```
t = (h - 2501 * W) / (1.006 + 1.86 * W)
```

---

# Language reference

## Lexical structure

- The source is tokenized over the **whole text** (it is **not** line-oriented).
- A `#` starts a **comment**: everything from `#` to the end of that line is
  discarded.
- **Whitespace** — spaces, tabs, carriage returns, **newlines**, and **`;`** —
  separates tokens but is **otherwise insignificant**. Newlines and semicolons
  are **not** statement terminators; statements are self-delimiting (below).
- **Numbers**: ordinary decimals with optional exponent: `10`, `10.0`,
  `0.0035`, `1e-3`, `.5`. A leading sign is **not** part of the number literal
  — `-3` is unary minus applied to `3` (see *Expressions*).
- **Identifiers**: `[A-Za-z_][A-Za-z0-9_]*`. An identifier is a **keyword**, a
  **state accessor**, or a **variable name**.
- **Operators / punctuation**: `+ - * / ( ) { } , < > <= >= == != = and or not`.

**Keywords** (reserved; cannot be variable names): `set heat cool sat humidify
mix process recirc recycle control to let if else repeat while and or not`.

**State accessors** (reserved; read the live state, cannot be variable names):
`t_db w rh h q_sensible q_latent water_added`.

## Tokens, statements, and self-delimitation

Because keywords are never operators and arguments are comma-separated,
expressions are **greedy but bounded**: an expression consumes tokens only
while the next token can continue it (an operator, or `(`). It **stops** at the
next keyword, `{`, `}`, `,`, `)`, or end of input. Therefore each statement is
unambiguously delimited by its own grammar; you do **not** need newline or `;`
terminators (they are simply skipped). For example `heat 2 heat 3` is two
statements (`heat 2`, then `heat 3`), while `heat 2 - 3` is one statement
(`heat (2-3)`). Real programs start each statement with a keyword, so this is
unambiguous; separating statements with newlines is recommended for readability
but has no semantic effect.

## Grammar (EBNF)

```
program     := statement+                  ; first statement MUST be `set`
block       := "{" statement* "}"

statement   := set_stmt | let_stmt
             | heat_stmt | cool_stmt | humidify_stmt
             | mix_stmt  | process_stmt | recirc_stmt
             | recycle_stmt | control_stmt
             | if_stmt | repeat_stmt | while_stmt

set_stmt      := "set" expr "," expr               ; t_db(°C) , rh(fraction)
let_stmt      := "let" IDENT "=" expr              ; declare or reassign
heat_stmt     := "heat" expr
cool_stmt     := "cool" expr [ "sat" ]
humidify_stmt := "humidify" expr
mix_stmt      := "mix" expr "," expr "," expr      ; frac , t2(°C) , rh2(frac)
process_stmt  := "process" expr "," expr           ; t_tar(°C) , rh_tar(frac)
recirc_stmt   := "recirc" expr                     ; supply fraction
recycle_stmt  := "recycle" expr block              ; supply fraction , body
control_stmt  := "control" ("heat"|"humidify") "to" ("rh"|"h") "=" expr
if_stmt       := "if" expr block [ "else" block ]
repeat_stmt   := "repeat" expr block
while_stmt    := "while" expr block

expr        := or_expr
or_expr     := and_expr ( "or" and_expr )*
and_expr    := not_expr ( "and" not_expr )*
not_expr    := "not" not_expr | cmp_expr
cmp_expr    := add_expr [ ("<"|">"|"<="|">="|"=="|"!=") add_expr ]
add_expr    := mul_expr ( ("+"|"-") mul_expr )*
mul_expr    := un_expr  ( ("*"|"/") un_expr )*
un_expr     := ("-"|"+") un_expr | primary
primary     := NUMBER | ACCESSOR | IDENT | "(" expr ")"
```

## Expression semantics

- Values are IEEE-754 floats. Booleans are floats: comparisons and `and/or/not`
  yield `1.0` (true) or `0.0` (false); `not x`, `and`, `or` treat any nonzero
  value as true. A condition in `if`/`while` is **true iff its value != 0.0**.
- `ACCESSOR` reads the **current** live state:
  `t_db`→`t`, `w`→`W`, `rh`→`rel_hum(t,W)`, `h`→`enthalpy(t,W)`,
  `q_sensible`/`q_latent`/`water_added`→ the running accumulators.
- `IDENT` (not a keyword/accessor) reads a variable; reading an **undefined**
  variable is an error.
- Operator precedence (low→high): `or`, `and`, `not`, comparison (non-chaining),
  `+ -`, `* /`, unary `-`/`+`, primary. Comparison is non-associative (at most
  one comparison per `cmp_expr`).
- `/` is floating division. Evaluation order of operands is left-to-right.

## State, accumulators, and `set`

State: dry-bulb `t`, humidity ratio `W`. Accumulators: `q_sensible`,
`q_latent`, `water_added` (start at 0). `set` also stores the **supply state**
`(t0, W0)` used by `recirc`/`recycle`. A variable environment maps names→floats.

- The program's **first statement must be `set`**, and `set` may appear **only**
  there (exactly one `set`, at top level). `set` anywhere else is an error.
- Any statement (or accessor) that uses the state **before** `set` has run is an
  error.

```
set T, RH:
    t  = T
    W  = hum_ratio(T, RH)
    t0, W0 = t, W
    q_sensible = q_latent = water_added = 0
```

## Process statement semantics

Let `enthalpy`, `hum_ratio`, `temp_from_h_w` be as defined above. Each `expr`
below is evaluated **once**, in order, against the current state.

**`heat x`** (sensible, `W` unchanged):
```
q_sensible += (1.006 + 1.86*W) * x ;  t += x
```

**`cool x`** (sensible, no condensation):
```
q_sensible += (1.006 + 1.86*W) * (-x) ;  t -= x
```

**`cool x sat`** (cooling with possible condensation):
```
t2 = t - x ;  W_sat2 = hum_ratio(t2, 1.0)
if W > W_sat2:
    dW          = W - W_sat2
    q_latent   -= dW * (2501 + 1.86*t2)
    q_sensible += (1.006 + 1.86*W_sat2) * (-x)   # sensible at the FINAL W
    water_added -= dW
    W = W_sat2                                    # leaves saturated (rh = 1)
else:
    q_sensible += (1.006 + 1.86*W) * (-x)
t = t2
```

**`humidify dW`** (isothermal; `t` unchanged):
```
q_latent += dW * (2501 + 1.86*t) ;  W += dW ;  water_added += dW
```
(`dW` may be **negative** to dehumidify.)

**`mix frac, T2, RH2`** — adiabatic mass/energy balance on a dry-air basis;
`frac` is the dry-air mass fraction of the **incoming** stream in the mixture.
Does **not** touch the accumulators:
```
W2 = hum_ratio(T2, RH2)
h_new = (1-frac)*enthalpy(t,W) + frac*enthalpy(T2,W2)
W     = (1-frac)*W             + frac*W2
t     = temp_from_h_w(h_new, W)
```

**`process T_tar, RH_tar`** — **order matters**: sensible to the target
dry-bulb first (booked with the *current* `W`), then isothermal
humidify/dehumidify to the target RH at the new temperature:
```
x = T_tar - t
q_sensible += (1.006 + 1.86*W) * x ;  t = T_tar
W_tar = hum_ratio(T_tar, RH_tar)
dW    = W_tar - W
q_latent += dW * (2501 + 1.86*t) ;  W = W_tar ;  water_added += dW
```
> `process` sets `W` directly to the target; it does **not** apply the
> `cool .. sat` condensation rule.

**`recirc frac`** — single-pass adiabatic blend of the current air with the
**original supply state** `(t0, W0)`; `frac` is the supply-air dry-mass
fraction. Does **not** touch the accumulators:
```
h_new = (1-frac)*enthalpy(t,W) + frac*enthalpy(t0,W0)
W     = (1-frac)*W             + frac*W0
t     = temp_from_h_w(h_new, W)
```

## Control-flow semantics

**`let x = e`** — evaluate `e`, bind/rebind variable `x`.

**`if c { A } [ else { B } ]`** — if `c != 0` run block `A`, else run `B`
(if present). Blocks introduce **no new scope**: variables and state changes
made inside persist.

**`repeat e { body }`** — evaluate `e` **once**; let `n = floor(e)`. `n` must be
`>= 0` (else error). Run `body` exactly `n` times in sequence.

**`while c { body }`** — re-evaluate `c` **before each** iteration; run `body`
while `c != 0`. Implementations must cap iterations (a runaway loop exceeding
1,000,000 iterations is an error).

## Implicit constructs (the hard part)

### `recycle frac { body }` — fixed point (must iterate to convergence)

Models a recycle/recycle-loop: a fraction `frac` of the **block output** is fed
back and blended with the fresh feed (the state at block entry) to form the
block input, so the block input depends on its own output — an **implicit
equation** that must be solved to convergence, **not** a single pass.

`frac` must satisfy `0 <= frac < 1` (else error). Let the state at entry be
`S_in = (t_in, W_in)` (captured once; accumulators are **not** reset). Define
the blend of a "recycle stream" `S = (t_S, W_S)` with the feed:

```
blend(S):
    W_b = (1-frac)*W_in + frac*W_S
    h_b = (1-frac)*enthalpy(t_in,W_in) + frac*enthalpy(t_S,W_S)
    t_b = temp_from_h_w(h_b, W_b)
    return (t_b, W_b)
```

Solve for the recycle stream fixed point `S*` such that
`S* = body( blend(S*) )`, by iteration:

```
S := S_in                                   # initial guess
repeat:
    in       := blend(S)
    scratch  := a COPY of the whole machine (state + accumulators + variables)
    set scratch state to `in`
    run `body` on scratch                   # all scratch effects are DISCARDED
    out      := (scratch.t, scratch.W)
    converged := |out.t - S.t| <= 1e-9  AND  |out.W - S.W| <= 1e-12
    S := out
until converged                             # (cap iterations; non-convergence is an error)
```

**Commit** (exactly once): set the live state to `blend(S*)` and run `body`
**once** on the **live** machine. That final pass is what updates the live
accumulators and the variable environment and produces the final state (which
equals `S*` to tolerance). In other words: the convergence iterations use a
throwaway copy and contribute **nothing** to `q_sensible/q_latent/water_added`
or to variables; only the single committed pass does.

> The fixed point converges geometrically (ratio ≈ `frac`) for the bodies used
> here. A single forward pass (treating the recycle stream guess as the entry
> state and running `body` once) gives a **different** answer and is wrong.

### `control <heat|humidify> to <rh|h> = e` — embedded root-find

Adjust **one actuator** by the amount that makes a target metric equal `e`,
then apply that amount (committing accumulators). The amount is **not** given;
you must **solve** for it. The solution is unique in the physical domain; solve
it to within `1e-9` in the metric (e.g. bisection). The grader compares the
resulting state, so any correct solver matches.

- **`control heat to rh = e`** — find the new dry-bulb `t*` (with `W` fixed)
  such that `rel_hum(t*, W) = e`, then apply it as a **sensible** change:
  ```
  x = t* - t ; q_sensible += (1.006 + 1.86*W) * x ; t = t*
  ```
  `rel_hum(t,W)` is strictly **decreasing** in `t` (heating lowers RH); the
  root is unique. Because `rel_hum` depends on `p_ws(t)` (the transcendental
  ASHRAE correlation), `t*` has **no closed form** — you must root-find. The
  solved `x` may be negative (net cooling) if `e` exceeds the current RH.

- **`control heat to h = e`** — find `t*` with `enthalpy(t*, W) = e`; apply as a
  sensible change exactly as above.

- **`control humidify to rh = e`** — find the new `W*` (with `t` fixed) such
  that `rel_hum(t, W*) = e`, then apply as a **latent** change:
  ```
  dW = W* - W ; q_latent += dW*(2501 + 1.86*t) ; W = W* ; water_added += dW
  ```
  `rel_hum` is strictly increasing in `W` here; the root is unique in
  `0 < W* < W_sat(t)` for `e` in `(0,1)`.

- **`control humidify to h = e`** — find `W*` with `enthalpy(t, W*) = e`; apply
  as a latent change exactly as above.

## Errors

`simulate` must raise (and not return) on, at least:

- a statement, or a state accessor, used before the first `set`;
- `set` that is not the first statement, or more than one `set`;
- an unrecognized statement keyword (e.g. `warmup 5`);
- a malformed statement (missing argument / comma / target / `=`);
- an unterminated `{ ... }` block;
- a `recycle` fraction outside `[0,1)`, or one that fails to converge;
- a `repeat` count `< 0`;
- a reference to an undefined variable.

## Worked micro-examples

```
set 20, 0.50
let n = 2 + 2
repeat n { heat 3 }
```
`set` gives `W ≈ 0.007269`; the loop runs 4× `heat 3` ⇒ `t = 32`,
`q_sensible = 4*(1.006 + 1.86*W)*3 ≈ 12.234`, `W` unchanged.

```
set 30, 0.50
recycle 0.6 { heat 5  humidify 0.001 }
```
Fixed point: with `frac = 0.6`, the converged dry-bulb satisfies
`t ≈ (1-0.6)*30 + 0.6*t + 5` (on the enthalpy balance) ⇒ `t_db ≈ 42.53`, and
`W ≈ W_in + 0.001/(1-0.6) = W_in + 0.0025`. The committed pass books **one**
`heat 5` + one `humidify 0.001` worth of energy/water. A single pass would give
`t_db = 35` (wrong).

```
set 18, 0.60
control heat to rh = 0.35
```
Root-find the sensible heating that drops RH from `0.60` to `0.35`:
`t_db ≈ 26.86` (uniquely solved against `p_ws`), `W` unchanged, `q_sensible > 0`.

## Constraints (important)

- **Pure standard library only.** You may use Python's `math` (and any stdlib).
  You may **not** import or call any psychrometrics / thermodynamic property
  package; importing **`psychrolib`**, **`CoolProp`**, or **`pyromat`** is
  forbidden — the verifier reads your source and rejects it if any appear.
  Implement the relations and the numerics (root-find, fixed point) yourself.
- Do not hardcode answers; your interpreter runs on programs you cannot see in
  advance.

## How you are graded

Your `simulate(...)` outputs are compared against an **independent in-task
oracle** (a full interpreter implemented inside the verifier — no third-party
library) across many PsychroLang programs exercising every construct: variables
and arithmetic over live state, `if/else`, `repeat`, `while`, condensation,
`process` (humidify and dehumidify), `mix`, `recirc`, the **fixed-point
`recycle`**, and the **root-finding `control`**, plus messy whitespace / inline
comments / nested braces and malformed-program error cases. Tolerances:

| Quantity                     | Tolerance        |
|------------------------------|------------------|
| `t_db`                       | 0.005 °C         |
| `w`                          | 5e-6 kg/kg       |
| `rh`                         | 0.001            |
| `h`, `q_sensible`, `q_latent`| 0.01 kJ/kg       |
| `water_added`                | 5e-7 kg/kg       |

All five test groups must pass.
