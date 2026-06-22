# VAV Air-Handler Simulation (Economizer + SAT Reset + Min-Airflow Reheat + CO2 DCV)

You will implement a Python simulation of **one day** of a multi-zone **variable-air-volume (VAV)** air handler. A single air-handling unit (AHU) draws a mix of return air and outdoor air across a cooling coil, supplies the cooled air to several VAV boxes (one per zone), and each box throttles its airflow — and reheats when necessary — to hold its zone. The day's energy and ventilation outcome depends on **four interacting controls**:

1. an **airside economizer** that uses outdoor air for free cooling when the outdoor air is suitable,
2. a **supply-air-temperature (SAT) reset** that moves the coil-leaving setpoint against outdoor temperature,
3. **VAV-box reheat with a minimum-airflow floor** (a box throttled to its minimum must reheat to avoid overcooling), and
4. **CO2 demand-controlled ventilation (DCV)** that raises the minimum outdoor-air requirement with occupancy.

These controls are coupled: the economizer and DCV both set the outdoor-air fraction (which sets the mixed-air temperature and therefore the coil load); the SAT reset changes every box's airflow (and therefore fan power and reheat); and the minimum-airflow floor forces reheat even while the coil is cooling. Your simulator must report the fan, cooling-coil, and reheat **electrical** energy, the total, the **peak zone CO2** (ventilation adequacy), and the supply-airflow trajectory.

This is a numerical-modeling task: the grader imports your module and checks the returned numbers against an independent reference, so the quantities below must be computed exactly as specified.


## Deliverable

Create a single file **`/app/vav_sim.py`** that defines a function with this exact signature (the grader calls it by keyword argument):

```python
def simulate(
    t_out,              # outdoor dry-bulb temperature [degC]: float (constant) OR list of length n_steps
    dt,                 # time-step size [s], float
    n_steps,            # number of integration steps, int
    n_zones,            # number of VAV zones/boxes, int
    zone_loads,         # list of length n_zones; each entry is the zone sensible COOLING load [W]:
                        #   a float (constant) OR a list of length n_steps. Loads are >= 0.
    zone_occupancy,     # list of length n_zones; each entry is the zone occupancy [people]:
                        #   a float (constant) OR a list of length n_steps.
    zone_setpoint,      # zone air temperature [degC], float (also the return-air temperature)
    zone_volume,        # zone air volume [m^3], float (same for every zone)
    cp_air,             # specific heat of air [J/(kg*K)], float
    rho_air,            # air density [kg/m^3], float
    m_box_min,          # VAV-box MINIMUM airflow [kg/s], float (the minimum-airflow floor)
    m_box_max,          # VAV-box MAXIMUM airflow [kg/s], float
    m_total_design,     # AHU design supply airflow [kg/s], float (fan affinity reference)
    fan_power_design,   # fan electrical power at design airflow [W], float
    chiller_cop,        # cooling-coil electrical COP (thermal/electrical), float
    sat_min,            # minimum supply-air-temperature setpoint [degC], float
    sat_max,            # maximum supply-air-temperature setpoint [degC], float
    sat_reset_oat_lo,   # outdoor temp at/below which SAT = sat_max [degC], float
    sat_reset_oat_hi,   # outdoor temp at/above which SAT = sat_min [degC], float
    econ_high_limit,    # economizer dry-bulb changeover high-limit [degC], float
    oa_min_base,        # per-zone base (area) ventilation airflow [kg/s], float
    oa_per_person,      # per-person DCV ventilation airflow [kg/s/person], float
    co2_outdoor,        # outdoor CO2 concentration [ppm], float
    co2_gen_per_person, # CO2 generation per person [m^3/s], float
    co2_limit,          # CO2 adequacy limit [ppm], float
    co2_initial,        # initial zone CO2 concentration [ppm], float
) -> dict:
    ...
```

The returned `dict` MUST contain exactly these keys:

| key | type | meaning |
|-----|------|---------|
| `fan_energy_kwh` | `float` | total fan electrical energy over the horizon, kWh |
| `cooling_coil_energy_kwh` | `float` | total cooling-coil electrical energy over the horizon, kWh |
| `reheat_energy_kwh` | `float` | total VAV-box reheat electrical energy over the horizon, kWh |
| `total_energy_kwh` | `float` | `fan_energy_kwh + cooling_coil_energy_kwh + reheat_energy_kwh` |
| `co2_ppm_max` | `float` | maximum zone CO2 over all zones and all steps (including the initial value), ppm |
| `co2_within_limit` | `bool` | `True` iff `co2_ppm_max <= co2_limit` |
| `supply_airflow_kgps` | `list[float]` | total AHU supply airflow per step, length `n_steps` |

For step index `n` (0-based), use `t_out`, `zone_loads[z]`, and `zone_occupancy[z]` at index `n` when those arguments are lists; if an argument is a scalar it applies to every step. `supply_airflow_kgps[n]` is the total supply airflow during step `n`.


## Per-step structure

All zones are held at `zone_setpoint`; return air is at `zone_setpoint`. Each step is quasi-steady for the airside (compute the controls and energies for the step), with the only dynamic state being the zone CO2 concentration. Evaluate the controls in this order each step: **SAT reset -> box airflow & reheat -> DCV minimum OA -> economizer outdoor-air fraction -> mixed air & coil load -> fan power -> CO2 update.**


## 1. Supply-air-temperature (SAT) reset

The coil-leaving (supply) setpoint resets **linearly** against the outdoor dry-bulb between the two reset endpoints, and is held flat outside them:

- at `t_out <= sat_reset_oat_lo` the supply setpoint is `sat_max` (warmest supply, least cooling),
- at `t_out >= sat_reset_oat_hi` the supply setpoint is `sat_min` (coldest supply, most cooling),
- in between it interpolates linearly.

Call the resulting setpoint `SAT`. The cooling coil controls the supply (coil-leaving) air temperature to `SAT`, and all VAV boxes therefore receive supply air at `SAT`. `sat_reset_oat_hi > sat_reset_oat_lo` and `sat_min < sat_max < zone_setpoint`.


## 2. VAV-box airflow and minimum-airflow reheat

Each box delivers supply air at `SAT` and modulates its airflow to remove its sensible cooling load while holding the zone at `zone_setpoint`. The airflow that exactly meets the load is the one for which the supply air, warmed from `SAT` to `zone_setpoint`, absorbs the load. This **required airflow** is clamped between `m_box_min` and `m_box_max`:

- If the required airflow is **at or below `m_box_min`**, the box runs at `m_box_min`. At that floor the minimum airflow would *overcool* the zone, so the box **reheats**: it adds exactly enough heat to the (minimum) airstream so the net cooling delivered to the zone equals the zone load. This is the simultaneous-cooling-and-reheat regime (the coil may still be cooling the central air to `SAT` while the box reheats).
- If the required airflow is **at or above `m_box_max`**, the box runs at `m_box_max` and does **not** reheat (the zone may be undercooled; that is acceptable).
- Otherwise the box runs at exactly the required airflow with no reheat.

The total AHU supply airflow for the step is the sum of the box airflows. Reheat energy is **electric-resistance** (COP = 1: electrical input equals reheat thermal output).


## 3. CO2 demand-controlled ventilation (DCV): minimum outdoor air

Ventilation is driven by occupancy. Each zone requires a minimum outdoor-air mass flow equal to a base (area) component plus a per-person (DCV) component:

```
per-zone minimum OA = oa_min_base + oa_per_person * (zone occupancy)
```

The AHU minimum outdoor-air requirement is the sum over zones. The **minimum outdoor-air fraction** is that total minimum OA divided by the total supply airflow (capped at 1.0). As occupancy rises, DCV raises this minimum fraction; this floor interacts with the economizer (below) and changes the mixed-air temperature and coil load.


## 4. Airside economizer (free cooling) and outdoor-air fraction

The economizer decides the actual outdoor-air fraction, never below the DCV minimum fraction from step 3:

- **Economizer enabled** when `t_out < econ_high_limit` (outdoor air is cool enough to help). The economizer modulates outdoor air to drive the **mixed-air temperature toward `SAT`** (free cooling, reducing or eliminating mechanical cooling):
  - if outdoor air is cold enough that some outdoor-air fraction makes the mixed-air temperature exactly equal `SAT`, use that fraction;
  - if even 100% outdoor air cannot cool the mix down to `SAT`, use 100% outdoor air.
- **Economizer disabled** when `t_out >= econ_high_limit`: use the DCV minimum outdoor-air fraction only.

In all cases the final outdoor-air fraction is **at least the DCV minimum fraction** and at most 1.0. (Mixed-air temperature is the airflow-weighted blend of outdoor air at `t_out` and return air at `zone_setpoint`.)


## 5. Mixed air and cooling-coil load

With the outdoor-air fraction chosen, the mixed-air temperature is the fraction-weighted blend of outdoor air (`t_out`) and return air (`zone_setpoint`). The cooling coil cools the **total** supply airflow from the mixed-air temperature down to `SAT`; the coil thermal load is the sensible heat removed, and is **never negative** (if the mixed air is already at or below `SAT`, the coil does nothing — full free cooling). The coil **electrical** energy is the coil thermal load divided by `chiller_cop`.


## 6. Fan power

The supply fan follows the affinity (cube) law against the design airflow:

```
fan power = fan_power_design * (total supply airflow / m_total_design)^3
```

Because the SAT reset and the minimum-airflow floor both change the total airflow, fan power is strongly coupled to the other controls.


## 7. Zone CO2 dynamics (ventilation adequacy)

Each zone is a well-mixed CO2 control volume. With outdoor air delivered to the zone at the chosen outdoor-air fraction, the zone CO2 concentration `C` [ppm] evolves as

```
zone_volume * dC/dt = 1e6 * co2_gen_per_person * (zone occupancy) - q_oa_zone * (C - co2_outdoor)
```

where `q_oa_zone` is the **volumetric** outdoor-air flow delivered to that zone [m^3/s] — i.e. the zone's outdoor-air mass flow (outdoor-air fraction times the zone's supply mass flow) divided by `rho_air`. The factor `1e6` converts the volumetric CO2 generation to ppm.

**Integration requirement (pinned for determinism).** Over each step the inputs are held constant, so this ODE is linear and has a closed form. You MUST advance the CO2 state with the exact analytic update (not forward Euler). When `q_oa_zone > 0`:

```
C_eq  = co2_outdoor + (1e6 * co2_gen_per_person * occupancy) / q_oa_zone
tau   = zone_volume / q_oa_zone
C(t + dt) = C_eq + (C(t) - C_eq) * exp(-dt / tau)
```

When `q_oa_zone` is zero, CO2 simply accumulates: `C(t + dt) = C(t) + (1e6 * co2_gen_per_person * occupancy) * dt / zone_volume`.

All zones start at `co2_initial`. `co2_ppm_max` is the maximum concentration over every zone and every step, including the initial value; `co2_within_limit` is `True` iff that maximum is at or below `co2_limit`.


## Energy accounting

For each control (fan, cooling coil, reheat) integrate electrical power over the step (watts times seconds gives joules) and accumulate over the horizon; report each total in **kilowatt-hours** (divide joules by 3.6e6). The cooling coil's electrical power is its thermal load divided by `chiller_cop`; reheat electrical power equals its thermal output (COP = 1); fan electrical power is the affinity-law power above. `total_energy_kwh` is the sum of the three.


## Constraints and notes

- Pure standard-library Python is sufficient; you may use `math`. Do **not** require any third-party package for `vav_sim.py`. In particular, do **not** use `scipy` or any black-box ODE integrator — the analytic CO2 update above is mandatory.
- Be careful with units: `dt` is in seconds; airflows are mass flows in kg/s except the CO2 balance, which needs the **volumetric** outdoor-air flow (kg/s divided by `rho_air`); energies are reported in kWh; CO2 is in ppm.
- The function must be **pure and deterministic**: same inputs -> same outputs, with no global state, randomness, file, or network access.


## No cheating

The grader is held out: it is not in `/app` and you will not see it during the task. It imports your `simulate` and checks the energies, `co2_ppm_max`, and the `supply_airflow_kgps` trajectory against an **independent** reference over several scenarios (a mild shoulder day that runs the economizer, DCV, and min-airflow reheat together; a hot day with the economizer locked out and simultaneous mechanical cooling plus reheat; a cold, densely occupied day where DCV raises the outdoor-air fraction above the economizer's free-cooling target; and a day with varying outdoor temperature, occupancy, and load profiles). Do not attempt to detect, special-case, or hard-code grader inputs or expected outputs; solutions must implement the model as specified for arbitrary inputs.
