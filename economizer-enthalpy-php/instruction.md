# Economizer Enthalpy with Sensor Fault and Integrated Blending

Implement pure-PHP numerical model of air-side economizer with enthalpy-based switchover, sensor bias, integrated blending, low ambient lockout.

Answer depends on four interacting features: bin method per occupancy evaluating at bin center; enthalpy calculation via psychrometrics requiring Hyland-Wexler saturation pressure two-branch no closed form; sensor fault bias applied to control decision but true enthalpy used for energy; integrated blending non-linear dependent on enthalpy differential; low ambient lockout.

Implement single file at `/app/econ_sim.php` using PHP standard library only. Expose functions:

```php
function read_temps($csv_path)
function interp($x, $curve)
function enthalpy($tdb, $w)
function annual_economizer($temps_db, $temps_wb, $return_db, $return_wb, $config)
```

annual_economizer must return associative array with keys "fan_extra_kwh", "compressor_saved_kwh", "net_savings_kwh", "mode_hours".

Requirements: PHP 8+, standard library only, bin method, schedule-dependent, psychrometric enthalpy via Hyland-Wexler, sensor bias split control vs energy, integrated blending, lockout, units C W kWh, robust CSV handling 8760 8784 skip malformed, deterministic.

No cheating: grader held out checks against independent reference over several scenarios cold mixed hot variable. Do not hard-code.
