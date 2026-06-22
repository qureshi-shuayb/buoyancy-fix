# Degree-Day Energy Estimator

You are building a small Python tool that estimates a building's annual heating and
cooling energy use from a year of hourly outdoor temperatures, using the classic
**degree-day** method.

Implement everything in a single module at **`/app/degree_days.py`**. The module must
expose the four functions described below, with exactly these names and signatures.
Pure Python standard library only — no third-party packages are required or installed.

## Input data: hourly temperature CSV

The tool reads a CSV file holding one year of **hourly** outdoor dry-bulb temperatures
(about 8760 rows). The file has a header row and two columns:

```
hour,temp_c
0,4.1
1,3.7
2,3.2
...
8759,5.0
```

- `hour`: integer hour index for the year (0-based, ascending). You do not need it for
  the calculation other than as a row marker.
- `temp_c`: outdoor temperature for that hour, in degrees Celsius (may be negative,
  may be fractional).

Rows are already in chronological order. Treat every row as exactly one hour of data.

## Concepts and units

**Balance-point temperature** (`balance_point`, °C): the outdoor temperature below which
the building needs heating and above which it needs cooling. It is configurable per
call, not a fixed constant.

**Heating degree days (HDD)** measure how much, and for how long, the outdoor
temperature sits *below* the balance point. **Cooling degree days (CDD)** measure how
much, and for how long, it sits *above* the balance point. For any moment, only the
shortfall below the balance point contributes to heating, and only the excess above it
contributes to cooling; the other side contributes zero (never a negative amount).

Degree days are reported in **°C·day** (degree-Celsius-days). Your input is sampled
**hourly**, so you must evaluate the heating/cooling demand from the hourly series and
then express the accumulated total in *days*, not hours: 24 hourly samples make up one
day. Evaluate the demand against the balance point at the hourly resolution of the data
— do not pre-average the data to a coarser resolution before thresholding.

**Building UA value** (`UA`, W/K): the building's overall heat-loss/heat-gain
coefficient — watts of heat flow per kelvin of indoor-outdoor temperature difference.

**Thermal energy from degree days.** The thermal energy the building must add (heating)
or remove (cooling) over the year is the UA value multiplied by the accumulated degree
days, with the time units reconciled: `UA` is in W/K (i.e. per second), while degree
days carry a *day* time unit. Convert consistently so the result is energy. Express the
thermal energy in **kWh** (1 kWh = 1000 W·h, and 1 day = 24 h).

**Equipment efficiency → delivered energy.** The thermal energy above is the heat
delivered to or removed from the building. The *delivered energy the equipment consumes*
is the thermal energy divided by the equipment's efficiency:

- Heating efficiency `heating_eff` is a dimensionless ratio (an AFUE such as 0.95, or a
  heat-pump COP such as 3.2): delivered heating energy = heating thermal energy /
  `heating_eff`.
- Cooling COP `cooling_cop` is a dimensionless ratio (e.g. 3.5): delivered cooling
  energy = cooling thermal energy / `cooling_cop`.

All delivered energies are in **kWh**.

## Functions to implement

```python
def read_temps(csv_path: str) -> list[float]:
    """Parse the hourly temperature CSV at csv_path and return the temp_c values
    as a list of floats, in file (chronological) order."""

def heating_degree_days(temps: list[float], balance_point: float) -> float:
    """Return the heating degree days (°C·day) for the hourly temperature series
    `temps` against `balance_point`."""

def cooling_degree_days(temps: list[float], balance_point: float) -> float:
    """Return the cooling degree days (°C·day) for the hourly temperature series
    `temps` against `balance_point`."""

def annual_energy_kwh(
    temps: list[float],
    balance_point: float,
    UA: float,
    heating_eff: float,
    cooling_cop: float,
) -> dict:
    """Return annual delivered energy as
    {"heating_kwh": <float>, "cooling_kwh": <float>}
    using the degree-day method, the building UA value, and the equipment
    efficiencies described above."""
```

## Requirements

1. **Language**: Python 3 (standard library only).
2. **Module location**: `/app/degree_days.py`, importable as `import degree_days`.
3. **Function names and signatures**: exactly as listed above. `annual_energy_kwh` must
   return a dict with the keys `"heating_kwh"` and `"cooling_kwh"`.
4. **Units**: temperatures in °C, `UA` in W/K, degree days in °C·day, all returned
   energies in kWh. Be careful to reconcile the hour/day and W/kW unit conversions.
5. **Sign convention**: heating only accrues when the outdoor temperature is below the
   balance point; cooling only when it is above. Neither degree-day total is ever
   negative. A climate entirely above the balance point has zero HDD; one entirely below
   has zero CDD.
6. **Determinism**: the functions are pure — same inputs, same outputs. No randomness, no
   wall-clock or network dependence.
