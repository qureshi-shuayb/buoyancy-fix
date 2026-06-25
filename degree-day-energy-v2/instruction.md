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

Hourly temperature CSV with header hour,temp_c. Normal year 8760 rows leap year 8784 rows. Skip malformed rows gracefully. Hour of day derives from position modulo 24 (index % 24).

Configuration dict contains UA, occupied_hours [start,end], occupied and unoccupied dicts each with heat_sp cool_sp gain_w, heating_cop_curve and cooling_cop_curve as lists of [temp_c,COP] points, backup_lockout_c, economizer_changeover_c, bin_width_c.

Occupied state is true when occupied_hours[0] <= hour_of_day < occupied_hours[1]; otherwise unoccupied.

## Output

annual_energy returns dict with heating_kwh, cooling_kwh, total_kwh as floats.

Use temperature-bin method: group hours into width-bin_width_c bins per occupancy state, evaluate each bin at its center temperature t_rep = (floor(t / bin_width_c) + 0.5) * bin_width_c.

Per occupancy state derive balance points as:
  heat_balance = heat_sp - gain_w / UA
  cool_balance = cool_sp - gain_w / UA
`balance_points` must return (heat_balance, cool_balance).

For each bin count n hours at representative temperature t_rep:
- If t_rep < heat_balance: heating load W = UA * (heat_balance - t_rep). If t_rep < backup_lockout_c use COP = 1.0 (electric resistance backup), else COP = interp(t_rep, heating_cop_curve). Heating electricity Wh = n * load / COP.
- Else if t_rep > cool_balance: cooling load W = UA * (t_rep - cool_balance). If t_rep < economizer_changeover_c then free cooling with zero compressor electricity (skip). Else COP = interp(t_rep, cooling_cop_curve). Cooling electricity Wh = n * load / COP.
- Else floating zone, no energy.

Sum Wh across bins, convert to kWh divide by 1000. Return heating_kwh, cooling_kwh, total_kwh.

Do not model part-load degradation or capacity limits — the model is load divided by COP only.

`interp(x, curve)` linearly interpolates a sorted list of [temp_c, value] points and clamps to endpoint values outside the range.

Handle 8760 and 8784 lengths.

## Constraints

Python 3 standard library only. Module at /app/degree_days.py importable. Function names signatures exactly as listed. Deterministic pure functions no randomness network.

## Grading

Outputs compared against independent reference across multiple synthetic climates and parameter variations. Tight tolerance 0.2% relative required. All test groups must pass.
