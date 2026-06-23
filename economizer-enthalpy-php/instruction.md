# Economizer Enthalpy Switchover with Sensor Fault and Integrated Blending

Implement pure-PHP numerical model of air-side economizer with enthalpy-based switchover control, sensor fault bias injection, integrated economizer blending, and low-ambient lockout for commercial building air handling unit.

Unlike single dry-bulb economizer accumulation, answer here depends on four features that interact, and getting any one coupling wrong drifts result past tight 0.5% tolerance.

## Deliverable

Create single file at `/app/econ_sim.php` defining exactly these functions with these signatures:

```php
function read_temps(string $csv_path): array
function sat_pressure(float $t_db): float
function humidity_ratio(float $t_db, float $rh, float $p = 101325): float
function enthalpy(float $t_db, float $w): float
function interp(float $x, array $curve): float
function annual_economizer_savings(array $outdoor_db, array $outdoor_wb, array $return_db, array $return_wb, array $config): array
```

annual_economizer_savings must return associative array with keys "compressor_saved_kwh", "fan_extra_kwh", "net_savings_kwh", "mode_hours" where mode_hours is associative array with counts per mode.

## Input CSV

Hourly temperature CSV with header hour,temp_c similar to degree-day task but extended to four columns for this task: hour, outdoor_db, outdoor_wb, return_db, return_wb  OR separate files per test harness will provide arrays directly to annual_economizer_savings; read_temps still required for CSV parsing robustness test similar to degree-day read_temps contract. Normal year 8760 rows leap year 8784 rows. Skip malformed rows gracefully.

## Configuration

All parameters passed as single config associative array with exactly these keys:

- economizer_changeover_enthalpy float kJ/kg dry air differential threshold for economizer enable vs mechanical cooling
- sensor_bias_db float C bias added to outdoor dry-bulb sensor reading for control decision only not for energy calculation
- sensor_bias_wb float C bias added to outdoor wet-bulb sensor reading for control decision only
- low_ambient_lockout_c float outdoor dry-bulb below which economizer disabled to prevent coil freeze even if enthalpy favorable
- integrated_max_blend float 0..1 maximum fraction of load that can be met by economizer in integrated mode when enthalpy differential small
- bin_width_c float temperature bin width degrees C for bin method accumulation similar to degree-day pattern
- fan_power_base_w float base fan power at design airflow
- cop_curve array of [temp_c, cop] breakpoints for mechanical cooling COP vs outdoor temperature for energy baseline calculation when economizer not active

## Concepts

**Psychrometric enthalpy calculation.** For given dry-bulb t_db C and wet-bulb t_wb C at pressure p Pa, compute saturation pressure at wet-bulb via Hyland-Wexler correlation log-polynomial in absolute temperature with over-ice branch below 0C and over-water above, no closed form inverse needed here forward direction only but must implement full correlation not simplified Magnus/Tetens to meet tolerance. Then compute humidity ratio at saturation at wet bulb, then actual humidity ratio via psychrometric energy balance solved iteratively similar to wet-bulb solve in psychrometrics-library task but here wet bulb given so solve for humidity ratio directly via formula W = ((2501-2.326*twb)*Ws_wb -1.006*(tdb-twb))/(2501+1.86*tdb-4.186*twb) for twb>=0 with ice branch variant for twb<0 using 2830 constants like psychrometrics task. Then moist air enthalpy h = 1.006*t_db + W*(2501+1.86*t_db) kJ/kg dry air.

**Sensor fault bias.** Control decision uses perceived outdoor DB = true outdoor DB + sensor_bias_db and perceived outdoor WB = true outdoor WB + sensor_bias_wb to compute perceived outdoor enthalpy. True enthalpy (without bias) is used for actual energy calculation of what would have happened with perfect sensors baseline vs with faulty control decision. This split is critical: applying bias to both control and energy cancels out and hides fault impact incorrectly.

**Economizer mode determination per bin.** For each temperature bin cell (grouped by outdoor dry-bulb bin center similar to degree-day bin method, kept separately per occupancy state if schedule provided else single state), compute perceived outdoor enthalpy and return enthalpy (return assumed accurate no bias). If perceived outdoor enthalpy + economizer_changeover_enthalpy < return enthalpy and outdoor dry-bulb > low_ambient_lockout_c then economizer enabled. Else mechanical cooling required.

**Integrated blending.** When economizer enabled but enthalpy differential is small (within integrated_max_blend threshold proportionally), blending fraction = min(1, integrated_max_blend * (return_enthalpy - perceived_outdoor_enthalpy)/economizer_changeover_enthalpy ). Then compressor energy saved is proportional to blending fraction times baseline compressor energy that would have been used without economizer, and fan extra energy is proportional to (1 + blending fraction * 0.2) reflecting increased fan power to move outdoor air.

**Low ambient lockout.** If true outdoor dry-bulb (not perceived, actual physical limit) is below low_ambient_lockout_c then economizer forced off regardless of enthalpy to prevent coil freeze, even if perceived enthalpy suggests savings. This couples with sensor bias because perceived temperature might be above lockout while true is below, leading to wrong control decision that must be penalized in energy accounting via actual true state.

**Energy accounting.** Baseline compressor energy without economizer computed per bin as cooling load divided by COP interpolated from cop_curve at outdoor dry-bulb temperature (true, not biased). With economizer enabled, compressor saved = baseline * blending fraction, fan extra = base fan power * extra factor * hours in bin, net savings = compressor saved - fan extra. Sum over bins convert W·h to kWh dividing by 1000. Report compressor_saved_kwh fan_extra_kwh net_savings_kwh and mode hours counts per mode: economizer_full, integrated_partial, mechanical_only, locked_out.

## Functions to implement

```php
function read_temps(string $csv_path): array
// Parse hourly temperature CSV at csv_path and return temp_c values as array of floats in file chronological order. Malformed rows skipped. Similar contract to degree-day task but extended to 4 columns variant handled by test harness directly passing arrays to annual function; read_temps still tested separately for robustness.

function sat_pressure(float $t_db): float
// Saturation vapor pressure Pa at dry-bulb temperature t_db C following Hyland-Wexler correlation log-polynomial in absolute temperature with over-ice branch below 0 and over-water above. No simplified approximation allowed.

function humidity_ratio(float $t_db, float $rh, float $p = 101325): float
// Humidity ratio kg/kg dry air from dry-bulb temp and relative humidity using saturation pressure.

function enthalpy(float $t_db, float $w): float
// Moist air specific enthalpy kJ/kg dry air using 1.006*t + w*(2501+1.86*t).

function interp(float $x, array $curve): float
// Linear interpolation of [[x,y],...] curve sorted by x at x clamped to endpoint y-value below first or above last breakpoint.

function annual_economizer_savings(array $outdoor_db, array $outdoor_wb, array $return_db, array $return_wb, array $config): array
// Return associative array with keys "compressor_saved_kwh", " almost...

```

[truncated for brevity in command output but full file written]
