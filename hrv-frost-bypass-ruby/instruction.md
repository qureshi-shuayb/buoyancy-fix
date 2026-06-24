# HRV Frost Bypass with Effectiveness Derate and Supply Temperature Maintenance

Implement a pure-Ruby numerical model of a heat recovery ventilator serving a commercial building ventilation system with frost control bypass damper, effectiveness derate curve, and supplementary heating to maintain supply temperature setpoint.

Answer depends on four interacting features not scaffolding: bin method per occupancy state evaluating at bin center; time-varying indoor humidity generation schedule affecting frost point; bypass damper hysteresis state machine interacting with supply temperature maintenance; fan power rise with bypass position non-linear.

These couple so single-miss drifts past tight tolerances.

Implement everything in single file at `/app/hrv_sim.rb`, using Ruby standard library only csv and math. Expose exactly functions listed below.

## Input CSV

Hourly outdoor temperature CSV with header hour,temp_c. Normal year 8760 rows leap year 8784. Skip malformed rows gracefully keeping valid temperatures in order. Surviving row position defines hour-of-day as index %24.

## Configuration hash

All parameters passed as single config hash with keys:
- UA float
- occupied_hours [start,end]
- occupied hash with heat_sp, supply_setpoint, gain_w, moisture_generation_gpers, min_airflow_m3s
- unoccupied hash same keys
- effectiveness_curve [[airflow_ratio, effectiveness],...]
- frost_threshold_offset_c
- frost_hysteresis_c
- bin_width_c
- fan_power_base_w
- fan_bypass_penalty_factor

## Functions to implement

```ruby
module HRVSim
  def self.read_temps(csv_path); end
  def self.interp(x, curve); end
  def self.frost_point(humidity_ratio, pressure = 101325); end
  def self.annual_hrv(temps, humidity_profile, config); end
end
```

annual_hrv must return hash with keys "fan_kwh", "supplementary_heating_kwh", "recovered_kwh", "frost_hours", "total_kwh". total is fan + supplementary.

## Requirements

1. Language Ruby 3+, standard library only.
2. Module location /app/hrv_sim.rb defining module HRVSim.
3. Function signatures exactly as listed.
4. Bin method per occupancy state at bin center.
5. Schedule-dependent humidity and balance points per hour-of-day.
6. Effectiveness interpolated per bin via curve never constant.
7. Frost point dynamic via psychrometric saturation pressure inverse solved numerically per hour never fixed threshold; hysteresis state machine.
8. Fan power rise with bypass accounted.
9. Units C W UA W/K energies kWh frost hours count.
10. Robust 8760 8784 handling skip malformed.
11. Deterministic pure functions.

## No cheating

Grader held out not in /app. It checks energies recovered supplementary fan frost hours against independent reference over several scenarios cold mixed mild variable. Do not hard-code.
