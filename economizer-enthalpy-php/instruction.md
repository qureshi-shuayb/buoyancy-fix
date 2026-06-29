# Economizer Enthalpy with Sensor Fault and Integrated Blending

Implement pure-PHP numerical model of air-side economizer with enthalpy-based switchover, sensor bias, integrated blending, low ambient lockout.

Answer depends on four interacting features not scaffolding: bin method evaluating at bin average; enthalpy calculation via psychrometrics requiring Hyland-Wexler saturation pressure two-branch no closed form; sensor fault bias applied to control decision but true enthalpy used for energy; integrated blending non-linear dependent on enthalpy differential; low ambient lockout.

These couple so single-miss drifts past tight 0.25% tolerance on net savings.

Implement single file at `/app/econ_sim.php`, PHP standard library only. Expose exactly functions listed below.

## Input CSV

Hourly outdoor dry-bulb and wet-bulb temperature CSV with header hour,temp_db,temp_wb similar pattern, plus return air DB WB profiles passed as arrays to annual function. Normal year 8760 rows leap year 8784. Skip malformed rows gracefully keeping valid temperatures in order. Surviving row position defines hour-of-day as index %24.

## Configuration associative array schema

All parameters passed as single config associative array with exactly these keys:

- bin_width_c float temperature bin width degrees C
- sensor_bias_db float sensor bias applied to perceived outdoor dry-bulb for control decision only degrees C
- sensor_bias_wb float sensor bias applied to perceived outdoor wet-bulb for control decision only degrees C
- changeover_enthalpy float enthalpy threshold kJ/kg below which economizer considered favorable
- differential_threshold float enthalpy differential kJ/kg defining integrated blending band width
- low_ambient_lockout_c float outdoor dry-bulb temperature below which economizer disabled to prevent coil freeze regardless of enthalpy
- fan_extra_power_w float extra fan power when economizer active at full open versus mechanical cooling baseline

## Output associative array schema

annual_economizer must return associative array with exactly these keys:

- "fan_extra_kwh" float total extra fan electrical energy consumed due to economizer operation in kWh
- "compressor_saved_kwh" float total compressor electrical energy saved by using free cooling instead of mechanical cooling in kWh, baseline compressor power assumed 1000 W when mechanical cooling active
- "net_savings_kwh" float net savings = compressor_saved_kwh - fan_extra_kwh
- "mode_hours" associative array with keys "economizer", "mechanical", "blending" each mapping to total hours count (float or int) spent in that mode across year weighted by bin counts

Mode hours keys must be exactly those three strings.

## Required formulas and constants

**Saturation pressure Hyland-Wexler ASHRAE 2017:** over ice t<=0 use coefficients c1 -5674.5359 c2 6.3925247 c3 -0.009677843 c4 6.2215701e-7 c5 2.0747825e-9 c6 -9.484024e-13 c7 4.1635019 in exp(c1/Tk + c2 + c3*Tk + c4*Tk^2 + c5*Tk^3 + c6*Tk^4 + c7*ln Tk). Over water t>0 use c8 -5800.2206 c9 1.3914993 c10 -0.048640239 c11 4.1764768e-5 c12 -1.4452093e-8 c13 6.5459673 same form. Tk = t + 273.15.

**Humidity ratio from dry-bulb and wet-bulb:** first compute saturation pressure at wet-bulb ps_wb = sat_pressure(twb). Then ws_wb = 0.621945 * ps_wb / (p - ps_wb) with p default 101325 Pa. Then W = ((2501 - 2.326*twb)*ws_wb - 1.006*(tdb - twb)) / (2501 + 1.86*tdb - 4.186*twb). This is ASHRAE wet-bulb formula water branch simplified sufficient for task.

**Enthalpy moist air:** h = 1.006*tdb + W * (2501 + 1.86*tdb)  in kJ/kg.

**Interpolation helper:** sort curve by x ascending, linear interpolate between surrounding points, clamp to endpoint y below first or above last.

**Bin method:** group hours into temperature bins width bin_width_c using floor(temp_db / bin_width_c). Bin representative temperature is the arithmetic mean of dry-bulb temperatures within the bin (tdb_sum / count), similarly for wet-bulb, return dry-bulb and return wet-bulb averaged within bin. Evaluate each bin cell weighted by count of hours.

**Control decision with sensor bias:** perceived outdoor DB = true DB + sensor_bias_db, perceived WB = true WB + sensor_bias_wb. Compute perceived outdoor enthalpy h_out_perc using perceived DB WB via humidity ratio then enthalpy formula. Compute true outdoor enthalpy h_out_true using true DB WB similarly for energy calculation. Compute return enthalpy h_ret from return DB WB profiles averaged per bin (return profiles passed as arrays same length as outdoor or shorter cycled).

Mode selection logic per bin in order:
- If perceived outdoor DB < low_ambient_lockout_c then mode = mechanical regardless of enthalpy (lockout to prevent freeze).
- Else if h_out_perc < changeover_enthalpy AND h_out_perc < h_ret - differential_threshold then mode = economizer (full free cooling).
- Else if h_out_perc < h_ret AND h_out_perc >= h_ret - differential_threshold then mode = blending (integrated partial).
- Else mode = mechanical.

**Energy calculation using true enthalpy:** baseline compressor power is 1000 W. Energy saved per hour of economizer operation is 1000 Wh, converted to kWh by dividing total Wh by 1000. This constant is part of specification and must be used to ensure deterministic outputs across implementations.

- Economizer mode: compressor saved = 1000 W × hours (Wh), fan extra = fan_extra_power_w × hours (Wh).
- Blending mode: blending ratio = max(0, min(1, (h_ret - h_out_true) / differential_threshold )). This linear ratio determines proportion of free cooling versus mechanical. Compressor saved = 1000 W × ratio × hours (Wh). Fan extra = fan_extra_power_w × ratio × hours (Wh).
- Mechanical mode: saved 0 fan extra 0.

Sum across bins convert Wh to kWh dividing by 1000. Net savings = compressor saved - fan extra.

**Mode hours:** accumulate hours per mode weighted by bin count into associative array with keys exactly "economizer", "mechanical", "blending".

## Functions to implement

```php
function read_temps($csv_path)
function interp($x, $curve)
function enthalpy($tdb, $w)
function annual_economizer($temps_db, $temps_wb, $return_db, $return_wb, $config)
```

annual_economizer must return associative array with keys "fan_extra_kwh", "compressor_saved_kwh", "net_savings_kwh", "mode_hours". mode_hours itself is associative array with three keys as specified.

## Requirements

1. Language PHP 8+, standard library only.
2. File location /app/econ_sim.php.
3. Function signatures exactly as listed.
4. Bin method at bin average per temperature bin. Function interp must implement linear interpolation with clamp as specified for API completeness; annual_economizer uses bin averaging not interp.
5. Psychrometric enthalpy via Hyland-Wexler two-branch no closed form.
6. Sensor bias applied to control decision only, true enthalpy used for energy.
7. Integrated blending linear ratio formula as specified.
8. Low ambient lockout as specified.
9. Units C kJ/kg W kWh hours. Reconcile conversions.
10. Robust 8760 8784 handling skip malformed.
11. Deterministic pure functions.
12. Implementation must respect sensor_bias_db and sensor_bias_wb in control decision; test suite verifies that changing these parameters from baseline alters net savings by at least 1% relative to detect hardcoded outputs or ignored config.

## No cheating

Grader held out not in /app. It checks fan_extra_kwh compressor_saved_kwh net_savings_kwh mode_hours against independent reference over several scenarios cold mixed hot variable. Do not hard-code.
