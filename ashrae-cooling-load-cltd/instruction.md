# Building Peak Cooling Load (ASHRAE CLTD/SCL/CLF Method)

Implement a single, dependency-free Python module that computes a building's
**peak design cooling load** using the ASHRAE **CLTD/SCL/CLF** method.

This is *not* a simple "add up the instantaneous heat gains" exercise. The whole
point of the CLTD/SCL/CLF procedure is that the **cooling load** a building
imposes on its equipment at a given hour is **not** the same as the instantaneous
heat *gain* at that hour: the building's mass stores and re-releases energy, so
gains are delayed and smeared in time, and tabulated gains must be **corrected**
to the actual design conditions before they become load. Your implementation must
reflect that.

## Where to put your code

Create a single module at exactly:

```
/app/cooling_load.py
```

It must expose this **module-level** function:

```python
def peak_cooling_load(building, design):
    """Return the building's peak design cooling load.

    Returns a dict with exactly these keys:
      {
        "peak_hour":  int,    # solar hour (1..24) at which the TOTAL load is greatest
        "sensible_w": float,  # sensible cooling load at peak_hour, in watts
        "latent_w":   float,  # latent cooling load at peak_hour, in watts
        "total_w":    float,  # total (sensible + latent) load at peak_hour, in watts
      }
    """
```

`peak_hour` is the hour at which the **total** load is maximized over the design
hours; the sensible/latent/total values returned are the loads **at that hour**.

## Units and conventions

- Temperatures are in **degrees Celsius (°C)**.
- Areas in **m²**, U-values in **W/(m²·K)**.
- Loads are in **watts (W)**.
- Ventilation airflow is in **litres per second (L/s)**.
- Humidity ratios are in **kg water / kg dry air**.
- Hours are **solar hours 1..24** (hour `h` indexes position `h-1` of every
  24-element table).
- All ASHRAE design tables are referenced to the **standard ASHRAE base design
  conditions** that underlie the CLTD tables; tabulated CLTD values must be
  corrected to the *actual* indoor and outdoor design conditions of this job
  before use.

## Input: `building`

```python
building = {
    "opaque_surfaces": [        # exterior walls and roof
        {
            "type": str,        # key into design["tables"]["cltd_opaque"]
            "orientation": str, # "N"|"E"|"S"|"W"|"HOR"; key into LM table
            "area_m2": float,
            "u_value": float,   # W/(m^2*K)
            "color": str,       # "dark"|"medium"|"light"; key into K table
        },
        ...
    ],
    "windows": [
        {
            "orientation": str, # "N"|"E"|"S"|"W"|"HOR"; key into SCL table
            "area_m2": float,
            "u_value": float,   # W/(m^2*K)
            "sc": float,        # shading coefficient (dimensionless)
        },
        ...
    ],
    "lights_w": float,          # installed lighting heat gain (W)
    "equipment_w": float,       # installed equipment heat gain (W)
    "people": {
        "count": int,
        "sensible_w_each": float,
        "latent_w_each": float,
    },
}
```

## Input: `design`

```python
design = {
    "t_room": float,            # indoor design dry-bulb (°C)
    "outdoor_max": float,       # peak outdoor dry-bulb (°C)
    "daily_range": float,       # outdoor daily temperature range (°C)
    "t_outdoor_mean": float,    # mean outdoor dry-bulb for the design day (°C)
    "lm_key": str,              # key into design["tables"]["lm"]
    "hours": list[int],         # solar hours to evaluate (e.g. 1..24)
    "ventilation_Ls": float,    # outdoor air / infiltration flow (L/s)
    "w_outdoor": float,         # outdoor humidity ratio (kg/kg)
    "w_room": float,            # indoor humidity ratio (kg/kg)
    "tables": { ... },          # ASHRAE design tables, described below
}
```

## Input data: `design["tables"]`

All the ASHRAE design data you need is provided to you at call time. You do **not**
need to memorize or reproduce any handbook table — read the values from here.

```python
design["tables"] = {
    # Opaque CLTD by surface type, one value per solar hour (°C), length 24.
    "cltd_opaque": { surface_type: [c1, ..., c24], ... },

    # Glass conduction CLTD, one value per solar hour (°C), length 24.
    "cltd_glass": [g1, ..., g24],

    # Solar Cooling Load by orientation, W/m^2, one value per hour, length 24.
    "scl": { orientation: [s1, ..., s24], ... },

    # Cooling Load Factors (dimensionless), one value per hour, length 24,
    # for each internal-gain category.
    "clf": {
        "lights":    [f1, ..., f24],
        "people":    [f1, ..., f24],
        "equipment": [f1, ..., f24],
    },

    # Latitude-month correction LM (°C) by orientation, for each lm_key.
    "lm": { lm_key: { orientation: value, ... }, ... },

    # Surface-color / absorptance factor K (dimensionless).
    "k_color": { "dark": ..., "medium": ..., "light": ... },

    # Fraction of the daily range below the peak outdoor temperature, per hour
    # (length 24): the outdoor dry-bulb at hour h is
    #   outdoor_max - daily_range * outdoor_temp_fraction[h-1].
    "outdoor_temp_fraction": [r1, ..., r24],
}
```

## What you must compute (requirements, per hour)

For **each** solar hour in `design["hours"]`, build up the cooling load from these
contributions, then take the **peak of the total over the day**.

1. **Opaque surfaces (walls & roof).** The cooling load through each opaque
   surface is `q = U * A * CLTD_corrected`, where `CLTD_corrected` is that
   surface's tabulated hourly CLTD **after** applying the standard ASHRAE
   corrections for: the latitude-month (LM) value for the surface's orientation,
   the surface-color factor K, and the difference between this job's actual indoor
   and outdoor design temperatures and the CLTD tables' base design conditions.
   Using the raw tabulated CLTD (or, worse, a plain `U*A*ΔT`) is incorrect.

2. **Glass conduction.** `q = U * A * CLTD_glass_corrected`, where the glass CLTD
   is corrected to the actual indoor/outdoor design conditions (glass carries no
   LM or color correction).

3. **Glass solar.** `q = A * SC * SCL[orientation][hour]` — the solar cooling load
   already accounts for transmission and thermal lag; scale it by the glazing area
   and shading coefficient.

4. **Internal gains (lights, people, equipment).** These do **not** appear as
   cooling load the instant they are emitted; mass delays them. Convert each
   internal *sensible* gain to a cooling load using the appropriate
   **cooling-load factor (CLF)** for the hour — i.e. multiply the installed gain
   by `CLF[category][hour]` rather than using the full instantaneous gain.
   - Lights:    `lights_w * CLF["lights"][hour]`
   - Equipment: `equipment_w * CLF["equipment"][hour]`
   - People (sensible): `count * sensible_w_each * CLF["people"][hour]`
   - People (**latent**): `count * latent_w_each` — **latent gains convert to load
     immediately and are not subject to CLF.**

5. **Ventilation / infiltration.** With airflow `Q` in L/s:
   - Sensible: `q = 1.23 * Q * (T_outdoor(hour) - t_room)`, where
     `T_outdoor(hour) = outdoor_max - daily_range * outdoor_temp_fraction[hour-1]`.
   - Latent:   `q = 3010 * Q * (w_outdoor - w_room)` (constant over the day).

6. **Sensible vs latent.**
   - **Sensible load** = opaque + glass conduction + glass solar + lights +
     equipment + people sensible + ventilation sensible.
   - **Latent load** = people latent + ventilation latent.
   - **Total** = sensible + latent.

7. **Peak.** Evaluate every hour in `design["hours"]` and return the hour at which
   the **total** load is greatest, together with the sensible, latent, and total
   loads at that hour. (Some contributions can be negative at some hours — e.g. a
   surface losing heat in the early morning — that is expected; do not clamp them.)

## Constraints

- **Pure standard library only.** You may use Python's `math` module. Do not pull
  in any HVAC / building-energy library.
- Do **not** hardcode answers. Your function is evaluated on several buildings and
  design conditions you cannot see in advance, including a randomized one.
- Read every table from `design["tables"]`; do not assume specific numeric values.

## How you are graded

Your function is called on several building/design scenarios that share the same
design tables, plus one randomized scenario generated at grading time. For each
scenario, `peak_hour`, `sensible_w`, `latent_w`, and `total_w` are compared
against an independent ASHRAE-method reference.

| Quantity   | Tolerance                          |
|------------|------------------------------------|
| peak_hour  | exact match                        |
| sensible_w | 1.0 W (and 1e-6 relative)          |
| latent_w   | 1.0 W (and 1e-6 relative)          |
| total_w    | 1.0 W (and 1e-6 relative)          |

All scenarios must pass.
