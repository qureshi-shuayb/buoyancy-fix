# HRV Frost Bypass with Effectiveness Derate and Supply Temperature Maintenance

Implement a pure-Ruby numerical model of a heat recovery ventilator serving a commercial building ventilation system with frost control bypass damper, effectiveness derate curve, and supplementary heating to maintain supply temperature setpoint.

Unlike single effectiveness times constant accumulation, answer here depends on four features that interact, and getting any one coupling wrong drifts result past tight tolerances.

## Deliverable

Create single file at `/app/hrv_sim.rb` defining module HRVSim with exactly these methods exposed as module functions:

```ruby
module HRVSim
  def self.read_temps(csv_path); end
  def self.interp(x, curve); end
  def self.frost_point(humidity_ratio, pressure = 101325); end
  def self.annual_hrv(temps, humidity_profile, config); end
end
```

Annual HRV must return hash with keys "fan_kwh", "supplementary_heating_kwh", "recovered_kwh", "frost_hours", "total_kwh". total is fan + supplementary heating.

## Input CSV

Hourly outdoor temperature CSV with header hour,temp_c similar to degree-day task. Normal year 8760 rows leap year 8784. Skip malformed rows gracefully keeping valid temperatures in order. Surviving row position defines hour-of-day as index %24. Separate indoor humidity generation profile passed as list to annual_hrv or via config.

## Configuration

All parameters passed as single config hash with exactly these keys:

- UA float building heat loss coefficient W/K (for reference, not directly used in HRV calc but for context)
- occupied_hours [start,end] ints hour occupied when start <= hod < end
- occupied hash with heat_sp float, supply_setpoint float, gain_w float, moisture_generation_gpers float, min_airflow_m3s float
- unoccupied hash with heat_sp float, supply_setpoint float, gain_w float, moisture_generation_gpers float, min_airflow_m3s float
- effectiveness_curve [[airflow_ratio, effectiveness], ...] list breakpoints defining sensible effectiveness vs airflow ratio to design flow
- frost_threshold_offset_c float safety margin below frost point to trigger bypass open
- frost_hysteresis_c float hysteresis band to close bypass to prevent chattering
- bin_width_c float temperature bin width degrees C
- fan_power_base_w float fan power at design airflow through core path
- fan_bypass_penalty_factor float multiplier on fan power when bypass fully open vs core path reflecting increased pressure drop

heat_sp is heating setpoint for reference not directly used in HRV energy except via comfort context. supply_setpoint is target supply air temperature after HRV and supplementary heater. gain_w and moisture_generation affect indoor humidity which affects exhaust humidity ratio which affects frost point.

## Concepts

**Effectiveness derate.** Nominal sensible effectiveness at design airflow ratio 1.0 is given by curve at airflow ratio 1. Interpolate effectiveness from effectiveness_curve based on actual airflow ratio for each bin cell (airflow divided by design airflow implied from config). Effectiveness also derates with temperature differential non-linearly approximated via same curve for simplicity in this task.

**Frost point dynamic.** Exhaust air humidity ratio depends on indoor moisture generation schedule varying by hour-of-day occupancy state plus outdoor humidity assumed fixed at 0.002 kg/kg for simplicity in this task to keep deterministic without full psychrometrics input, but frost point still must be computed via psychrometric saturation pressure relationship inverse to find temperature at which saturation pressure equals partial pressure derived from humidity ratio. Use Hyland-Wexler correlation for saturation pressure over ice below 0C and over water above, no closed form inverse so solve numerically via bisection similar to psychrometrics-library dew point task. Frost threshold for bypass open is frost_point minus frost_threshold_offset_c.

**Bypass damper hysteresis state machine.** At start of each hour evaluate exhaust temperature at cold corner approximated as function of outdoor temp indoor temp effectiveness and airflow. If exhaust cold corner temperature below frost threshold for current occupancy state then bypass must open to protect core. Once open it stays open until exhaust temperature rises above frost threshold plus hysteresis band to prevent chattering. While bypass open effectiveness drops to near zero (bypassed air does not go through heat exchanger) and fan power rises by fan_bypass_penalty_factor at full bypass linearly interpolated by bypass fraction.

**Supply temperature maintenance and supplementary heating.** After HRV (with or without bypass), supply air temperature may be below supply_setpoint especially during bypass events in cold weather. Supplementary electric heater downstream of HRV must raise supply air to setpoint. Heater thermal power = airflow * 1200 * max(0, supply_setpoint - temp_after_hrv) watts simplified using rho*cp approx 1200 J/m3K. Heater electrical input equals thermal output COP 1. Sum over hours convert to kWh.

**Fan energy accounting.** Fan electrical power at each bin depends on airflow ratio cubed times static pressure factor adjusted for bypass penalty. Base fan power at design airflow through core path is fan_power_base_w. At part airflow ratio r, fan power scales with r^3 times pressure factor 1.0 for core path or fan_bypass_penalty_factor for bypass path linearly interpolated. Sum over hours convert W·h to kWh dividing by 1000.

**Comfort and recovered energy.** Recovered heat kWh is thermal energy transferred from exhaust to supply via HRV effectiveness when not bypassed, calculated per bin as effectiveness * airflow * 1200 * (indoor_temp - outdoor_temp) positive only when heat recovery beneficial (outdoor colder than indoor). Comfort degree-hours not required for this task simplified to focus on energy; supplementary heating ensures supply setpoint met so comfort assumed maintained except we still report frost hours count.

## Functions to implement

```ruby
module HRVSim
  def self.read_temps(csv_path)
    # Parse hourly temperature CSV at csv_path and return temp_c values as array of floats in file chronological order. Malformed rows skipped.
  end

  def self.interp(x, curve)
    # Linear interpolation of [[x,y],...] curve sorted by x at x clamped to endpoint y-value below first or above last breakpoint.
  end

  def self.frost_point(humidity_ratio, pressure = 101325)
    # Return frost point temperature C for given humidity ratio kg/kg and pressure Pa using Hyland-Wexler saturation pressure inverse solved numerically. No closed form.
  end

  def self.annual_hrv(temps, humidity_profile, config)
    # Return annual energy dict using bin method with schedule-dependent balance points effectiveness derate dynamic frost point hysteresis bypass state machine fan power rise and supplementary heating as described. Return hash with keys "fan_kwh", "supplementary_heating_kwh", "recovered_kwh", "frost_hours", "total_kwh".
  end
end
```

## Requirements

1. Language Ruby 3+, standard library only csv and math allowed.
2. Module location /app/hrv_sim.rb defining module HRVSim importable via require.
3. Function names signatures exactly as listed. annual_hrv must return hash with keys fan_kwh supplementary_heating_kwh recovered_kwh frost_hours total_kwh.
4. Bin method accumulate over temperature bins per occupancy state evaluating at bin center not raw hour sum.
5. Schedule-dependent indoor humidity generation and balance points use occupied or unoccupied according to hour-of-day never single fixed.
6. Effectiveness interpolated per bin via curve with NTU relation approximation never constant effectiveness.
7. Frost point dynamic via psychrometric saturation pressure inverse solved numerically per hour never fixed outdoor temp threshold; hysteresis state machine for bypass open close to prevent chattering.
8. Fan power rise with bypass position accounted per bin never constant fan power.
9. Units temperatures C gains W UA W/K energies kWh frost hours count. Reconcile hour to energy and W to kW conversions.
10. Robust input handle 8760 and 8784 row files skip malformed rows hour-of-day derives from position within valid temperatures.
11. Deterministic pure functions same inputs same outputs no randomness wall-clock network.

## No cheating

Grader is held out not in /app and you will not see it during task. It requires your module and checks energy recovered supplementary fan and frost hours against independent reference over several scenarios including cold climate with heavy frost, mixed climate with intermittent frost, mild climate with no frost, and variable day crossing frost threshold with hysteresis exercising. Do not attempt to detect special-case or hard-code grader inputs or expected outputs; solutions must implement model as specified for arbitrary inputs.
