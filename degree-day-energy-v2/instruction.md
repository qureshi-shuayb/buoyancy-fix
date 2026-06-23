# Annual Building Energy Estimator

Build a pure Python tool estimating annual heating and cooling **electricity use in kWh** from hourly outdoor temperatures. The result depends on four interacting mechanisms; missing any coupling drifts beyond 0.5% tolerance.

## Module location

Create single file at `/app/degree_days.py` importable as standard library only. Export exactly these functions:

```python
def read_temps(csv_path: str) -> list[float]: ...
def interp(x: float, curve: list) -> float: ...
def balance_points(heat_sp: float, cool_sp: float, gain_w: float, UA: float) -> tuple: ...
def annual_energy(temps: list, config: dict) -> dict: ...
```

## Input CSV

Hourly outdoor dry bulb temperatures with header `hour,temp_c`. Example:

```
hour,temp_c
0,4.1
1,3.7
...
8759,5.0
```

* `hour` is 0-based row marker; hour-of-day derived as position modulo 24 after filtering valid rows.
* `temp_c` float Celsius, may be negative.
* Normal year 8760 rows, leap year 8784 rows. Process all valid rows present, do not hardcode count.
* Malformed rows — blank, missing temp_c, non-numeric — skip gracefully preserving order of valid temps. Hour-of-day then comes from index in filtered list.

## Configuration dict

Single `config` dict with exact keys:

```python
{
 "UA": float,  # W per K building heat loss coefficient
 "occupied_hours": [start, end],  # inclusive start exclusive end, 0-24 ints. Occupied if start <= hod < end else unoccupied
 "occupied":   {"heat_sp": float, "cool_sp": float, "gain_w": float},
 "unoccupied": {"heat_sp": float, "cool_sp": float, "gain_w": float},
 "heating_cop_curve": [[temp_c, cop], ...],  # sorted ascending temp, heat pump heating COP
 "cooling_cop_curve": [[temp_c, cop], ...],  # sorted ascending temp, AC cooling COP
 "backup_lockout_c": float,  # below this outdoor temp heat pump locked out, resistance backup COP 1
 "economizer_changeover_c": float,  # cooling below this outdoor temp uses free cooling zero electricity
 "bin_width_c": float,  # temperature bin width degrees C
}
```

Heat setpoint lower when unoccupied setback, cool setpoint higher when unoccupied setup. Gains lower unoccupied.

## Derived balance points

Internal gains offset setpoints. For given occupancy state:

```
T_balance_heat = heat_sp - gain_w / UA
T_balance_cool = cool_sp - gain_w / UA
```

Heating needed only when outdoor < T_balance_heat. Cooling needed only when outdoor > T_balance_cool. Between, building floats zero energy. Because occupied vs unoccupied have different setpoints and gains, balance points differ by hour of day. Must use per-hour occupancy state balance points, never raw setpoints nor single fixed balance.

## Bin method

Group hours into temperature bins width `bin_width_c`. Bin index = floor(temp_c / bin_width_c). Representative temperature = (bin_index + 0.5) * bin_width_c = bin center.

Keep bins separately per occupancy state — same temperature but different occupancy is different cell because balance points differ.

Evaluate each cell's load and equipment efficiency at representative temperature, weighted by count of hours in cell. Do not sum raw hours directly; bin evaluation is required.

## Thermal loads

For heating cell where t_rep < T_balance_heat:
```
thermal_load_W = UA * (T_balance_heat - t_rep)
```
For cooling cell where t_rep > T_balance_cool:
```
thermal_load_W = UA * (t_rep - T_balance_cool)
```
Otherwise zero.

## Heating equipment

Heating COP from `heating_cop_curve` via linear interpolation at t_rep, clamped to endpoint COP outside curve range. If t_rep < backup_lockout_c then heat pump locked out, use electric resistance backup COP exactly 1.0.

Heating electricity Wh for cell = n_hours * thermal_load_W / efficiency.

## Cooling equipment

Cooling COP from `cooling_cop_curve` via linear interpolation at t_rep clamped similarly.

Economizer rule: for cooling cell where t_rep < economizer_changeover_c, cooling load met with outdoor air free cooling, compressor electricity zero for that cell. At or above changeover, normal compressor operation.

Cooling electricity Wh = n_hours * thermal_load_W / COP, or zero if economizer applies.

## Units and accounting

Each sample represents one hour, so watts * 1 hour = watt-hours. Sum per-cell contributions, divide by 1000 to kWh. Return dict:
```python
{"heating_kwh": float, "cooling_kwh": float, "total_kwh": float}
```
total is sum, never negative, heating and cooling separate.

## Function specifications

`read_temps(csv_path: str) -> list[float]`
Parse CSV, return temp_c values in file order skipping malformed rows. Use csv DictReader or similar standard library.

`interp(x: float, curve: list) -> float`
Linear interpolation of [[x,y],...] sorted by x at position x, clamped to endpoint y below first or above last breakpoint.

`balance_points(heat_sp, cool_sp, gain_w, UA) -> tuple`
Return (heat_sp - gain_w/UA, cool_sp - gain_w/UA).

`annual_energy(temps: list, config: dict) -> dict`
Implement bin method with schedule-dependent balance points, interpolated heating COP with resistance backup below lockout, interpolated cooling COP, economizer exclusion. Return heating, cooling, total kWh.

## Requirements

1 Python 3 standard library only.
2 Module at /app/degree_days.py exactly those four functions.
3 Bin method per occupancy state at bin center, not raw hour sum.
4 Schedule-dependent balance points per hour-of-day.
5 Interpolate COP curves per bin, apply backup lockout COP 1.
6 Economizer zero electricity below changeover.
7 Temperatures C, gains W, UA W/K, energies kWh. Reconcile W to kW and hour to energy.
8 Handle 8760 and 8784 lengths, skip malformed rows, hour-of-day from filtered position.
9 Deterministic pure functions.

## Grading tolerances

* interp and balance_points graded tight absolute 1e-6 relative 1e-6.
* annual energy graded 0.5% relative tolerance 1e-6 absolute.
* Tests include shoulder season, temperate, hot, cold climates, leap year variant, parametrized UA gains economizer lockout, CSV roundtrip, malformed rows, hot zero heating, cold zero cooling, end-to-end CSV, and fail-signal checks ensuring each naive shortcut drifts >2% (4x tolerance).

## Notes

Canary GUID for benchmark tracking: 7f3c1d92-4d8b-4e6a-9c2f-1b5e0d7a6c34 — preserve in file headers.
