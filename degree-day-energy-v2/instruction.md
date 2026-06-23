# Annual Building Energy Estimator

Implement a pure-Python tool that estimates a building's annual heating and cooling electricity use in kWh from hourly outdoor temperatures.

## Output location

Create exactly `/app/degree_days.py` exposing exactly these functions:

```python
def read_temps(csv_path: str) -> list[float]: ...
def interp(x: float, curve: list) -> float: ...
def balance_points(heat_sp: float, cool_sp: float, gain_w: float, UA: float) -> tuple: ...
def annual_energy(temps: list, config: dict) -> dict: ...
```

## Input

Hourly temperature CSV with header hour,temp_c. Normal year 8760 rows leap year 8784 rows. Skip malformed rows gracefully. Hour of day derives from position modulo 24.

Configuration dict contains UA, occupied_hours [start,end], occupied and unoccupied dicts each with heat_sp cool_sp gain_w, heating_cop_curve and cooling_cop_curve as lists of [temp_c,COP] points, backup_lockout_c, economizer_changeover_c, bin_width_c.

## Output

annual_energy returns dict with heating_kwh, cooling_kwh, total_kwh as floats. Use bin method grouping temperatures into bins per occupancy state evaluating at bin center. Account for schedule-dependent balance points derived from setpoints and gains, equipment COP curves with backup lockout, economizer free cooling, part-load degradation, capacity limits, unit conversions. Handle 8760 and 8784 lengths.

## Constraints

Python 3 standard library only. Module at /app/degree_days.py importable. Function names signatures exactly as listed. Deterministic pure functions no randomness network.

## Grading

Outputs compared against independent reference across multiple synthetic climates and parameter variations. Tight tolerance required. All test groups must pass.
