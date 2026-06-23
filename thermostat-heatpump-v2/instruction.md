# Thermostat + Heat-Pump Building Simulation (with Defrost, Cycling Losses, and Anti-Short-Cycling)

You will implement a Python simulation of one day of a single-zone building that
is heated by a **deadband (hysteresis) thermostat** controlling an **air-source
heat pump**. Real air-source heat pumps are not ideal single-stage boxes, so this
model layers three interacting effects on top of the basic thermostat:

1. an **anti-short-cycle** minimum compressor run-time and off-time that overrides
   the bare deadband,
2. periodic **defrost cycles** when the outdoor air is inside a defrost band, and
3. **part-load cycling degradation** that lowers the effective COP.

A heat-pump capacity limit plus **backup electric-resistance heat** make up any
shortfall (including the heat lost during defrost). Your simulator must report the
total electrical energy consumed (including defrost and backup) and the comfort
violations over the horizon.

This is a numerical-modeling task: the grader imports your module and checks the
returned numbers against an independent reference, so the quantities below must be
computed exactly as specified.


## Deliverable

Create a single file **`/app/hvac_sim.py`** that defines a function with this
exact signature (the grader calls it by keyword argument):

```python
def simulate(
    t_out,              # outdoor temperature [degC]: float (constant) OR list of length n_steps
    dt,                 # time-step size [s], float
    n_steps,            # number of integration steps, int
    setpoint,           # thermostat setpoint [degC], float
    deadband,           # full deadband width [degC], float (band is setpoint +/- deadband/2)
    R,                  # zone thermal resistance [K/W], float
    C,                  # zone thermal capacitance [J/K], float
    t_initial,          # initial indoor temperature [degC], float
    cop_curve,          # list of [t_out_degC, COP] points (rated heat-pump COP vs outdoor temp)
    hp_capacity,        # heat-pump rated thermal output [W], float
    backup_capacity,    # backup resistance rated thermal output [W], float
    internal_gain,      # internal heat gain [W]: float (constant) OR list of length n_steps
    defrost_band,       # [t_lo_degC, t_hi_degC]: defrost band (inclusive) for outdoor temp
    defrost_interval,   # defrost interval [MINUTES] of accumulated in-band compressor run-time
    defrost_duration,   # defrost duration [MINUTES]
    defrost_cop_factor, # COP multiplier applied during defrost (0 < factor <= 1), float
    Cd,                 # cycling (part-load) degradation coefficient, float
    min_runtime,        # minimum compressor ON time [SECONDS], float
    min_offtime,        # minimum compressor OFF time [SECONDS], float
) -> dict:
    ...
```

> **Unit caution.** `dt`, `min_runtime`, and `min_offtime` are in **seconds**;
> `defrost_interval` and `defrost_duration` are in **minutes**. Convert carefully.

The returned `dict` MUST contain exactly these keys:

| key | type | meaning |
|-----|------|---------|
| `energy_kwh` | `float` | total electrical energy consumed over the horizon (heat pump + defrost + backup), in kWh |
| `comfort_degree_hours` | `float` | total comfort violation, in degree-hours (degC*h) outside the deadband |
| `indoor_temp` | `list[float]` | indoor temperature trajectory, length `n_steps + 1` |

`indoor_temp[0]` must equal `t_initial`, and `indoor_temp[k]` is the indoor
temperature at the **end** of step `k` (so the list has `n_steps + 1` entries).

For step index `n` (0-based), use `t_out` and `internal_gain` at index `n` when
those arguments are lists; if an argument is a scalar it applies to every step.


## Zone thermal model (1R1C)

The single zone is a lumped-capacitance (one-resistance, one-capacitance) model:

```
C * dT_in/dt = (t_out - T_in) / R + internal_gain + Q_hvac
```

where `Q_hvac` is the net **useful** heating power delivered to the zone during the
step (heat-pump heat actually delivered plus backup heat; see below).

**Integration requirement (pinned for determinism).** Over each step the inputs
(`t_out`, `internal_gain`, `Q_hvac`) are held constant, so the ODE is linear and
has a closed form. You MUST advance the state with this exact analytic update
(not forward Euler):

```
tau   = R * C
T_eq  = t_out + R * (internal_gain + Q_hvac)
T_in(t + dt) = T_eq + (T_in(t) - T_eq) * exp(-dt / tau)
```


## Control: deadband plus anti-short-cycling

The compressor is governed first by a two-state (ON/OFF) hysteresis controller for
**heating only** (there is no cooling), and then by a minimum-cycle constraint that
can override it.

Let `lo = setpoint - deadband/2` and `hi = setpoint + deadband/2`.

**1. Deadband "call".** At the start of each step, form a desired call from the
**current** indoor temperature: call for heat when the indoor temperature is below
`lo`; release the call when it is above `hi`; otherwise keep the previous call (no
chattering between `lo` and `hi`).

**2. Anti-short-cycle override.** The compressor cannot switch faster than its
minimum cycle times:

- Once the compressor turns ON it must stay ON for at least `min_runtime` seconds.
  If the deadband releases the call before the compressor has run that long, the
  compressor stays ON anyway until `min_runtime` is reached.
- Once the compressor turns OFF it must stay OFF for at least `min_offtime`
  seconds. If the deadband calls for heat before the compressor has been off that
  long, the start is blocked until `min_offtime` is reached.

The compressor starts **OFF** and is treated as already having satisfied its
minimum off-time, so it may start on the first step if called. The "time in the
current state" used for these comparisons is measured at the **start** of the step
(before the step runs). When the compressor is OFF, `Q_hvac = 0` and no
electricity is consumed.


## Defrost cycles

When the outdoor temperature is inside the (inclusive) `defrost_band`, frost
accumulates on the outdoor coil and the heat pump must periodically defrost.

- Defrost is scheduled on **accumulated in-band compressor run-time**: only steps in
  which the compressor is ON *and* the outdoor temperature is inside `defrost_band`
  add to this accumulator. When the accumulator reaches `defrost_interval`
  (minutes), the heat pump enters defrost for `defrost_duration` (minutes), after
  which the accumulator restarts from zero. Time spent defrosting does not add to
  the accumulator. Time while the compressor is OFF, or while the outdoor air is
  outside the band, neither advances the accumulator nor a defrost in progress (it
  is simply held).
- **During defrost the heat pump delivers no useful heat to the zone** (its
  capacity goes into melting frost), yet it still draws electricity, and at a
  degraded efficiency: the COP used for its electrical draw is the rated COP at the
  current outdoor temperature multiplied by `defrost_cop_factor`. Its electrical
  draw during defrost corresponds to running the compressor at its rated thermal
  capacity against that degraded COP.
- Because the heat pump contributes nothing during defrost, **backup resistance
  heat covers the heating load during a defrost step** (subject to its capacity
  limit; see below).


## Heat pump, part-load degradation, capacity limit, and backup heat

While the compressor is ON and **not** defrosting:

- The heat pump runs at its full rated thermal output `hp_capacity`.
- The **rated COP is read from `cop_curve`** by **linear interpolation** in outdoor
  temperature. `cop_curve` is a list of `[t_out, COP]` points; interpolate linearly
  between the two surrounding points, and **clamp** to the nearest endpoint COP for
  outdoor temperatures below the first or above the last point.
- **Part-load cycling degradation.** A unit that only needs to meet part of its
  capacity cycles and loses efficiency. Define the part-load ratio over the step as
  `PLR = min(1, load / hp_capacity)`, where `load = max(0, (setpoint - t_out) / R)`
  is the conductive heating load at the setpoint. The part-load factor is
  `PLF = 1 - Cd * (1 - PLR)`, and the **effective COP is the rated (interpolated)
  COP multiplied by `PLF`**. The heat pump's electrical input is its thermal output
  divided by this effective COP.

**Backup resistance heat** supplies any shortfall on cold days and during defrost.
The building's conductive heating load at the setpoint is `load` (defined above,
never negative). The deficit the backup must cover is the load minus the heat-pump
thermal output **actually delivered this step** — which is `hp_capacity` during
normal heating but **zero during defrost**. The backup supplies that deficit (never
negative) limited to `backup_capacity` watts. Backup resistance heat has a COP of 1
(its electrical input equals its thermal output).

The net useful heat delivered to the zone while ON is the heat-pump heat actually
delivered (zero during defrost) plus the backup heat, and that net heat is the
`Q_hvac` used in the zone update above.


## Energy accounting

`energy_kwh` is the total **electrical** energy drawn over the horizon: at each
step sum the heat-pump electrical input (normal-heating draw, or the degraded
defrost draw, or zero while OFF) and the backup electrical input, multiply by the
step duration, and accumulate. Watts integrated over seconds gives joules; report
the total in **kilowatt-hours**.


## Comfort accounting

`comfort_degree_hours` measures how far, and for how long, the indoor temperature
strays **outside** the deadband. At each step, using the indoor temperature at the
**end** of that step, the instantaneous violation is:

- `lo - T_in` when `T_in < lo`,
- `T_in - hi` when `T_in > hi`,
- `0` when `T_in` is within `[lo, hi]`.

Weight each step's violation by the step duration expressed in **hours** and sum
over all `n_steps` steps. The result is in degree-hours (degC*h).


## Constraints and notes

- Pure standard-library Python is sufficient; you may use `math`. Do not require
  any third-party package for `hvac_sim.py`. (In particular, do not use `scipy` or
  any ODE integrator — the analytic update above is mandatory.)
- Be careful with units: `dt`, `min_runtime`, `min_offtime` are in seconds;
  `defrost_interval`, `defrost_duration` are in minutes; energy is reported in kWh
  and comfort in degree-hours.
- The function must be **pure and deterministic**: same inputs -> same outputs,
  with no global state, randomness, file, or network access.


## No cheating

The grader is held out: it is not in `/app` and you will not see it during the
task. It imports your `simulate` and checks `energy_kwh`, `comfort_degree_hours`,
and the `indoor_temp` trajectory against an **independent** reference over several
scenarios (a mild in-band day that cycles and defrosts, a cold day below the band
that forces backup heat, a cold humid in-band day that forces defrost + backup +
cycling at once, and a day with a varying outdoor-temperature profile). Do not
attempt to detect, special-case, or hard-code grader inputs or expected outputs;
solutions must implement the model as specified for arbitrary inputs.
