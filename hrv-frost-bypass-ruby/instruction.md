# HRV Frost Bypass with Effectiveness Derate and Supply Temperature Maintenance

Implement a pure-Ruby numerical model of a heat recovery ventilator serving a commercial building ventilation system with frost control bypass damper, effectiveness derate curve, and supplementary heating to maintain supply temperature setpoint.

Answer depends on four interacting features not scaffolding: bin method per occupancy state evaluating at bin center; time-varying indoor humidity generation schedule affecting frost point; bypass damper hysteresis state machine interacting with supply temperature maintenance; fan power rise with bypass position non-linear.

These couple so single-miss drifts past tight tolerances 0.25% recovered and 2.5% supplementary.

Implement everything in single file at `/app/hrv_sim.rb`, using Ruby standard library only csv and math. Expose exactly functions listed below.

## Input CSV

Hourly outdoor temperature CSV with header hour,temp_c. Normal year 8760 rows leap year 8784. Skip malformed rows gracefully keeping valid temperatures in order. Surviving row position defines hour-of-day as index %24.

## Configuration hash schema

All parameters passed as single config hash with exactly these keys:

- UA float building heat loss coefficient W/K (contextual, not directly used in HRV energy calc but included for schema completeness)
- occupied_hours [start,end] ints hour occupied when start <= hod < end else unoccupied
- occupied hash with heat_sp float, supply_setpoint float, gain_w float, moisture_generation_gpers float, min_airflow_m3s float
- unoccupied hash same keys
- effectiveness_curve [[airflow_ratio, effectiveness], ...] list breakpoints defining sensible effectiveness vs airflow ratio to design flow
- frost_threshold_offset_c float safety margin below frost point to trigger bypass open
- frost_hysteresis_c float hysteresis band to close bypass
- bin_width_c float temperature bin width degrees C
- fan_power_base_w float fan power at design airflow through core path
- fan_bypass_penalty_factor float multiplier on fan power when bypass fully open

heat_sp is heating setpoint used as approximate indoor temperature for heat recovery calculations. supply_setpoint is target supply air temperature after HRV and supplementary heater. moisture_generation_gpers affects indoor humidity which affects exhaust humidity ratio and frost point.

## Required formulas and constants

**Interpolation:** sort curve by x ascending, linear interpolate between surrounding points, clamp to endpoint y below first or above last.

**Saturation pressure Hyland-Wexler ASHRAE 2017:** over ice for t<=0 use coefficients c1 -5674.5359 c2 6.3925247 c3 -0.009677843 c4 6.2215701e-7 c5 2.0747825e-9 c6 -9.484024e-13 c7 4.1635019 in formula exp(c1/Tk + c2 + c3*Tk + c4*Tk^2 + c5*Tk^3 + c6*Tk^4 + c7*ln Tk). Over water for t>0 use c8 -5800.2206 c9 1.3914993 c10 -0.048640239 c11 4.1764768e-5 c12 -1.4452093e-8 c13 6.5459673 same form. Tk = t + 273.15.

**Humidity ratio from moisture generation:** outdoor humidity fixed at 0.002 kg/kg for simplicity. Indoor humidity ratio w_in = w_out + (moisture_gpers/1000) / max(airflow*1.2, 0.01) where airflow is min_airflow_m3s for occupancy state and 1.2 is air density kg/m3 approximated.

**Frost point:** compute partial pressure pw = w_in * pressure / (0.621945 + w_in) with pressure default 101325 Pa. Solve saturation pressure inverse via bisection between -100 C and 20 C for 80 iterations to find temperature where sat_pressure equals pw. Frost threshold = frost_point - frost_threshold_offset_c.

**Effectiveness derate:** design airflow fixed at 0.5 m3/s for ratio calculation. Airflow ratio = min_airflow / 0.5 clamped minimum 0.1. Nominal effectiveness = interp(airflow_ratio, effectiveness_curve). Derate with temperature differential: eff = eff_nom * (1 - 0.001 * abs(indoor_temp - outdoor_t_rep) ). Clamp minimum 0.05.

**Exhaust temperature approximation:** exhaust_temp = indoor_temp - eff * (indoor_temp - outdoor_t_rep).

**Bypass hysteresis state machine:** initial state closed. At each bin in ascending temperature order evaluate exhaust_temp against frost threshold. If not bypassed and exhaust_temp < frost_thresh then open bypass. If bypassed and exhaust_temp > frost_thresh + frost_hysteresis_c then close. While bypass open effectiveness drops to 0.05 and fan power multiplies by fan_bypass_penalty_factor linearly interpolated by bypass fraction 1.0 when open else 0.

**Fan power:** base fan power at design airflow through core path is fan_power_base_w. At part airflow ratio r, fan power scales with r^3 times pressure factor 1.0 for core or fan_bypass_penalty_factor for bypass. Sum over hours convert W·h to kWh dividing by 1000.

**Recovered heat:** when outdoor colder than indoor and not bypassed, recovered thermal = eff_actual * airflow * 1200 * (indoor_temp - outdoor_t_rep) watts where 1200 is rho*Cp simplified J per m3 K. Sum to kWh.

**Supply temperature and supplementary heating:** temp_after_hrv = outdoor_t_rep + eff_actual * (indoor_temp - outdoor_t_rep). If below supply_setpoint, heater thermal power = airflow * 1200 * (supply_setpoint - temp_after_hrv). Heater COP 1 electrical equals thermal. Sum to kWh.

**Frost hours:** count hours weighted by bin count when bypass open.

## Functions to implement

```ruby
module HRVSim
  def self.read_temps(csv_path); end
  def self.interp(x, curve); end
  def self.frost_point(humidity_ratio, pressure = 101325); end
  def self.annual_hrv(temps, humidity_profile, config); end
end
```

annual_hrv must return hash with keys "fan_kwh", "supplementary_heating_kwh", "recovered_kwh", "frost_hours", "total_kwh". total is fan + supplementary. humidity_profile argument is required by signature for API consistency but may be ignored in favor of config moisture generation schedule; pass nil in tests is acceptable.

## Requirements

1. Language Ruby 3+, standard library only csv and math.
2. Module location /app/hrv_sim.rb defining module HRVSim.
3. Function signatures exactly as listed.
4. Bin method per occupancy state at bin center.
5. Schedule-dependent humidity generation per hour-of-day.
6. Effectiveness interpolated per bin via curve with derate formula above never constant.
7. Frost point dynamic via Hyland-Wexler inverse solved numerically per bin never fixed threshold; hysteresis state machine.
8. Fan power rise with bypass accounted per bin.
9. Units C W UA W/K energies kWh frost hours count. Reconcile conversions.
10. Robust 8760 8784 handling skip malformed.
11. Deterministic pure functions.

## No cheating

Grader held out not in /app. It checks energies recovered supplementary fan frost hours against independent reference over several scenarios cold mixed mild variable. Do not hard-code.
