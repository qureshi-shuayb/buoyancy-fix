# Annual Building Energy Estimator (Bin Method, Setback Schedule, Part-Load Equipment, Economizer)

You are building a pure-Python tool that estimates a building's **annual heating and
cooling electricity use (kWh)** from a year of hourly outdoor temperatures. Unlike a
single "degree-days times a constant" accumulation, the answer here depends on **four
features that interact**, and getting any one of the couplings wrong drifts the result
past a tight **0.5%** tolerance:

1. **Bin method.** Energy is accumulated over **temperature bins**, not as one running
   sum over raw hours.
2. **Time-varying setback schedule.** Occupied and unoccupied hours use different
   setpoints and internal gains, so the heating/cooling **balance points change by
   hour-of-day**.
3. **Part-load / temperature-dependent equipment.** A heating heat pump with a
   COP-versus-outdoor-temperature curve plus electric-resistance backup below a lockout
   temperature, and an air conditioner with its own temperature-dependent cooling COP.
4. **Economizer (free cooling).** When a cooling hour is cool enough outside, the load is
   met with outdoor air and the compressor draws no electricity.

These features couple: the setback shifts which hours need heating versus cooling versus
free cooling; the backup engages only below the lockout temperature; the economizer is
available only for the (schedule-dependent) cooling hours that are below the changeover
temperature; and equipment efficiency varies across bins. A model that implements any
single feature but misses an interaction will not match.

Implement everything in a single module at **`/app/degree_days.py`**, using the Python
**standard library only** (no third-party packages). Expose exactly the functions and
signatures listed below.

## Input data: hourly temperature CSV

The tool reads a CSV holding one year of **hourly** outdoor dry-bulb temperatures, with a
header row and two columns:

```
hour,temp_c
0,4.1
1,3.7
2,3.2
...
8759,5.0
```

- `hour`: 0-based ascending integer hour index for the year. It is only a row marker, but
  its position determines the **hour-of-day** as `hour % 24` (row 0 is hour-of-day 0).
- `temp_c`: outdoor temperature for that hour in °C (may be negative or fractional).

Notes:
- A normal year has **8760** rows; a leap year has **8784**. Do not hardcode the count —
  process every valid data row present, in file order.
- The file may contain **malformed rows** (blank lines, missing/empty `temp_c`, or a
  non-numeric `temp_c`). Skip them gracefully, keeping the valid temperatures in order.
  The surviving row position still defines hour-of-day (i.e. hour-of-day comes from the
  index within the returned list of valid temperatures, `i % 24`).

## Configuration

All building, schedule, and equipment parameters are passed as a single `config` dict
with exactly these keys:

```python
config = {
    "UA": float,                     # building heat-loss coefficient, W/K
    "occupied_hours": [start, end],  # ints; an hour is OCCUPIED when start <= (hour_of_day) < end
    "occupied":   {"heat_sp": float, "cool_sp": float, "gain_w": float},
    "unoccupied": {"heat_sp": float, "cool_sp": float, "gain_w": float},
    "heating_cop_curve": [[t_c, cop], ...],   # rated heating COP vs outdoor temp
    "cooling_cop_curve": [[t_c, cop], ...],   # rated cooling COP vs outdoor temp
    "backup_lockout_c": float,       # below this outdoor temp the heat pump is locked out
    "economizer_changeover_c": float,# cooling hours below this outdoor temp use free cooling
    "bin_width_c": float,            # temperature bin width, °C
}
```

`heat_sp`, `cool_sp`, `gain_w` are the heating setpoint (°C), cooling setpoint (°C), and
combined internal+solar heat gains (W) for that occupancy state. `gain_w` is lower when
unoccupied; the unoccupied heating setpoint is set **back** (lower) and the unoccupied
cooling setpoint is set **up** (higher).

## Concepts and units

**Balance points (derived, per occupancy state).** Internal and solar gains warm the
building, so the temperature at which heating or cooling is actually needed is offset from
the setpoint. For a given occupancy state with setpoints `heat_sp`/`cool_sp` and gains
`gain_w`:

```
T_balance_heat = heat_sp - gain_w / UA
T_balance_cool = cool_sp - gain_w / UA
```

`gain_w / UA` is a temperature offset in kelvin. Heating is needed only when the outdoor
temperature is **below** `T_balance_heat`; cooling only when it is **above**
`T_balance_cool`; between the two the building floats and uses no energy. Because the
occupied and unoccupied states have different setpoints and gains, **the two balance
points differ by hour-of-day** — you must use the balance points for the occupancy state
that is active in each hour. Do **not** use the raw setpoints, and do **not** use a single
fixed balance point for the whole year.

**Bin method.** Rather than accumulating over each raw hour, group the hours into
temperature bins of width `bin_width_c`. Use bin index `floor(temp_c / bin_width_c)`, and
let each bin's **representative temperature** be the bin center
`(bin_index + 0.5) * bin_width_c`. Bins must be kept **separately per occupancy state**
(an occupied hour and an unoccupied hour at the same temperature belong to different
cells), because the balance points and gains differ. Evaluate each cell's loads and
equipment efficiency at the bin's representative temperature, weighted by the number of
hours in that cell.

**Heating thermal load.** For a heating bin (representative temperature below the active
`T_balance_heat`), the thermal load is `UA * (T_balance_heat - T_rep)` watts.

**Cooling thermal load.** For a cooling bin (representative temperature above the active
`T_balance_cool`), the thermal load is `UA * (T_rep - T_balance_cool)` watts.

**Heating equipment.** The heat pump's heating COP comes from `heating_cop_curve`, a list
of `[temp_c, cop]` breakpoints sorted by temperature, via **linear interpolation** at the
representative temperature (clamped to the endpoint COP below the coldest or above the
warmest breakpoint). However, **below `backup_lockout_c` the heat pump is locked out** and
heating is delivered by electric-resistance backup with a COP of exactly **1.0**. The
heating electricity for a bin is its thermal load divided by the applicable efficiency.

**Cooling equipment.** The air conditioner's cooling COP comes from `cooling_cop_curve`
(same interpolation/clamping rules) at the representative temperature. The compressor
cooling electricity for a bin is its thermal load divided by that COP — **except** when
the economizer applies.

**Economizer (free cooling).** For a cooling bin whose representative temperature is
**below `economizer_changeover_c`**, the cooling load is met with outdoor air and the
**compressor draws no electricity** — that bin contributes **zero** to cooling
electricity. Cooling bins at or above the changeover temperature run the compressor
normally. (Whether a cooling bin can use the economizer therefore depends on the active
cooling balance point, which depends on the schedule.)

**Units / accounting.** Each hourly sample represents exactly one hour, so a load in watts
over that hour is energy in watt-hours directly. Sum the per-bin contributions (weighted
by hours in the bin) and convert W·h → kWh (÷1000). Heating and cooling are reported
separately; neither is ever negative.

## Functions to implement

```python
def read_temps(csv_path: str) -> list[float]:
    """Parse the hourly temperature CSV at csv_path and return the temp_c values as a
    list of floats, in file (chronological) order. Malformed rows are skipped."""

def interp(x: float, curve: list) -> float:
    """Linear interpolation of a [[x, y], ...] curve (sorted by x) at x, clamped to the
    endpoint y-value below the first or above the last breakpoint."""

def balance_points(heat_sp: float, cool_sp: float, gain_w: float, UA: float) -> tuple:
    """Return (T_balance_heat, T_balance_cool) for one occupancy state:
    (heat_sp - gain_w/UA, cool_sp - gain_w/UA)."""

def annual_energy(temps: list, config: dict) -> dict:
    """Return annual delivered electricity as
    {"heating_kwh": <float>, "cooling_kwh": <float>, "total_kwh": <float>},
    using the bin method with the schedule-dependent balance points, the heat-pump COP
    curve with resistance backup below the lockout, the cooling COP curve, and the
    economizer free-cooling exclusion, as described above. total_kwh is the sum of the
    heating and cooling electricity."""
```

## Requirements

1. **Language**: Python 3, standard library only.
2. **Module location**: `/app/degree_days.py`, importable as `import degree_days`.
3. **Function names and signatures**: exactly as listed above. `annual_energy` must return
   a dict with keys `"heating_kwh"`, `"cooling_kwh"`, and `"total_kwh"`.
4. **Bin method**: accumulate over temperature bins (per occupancy state), evaluating
   loads and efficiencies at the bin center — not a single running sum over raw hours.
5. **Schedule-dependent balance points**: use the occupied or unoccupied balance points
   according to each hour's hour-of-day; never a single fixed balance point.
6. **Equipment**: interpolate the heating and cooling COP curves per bin; apply
   resistance backup (COP 1.0) below the lockout temperature.
7. **Economizer**: cooling bins below the changeover temperature contribute zero
   compressor cooling electricity.
8. **Units**: temperatures in °C; gains in W; `UA` in W/K; all returned energies in kWh.
   Reconcile the hour→energy and W→kW conversions.
9. **Robust input**: handle 8760- and 8784-row files; skip malformed rows; hour-of-day
   derives from position within the valid temperatures.
10. **Determinism**: pure functions — same inputs, same outputs; no randomness, wall-clock,
    or network use.
