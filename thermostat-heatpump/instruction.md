# Thermostat + Heat-Pump Building Simulation

You will implement a Python simulation of one day of a single-zone building that
is heated by a **deadband (hysteresis) thermostat** controlling an **air-source
heat pump** whose efficiency (COP) depends on the outdoor temperature. The heat
pump has a fixed thermal capacity, and **backup electric-resistance heat** makes
up any shortfall on cold days. Your simulator must report the total electrical
energy consumed and the comfort violations over the horizon.

This is a numerical-modeling task: the grader imports your module and checks the
returned numbers against an independent reference, so the quantities below must be
computed exactly as specified.


## Deliverable

Create a single file **`/app/hvac_sim.py`** that defines a function with this
exact signature (the grader calls it by keyword argument):

```python
def simulate(
    t_out,            # outdoor temperature [degC]: float (constant) OR list of length n_steps
    dt,               # time-step size [s], float
    n_steps,          # number of integration steps, int
    setpoint,         # thermostat setpoint [degC], float
    deadband,         # full deadband width [degC], float (the band is setpoint +/- deadband/2)
    R,                # zone thermal resistance [K/W], float
    C,                # zone thermal capacitance [J/K], float
    t_initial,        # initial indoor temperature [degC], float
    cop_curve,        # list of [t_out_degC, COP] points (heat-pump COP vs outdoor temp)
    hp_capacity,      # heat-pump rated thermal output [W], float
    backup_capacity,  # backup resistance rated thermal output [W], float
    internal_gain,    # internal heat gain [W]: float (constant) OR list of length n_steps
) -> dict:
    ...
```

The returned `dict` MUST contain exactly these keys:

| key | type | meaning |
|-----|------|---------|
| `energy_kwh` | `float` | total electrical energy consumed over the horizon, in kWh |
| `comfort_degree_hours` | `float` | total comfort violation, in degree-hours (degC*h) outside the deadband |
| `indoor_temp` | `list[float]` | indoor temperature trajectory, length `n_steps + 1` |

`indoor_temp[0]` must equal `t_initial`, and `indoor_temp[k]` is the indoor
temperature at the **end** of step `k` (so the list has `n_steps + 1` entries).


## Zone thermal model (1R1C)

The single zone is a lumped-capacitance (one-resistance, one-capacitance) model:

```
C * dT_in/dt = (t_out - T_in) / R + internal_gain + Q_hvac
```

where `Q_hvac` is the net heating power delivered to the zone during the step.

**Integration requirement (pinned for determinism).** Over each step the inputs
(`t_out`, `internal_gain`, `Q_hvac`) are held constant, so the ODE is linear and
has a closed form. You MUST advance the state with this exact analytic update
(not forward Euler):

```
tau   = R * C
T_eq  = t_out + R * (internal_gain + Q_hvac)
T_in(t + dt) = T_eq + (T_in(t) - T_eq) * exp(-dt / tau)
```

For step index `n` (0-based), use `t_out` and `internal_gain` at index `n` when
those arguments are lists; if an argument is a scalar it applies to every step.


## Thermostat (deadband hysteresis, heating only)

The thermostat is a two-state (ON/OFF) hysteresis controller for **heating only**
(there is no cooling). Let `lo = setpoint - deadband/2` and
`hi = setpoint + deadband/2`.

- The heating system starts **OFF**.
- At the start of each step, decide the ON/OFF state from the **current** indoor
  temperature: turn ON when the indoor temperature is below `lo`; turn OFF when it
  is above `hi`; otherwise keep the previous state (no chattering between `lo` and
  `hi`).
- While OFF, `Q_hvac = 0` and no electricity is consumed.


## Heat pump, capacity limit, and backup heat

While the heating system is ON:

- The **heat pump runs at its full rated output**, delivering `hp_capacity` watts
  of heat. Its electrical input is the thermal output divided by the COP at the
  current outdoor temperature.
- The **COP is read from `cop_curve`** by **linear interpolation** in outdoor
  temperature. `cop_curve` is a list of `[t_out, COP]` points; interpolate
  linearly between the two surrounding points, and **clamp** to the nearest
  endpoint COP for outdoor temperatures below the first or above the last point.
- **Backup resistance heat** supplies any shortfall on cold days. The building's
  conductive heating load at the setpoint is `(setpoint - t_out) / R` watts. When
  this load exceeds `hp_capacity` (i.e. the outdoor temperature is below the
  balance point), the backup makes up the deficit `load - hp_capacity`, limited to
  `backup_capacity` watts. Backup resistance heat has a COP of 1 (its electrical
  input equals its thermal output). The load is never negative for this purpose.

The net heat delivered to the zone while ON is the heat-pump output plus the
backup output, and that net heat is the `Q_hvac` used in the zone update above.


## Energy accounting

`energy_kwh` is the total **electrical** energy drawn over the horizon: at each
step sum the heat-pump electrical input and the backup electrical input (zero
while OFF), multiply by the step duration, and accumulate. Watts integrated over
seconds gives joules; report the total in **kilowatt-hours**.


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
  any third-party package for `hvac_sim.py`.
- Be careful with units: `dt` is in seconds; energy is reported in kWh and comfort
  in degree-hours.
- The function must be **pure and deterministic**: same inputs -> same outputs,
  with no global state, randomness, file, or network access.

## No cheating

The grader is held out: it is not in `/app` and you will not see it during the
task. It imports your `simulate` and checks `energy_kwh`, `comfort_degree_hours`,
and the `indoor_temp` trajectory against an **independent** reference over several
scenarios (a mild day where only the heat pump runs and cycles, a cold day that
forces backup heat, and a day with a varying outdoor-temperature profile). Do not
attempt to detect, special-case, or hard-code grader inputs or expected outputs;
solutions must implement the model as specified for arbitrary inputs.
