# Hourly Heat-Pump Energy Estimator

You are building a small Python tool that estimates a building's annual heating and
cooling **electricity** use from a year of hourly outdoor temperatures. The headline
number is annual delivered electricity in kWh, and getting it right requires two pieces
of physics that the textbook "degree-days times a constant" shortcut does **not**
capture: a *derived* balance point, and a heating COP that *varies with outdoor
temperature* and must be integrated hour by hour.

Implement everything in a single module at **`/app/degree_days.py`**. The module must
expose the functions described below, with exactly these names and signatures. Pure
Python standard library only — no third-party packages are required or installed.

## Input data: hourly temperature CSV

The tool reads a CSV file holding one year of **hourly** outdoor dry-bulb temperatures.
The file has a header row and two columns:

```
hour,temp_c
0,4.1
1,3.7
2,3.2
...
8759,5.0
```

- `hour`: integer hour index for the year (0-based, ascending). It is only a row marker.
- `temp_c`: outdoor temperature for that hour, in degrees Celsius (may be negative, may
  be fractional).

Notes on the file:
- A normal year has **8760** rows; a leap year has **8784**. Do not hardcode the count —
  process every data row that is present.
- The file may contain **malformed rows** (blank lines, rows with a missing/empty
  `temp_c`, or a non-numeric `temp_c`). Skip such rows gracefully and keep the valid
  temperatures, in file order. Do not abort on a bad row.

## Concepts and units

**Balance-point temperature** (`balance_point`, °C) — *derived, not given.* Internal
heat gains (people, lights, appliances) and solar gains warm the building, so heating is
only needed once the outdoor temperature drops far enough below the setpoint to lose
those gains through the envelope. Compute it as:

```
T_balance = T_setpoint - (Q_internal + Q_solar) / UA
```

where `T_setpoint` is in °C, `Q_internal` and `Q_solar` are steady gains in **watts**,
and `UA` is the building heat-loss coefficient in **W/K**. `(Q_internal + Q_solar) / UA`
is a temperature offset in kelvin. Heating is needed below `T_balance`; cooling above it.
Do **not** use the raw setpoint as the balance point.

**Building UA value** (`UA`, W/K): the building's overall heat-loss/heat-gain
coefficient — watts of heat flow per kelvin of indoor-outdoor temperature difference.

**Heating / cooling degree days (HDD / CDD)** measure how much, and for how long, the
outdoor temperature sits below / above a balance point. Only the shortfall below the
balance point contributes to heating, and only the excess above it to cooling; the other
side contributes zero (never negative). Your input is sampled **hourly**, so evaluate the
demand at each hour against the balance point, then express the accumulated total in
**°C·day** (24 hourly samples make one day). Do not pre-average to a coarser resolution
before thresholding.

**Temperature-dependent heating COP.** The heat pump's heating coefficient of
performance (COP) depends on the outdoor temperature: it is high in mild weather and
falls in the cold. You are given a **COP curve** — a list of `(temp_c, cop)` breakpoints
sorted by temperature. For any outdoor temperature, the COP is the **linear
interpolation** between the two surrounding breakpoints; below the coldest breakpoint or
above the warmest, clamp to the endpoint COP.

**Cooling COP** (`cooling_cop`) is a single dimensionless constant.

**Annual electricity (the headline result).** Because the heating COP varies with
temperature, heating electricity must be integrated **per hour**, not derived from a
single average COP. For each hour:

- if the outdoor temperature is **below** the balance point, the heating thermal load is
  `UA * (T_balance - T_out)` watts, and the electricity for that hour is that load
  divided by the **interpolated COP at that hour's outdoor temperature**;
- if it is **above** the balance point, the cooling thermal load is
  `UA * (T_out - T_balance)` watts, and the electricity for that hour is that load
  divided by `cooling_cop`.

Each hourly sample represents exactly one hour, so a load in watts over that hour is
energy in watt-hours directly. Sum over the year and convert W·h → kWh (÷1000). A
shortcut of the form `degree_days * UA * 24 / 1000 / COP_avg` will **not** match,
because the COP curve is convex and the heating load concentrates in the cold, low-COP
hours.

## Functions to implement

```python
def read_temps(csv_path: str) -> list[float]:
    """Parse the hourly temperature CSV at csv_path and return the temp_c values as a
    list of floats, in file (chronological) order. Malformed rows are skipped."""

def balance_point(T_setpoint: float, Q_internal: float, Q_solar: float, UA: float) -> float:
    """Return the derived balance-point temperature (°C):
    T_setpoint - (Q_internal + Q_solar) / UA."""

def heating_degree_days(temps: list[float], balance_point: float) -> float:
    """Return the heating degree days (°C·day) for the hourly series `temps` against
    `balance_point`."""

def cooling_degree_days(temps: list[float], balance_point: float) -> float:
    """Return the cooling degree days (°C·day) for the hourly series `temps` against
    `balance_point`."""

def cop_at(temp_c: float, cop_curve: list) -> float:
    """Return the heating COP at outdoor temperature `temp_c`, linearly interpolated
    from the `(temp_c, cop)` breakpoints in `cop_curve` (clamped beyond the ends)."""

def annual_energy_kwh(
    temps: list[float],
    T_setpoint: float,
    Q_internal: float,
    Q_solar: float,
    UA: float,
    heating_cop_curve: list,
    cooling_cop: float,
) -> dict:
    """Return annual delivered electricity as
    {"balance_point_c": <float>, "heating_kwh": <float>, "cooling_kwh": <float>},
    using the derived balance point, a per-hour heating integral with the interpolated
    COP, and a constant cooling COP, as described above."""
```

## Requirements

1. **Language**: Python 3 (standard library only).
2. **Module location**: `/app/degree_days.py`, importable as `import degree_days`.
3. **Function names and signatures**: exactly as listed above. `annual_energy_kwh` must
   return a dict with the keys `"balance_point_c"`, `"heating_kwh"`, and `"cooling_kwh"`.
4. **Units**: temperatures in °C; `Q_internal`, `Q_solar` in W; `UA` in W/K; degree days
   in °C·day; all returned energies in kWh. Reconcile the hour/day and W/kW conversions.
5. **Balance point is derived** from setpoint and gains — never the raw setpoint.
6. **Heating COP is interpolated per hour** and the heating electricity is the per-hour
   integral of load/COP — not degree days divided by a single average COP.
7. **Sign convention**: heating only accrues below the balance point, cooling only above;
   neither side is ever negative. An all-heating climate has zero cooling; an
   all-cooling climate has zero heating.
8. **Robust input**: handle 8760- and 8784-row files; skip malformed rows.
9. **Determinism**: the functions are pure — same inputs, same outputs. No randomness, no
   wall-clock or network dependence.
