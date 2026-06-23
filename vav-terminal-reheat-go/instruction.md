# VAV Terminal with Reheat Coil and Static Pressure Reset

Implement a pure-Go numerical model of a VAV terminal unit serving a single zone in a commercial building with variable air volume system, pressure-dependent airflow, hot water reheat coil staging, and duct static pressure reset.

Unlike single degree-days times constant accumulation, answer here depends on four features that interact, and getting any one coupling wrong drifts result past tight 0.5% tolerance:

1. **Bin method.** Energy accumulated over temperature bins not as one running sum over raw hours.
2. **Time-varying static pressure reset schedule.** Available duct static changes by hour based on warmest zone demand, so airflow capability changes by hour-of-day.
3. **Part-load equipment with reheat staging.** VAV damper modulates airflow to meet cooling load down to minimum airflow setpoint, then hot water reheat coil stages on to meet heating load with coil effectiveness varying non-linearly with water flow via NTU relation.
4. **Pressure-dependent airflow.** Airflow solved from damper authority curve versus available static pressure each hour, not commanded directly. Fan power follows affinity laws cubed with flow.

These features couple: reset shifts available static which changes flow which changes whether reheat is needed versus cooling versus deadband floating; reheat staging interacts with minimum airflow setpoint; coil effectiveness depends on flow at bin center which depends on damper position which depends on reset state; fan power depends cubically on flow solved from pressure. A model implementing any single feature but missing interaction will not match.

Implement everything in single file at `/app/vav_sim.go`, using Go standard library only (no third-party packages). Expose exactly functions and signatures listed below.

## Input data hourly temperature CSV

Tool reads CSV holding one year hourly outdoor dry-bulb temperatures with header row and two columns hour,temp_c similar to degree-day-energy task. Normal year 8760 rows leap year 8784 rows. Do not hardcode count — process every valid data row present in file order. File may contain malformed rows blank lines missing empty temp_c or non-numeric temp_c. Skip them gracefully keeping valid temperatures in order. Surviving row position defines hour-of-day as index %24.

## Configuration

All building schedule equipment parameters passed as single config map with exactly these keys:

- UA float64 building heat loss coefficient W/K
- occupied_hours []int with start end inclusive start exclusive end; hour occupied when start <= hod < end else unoccupied
- occupied map with heat_sp float64 cool_sp float64 gain_w float64 min_airflow_m3s float64
- unoccupied map with heat_sp float64 cool_sp float64 gain_w float64 min_airflow_m3s float64
- damper_authority_curve [][]float64 list of [pressure_Pa, flow_m3s] breakpoints defining damper flow vs available static at full open
- static_reset_base_pa float64 base static pressure Pa
- static_reset_min_pa float64 minimum reset Pa
- static_reset_max_pa float64 maximum reset Pa
- coil_effectiveness_curve [][]float64 list of [water_flow_lps, effectiveness] breakpoints for hot water reheat coil NTU-effectiveness relation approximated via curve
- bin_width_c float64 temperature bin width degrees C
- fan_efficiency float64 overall fan total efficiency 0..1

heat_sp cool_sp gain_w are heating setpoint C cooling setpoint C and combined internal solar heat gains W for that occupancy state. gain_w lower when unoccupied; unoccupied heating setpoint set back lower and unoccupied cooling setpoint set up higher. min_airflow differs per occupancy state.

## Concepts and units

**Balance points derived per occupancy state.** Internal gains warm building so temperature at which heating or cooling actually needed is offset from setpoint. For given occupancy state with setpoints heat_sp cool_sp and gains gain_w: T_balance_heat = heat_sp - gain_w/UA ; T_balance_cool = cool_sp - gain_w/UA ; gain_w/UA is temperature offset in kelvin. Heating needed only when outdoor temperature below Tb_heat; cooling only when above Tb_cool; between the two building floats and uses no heating cooling energy except fan at minimum airflow. Because occupied and unoccupied states have different setpoints gains and min airflow, balance points differ by hour-of-day — you must use balance points for occupancy state active each hour. Do not use raw setpoints and do not use single fixed balance point for whole year.

**Bin method.** Rather than accumulating over each raw hour group hours into temperature bins width bin_width_c. Use bin index floor(temp_c / bin_width_c) and let each bin representative temperature be bin center (bin_index+0.5)*bin_width_c. Bins must be kept separately per occupancy state because balance points gains and min airflow differ. Evaluate each cell loads and equipment efficiency at bin representative temperature weighted by number hours in that cell.

**Heating thermal load.** For heating bin representative temperature below active Tb_heat thermal load is UA * (Tb_heat - T_rep) watts.

**Cooling thermal load.** For cooling bin representative temperature above active Tb_cool thermal load is UA * (T_rep - Tb_cool) watts.

**Pressure-dependent airflow.** For each bin cell determine required airflow to meet load at bin center temperature given UA and balance points using standard VAV airflow formula airflow = load / (rho*cp*delta_T) simplified with rho*cp approximated as 1200 J per m3 K for this task to keep deterministic, capped between minimum airflow for that occupancy state and maximum flow achievable from damper authority curve at available static pressure for that hour-of-day derived from static reset schedule. Available static pressure follows reset schedule based on outdoor temperature linear between reset_min at coldest outdoor temp in profile and reset_max at warmest. Solve damper position needed to achieve required flow via damper authority curve inverse linear interpolation then clamp 0..1. If required flow exceeds maximum achievable at available static cap at maximum and record comfort violation proportionally.

**Fan power.** Fan electrical power = air_power / fan_efficiency where air_power = flow_m3s * static_pressure_pa simplified. Fan affinity laws imply power scales with flow cubed at constant static but here static also varies via reset so must compute per bin explicitly not average.

**Reheat coil staging.** When in heating mode and at minimum airflow if heating load exceeds what minimum airflow at supply air temperature can deliver then reheat coil activates. Coil heat delivered = UA*(Tb_heat - T_rep) - airflow*1200*(supply_temp - T_rep) simplified. Coil effectiveness from coil_effectiveness_curve via linear interpolation at water flow rate needed approximated proportional to heat delivered divided by max coil capacity clamped to endpoint effectiveness below coldest or above warmest breakpoint. Heating electricity equivalent for hot water assumed gas boiler efficiency 0.9 with electrical equivalent factor 0.05 to convert thermal to electrical kWh for single metric reporting.

**Comfort accounting.** Degree-hours outside deadband similar to thermostat task using indoor temperature at end of step approximated via steady-state assumption per bin for simplicity or via exact analytic 1R1C update like thermostat task if desired for more accuracy — either approach acceptable as long as outputs match reference within tolerance across test grid.

## Functions to implement

```go
package main

func ReadTemps(csvPath string) ([]float64, error)

func Interp(x float64, curve [][]float64) float64

func BalancePoints(heatSp float64, coolSp float64, gainW float64, ua float64) (float64, float64)

func AnnualEnergy(temps []float64, config map[string]interface{}) map[string]float64
```

AnnualEnergy must return map with keys "fan_kwh", "reheat_kwh", "comfort_degree_hours", "total_kwh". total_kwh is sum fan + reheat.

## Requirements

1. Language Go 1.23+, standard library only math package allowed.
2. Module location /app/vav_sim.go package main importable via go test.
3. Function names signatures exactly as listed. AnnualEnergy must return map with keys fan_kwh reheat_kwh comfort_degree_hours total_kwh.
4. Bin method accumulate over temperature bins per occupancy state evaluating at bin center not raw hour sum.
5. Schedule-dependent balance points use occupied or unoccupied according to hour-of-day never single fixed balance point.
6. Pressure-dependent airflow solved per bin via damper authority curve and available static from reset schedule never constant airflow.
7. Coil effectiveness interpolated per bin via curve reheat staging respects minimum airflow.
8. Units temperatures C gains W UA W/K energies kWh comfort degree-hours. Reconcile hour to energy and W to kW conversions.
9. Robust input handle 8760 and 8784 row files skip malformed rows hour-of-day derives from position within valid temperatures.
10. Deterministic pure functions same inputs same outputs no randomness wall-clock network.

## No cheating

Grader is held out not in /app and you will not see it during task. It imports your package and checks energy_kwh comfort_degree_hours and trajectory length against independent reference over several scenarios including mild day with static reset active, cold day requiring reheat at minimum airflow, hot day with high fan energy at maximum static, and variable day crossing reset thresholds. Do not attempt to detect special-case or hard-code grader inputs or expected outputs; solutions must implement model as specified for arbitrary inputs.
