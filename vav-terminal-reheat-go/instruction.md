# VAV Terminal with Reheat Coil and Static Pressure Reset

Implement a pure-Go numerical model of a VAV terminal unit serving a single zone in a commercial building with variable air volume system, pressure-dependent airflow, hot water reheat coil staging, and duct static pressure reset.

Unlike simple bin method accumulation, answer here depends on four features that interact, and getting any one coupling wrong drifts result past tight 2% tolerance:

1. **Bin method.** Energy accumulated over temperature bins not as one running sum over raw hours, per occupancy state, evaluated at bin center.
2. **Time-varying static pressure reset schedule.** Available duct static changes by hour based on outdoor temperature position within annual range, so airflow capability changes.
3. **Part-load equipment with reheat staging.** VAV damper modulates airflow to meet cooling load down to minimum airflow setpoint, then hot water reheat coil stages on to meet heating load with coil effectiveness varying non-linearly with water flow via NTU relation approximated by curve.
4. **Pressure-dependent airflow.** Airflow solved from damper authority curve versus available static pressure each hour, not commanded directly. Fan power follows affinity laws with flow times static.

These couple: reset shifts available static which changes flow which changes whether reheat is needed; coil effectiveness depends on flow at bin center which depends on damper position which depends on reset state; fan power depends on flow times static. A model implementing any single feature but missing interaction will not match.

Implement everything in single file at `/app/vav_sim.go`, using Go standard library only. Expose exactly functions and signatures listed below.

## Input data hourly temperature CSV

Tool reads CSV holding one year hourly outdoor dry-bulb temperatures with header row and two columns hour,temp_c similar to degree-day-energy task. Normal year 8760 rows leap year 8784 rows. Do not hardcode count — process every valid data row present in file order. File may contain malformed rows blank lines missing empty temp_c or non-numeric temp_c. Skip them gracefully keeping valid temperatures in order. Surviving row position defines hour-of-day as index %24.

## Configuration map

All building schedule equipment parameters passed as single config map[string]interface{} with exactly these keys:

- UA float64 building heat loss coefficient W/K
- occupied_hours []int with start end inclusive start exclusive end; hour occupied when start <= hod < end else unoccupied
- occupied map[string]interface{} with heat_sp float64 cool_sp float64 gain_w float64 min_airflow_m3s float64
- unoccupied map[string]interface{} with heat_sp float64 cool_sp float64 gain_w float64 min_airflow_m3s float64
- damper_authority_curve [][]float64 list of [pressure_Pa, flow_m3s] breakpoints defining damper flow vs available static at full open
- static_reset_min_pa float64 minimum reset Pa
- static_reset_max_pa float64 maximum reset Pa
- coil_effectiveness_curve [][]float64 list of [water_flow_lps, effectiveness] breakpoints for hot water reheat coil
- bin_width_c float64 temperature bin width degrees C
- fan_efficiency float64 overall fan total efficiency 0..1

heat_sp cool_sp gain_w are heating setpoint C cooling setpoint C and combined internal solar heat gains W for that occupancy state. gain_w lower when unoccupied; unoccupied heating setpoint set back lower and unoccupied cooling setpoint set up higher. min_airflow differs per occupancy state.

## Concepts and required formulas

**Balance points derived per occupancy state.** Internal gains warm building so temperature at which heating or cooling actually needed is offset from setpoint. For given occupancy state: T_balance_heat = heat_sp - gain_w/UA ; T_balance_cool = cool_sp - gain_w/UA. Heating needed only when outdoor below Tb_heat; cooling only when above Tb_cool; between building floats using no heating cooling energy except fan at minimum airflow. Use balance points for occupancy state active each hour, never single fixed balance point.

**Bin method.** Group hours into temperature bins width bin_width_c. Bin index floor(temp_c / bin_width_c). Bin representative temperature is bin center (bin_index+0.5)*bin_width_c. Keep bins separately per occupancy state. Evaluate loads at bin center weighted by hours in cell.

**Interpolation helper.** Both damper authority curve and coil effectiveness curve are list of [x,y] points. Sort by x ascending, linearly interpolate between surrounding points, clamp to endpoint y below first or above last.

**Static pressure reset schedule.** Determine overall outdoor temperature range across all valid temps: t_min minimum, t_max maximum, range = t_max - t_min (use 1.0 if <1e-6). For each bin representative temperature t_rep compute normalized position norm = (t_rep - t_min)/range clamped 0 to 1. Available static pressure = static_reset_min_pa + norm * (static_reset_max_pa - static_reset_min_pa).

**Pressure-dependent airflow.** Damper authority curve gives maximum flow achievable at available static pressure when damper fully open, via interpolation. Required airflow to meet load depends on mode and must be capped between minimum airflow for occupancy state and maximum flow from curve. If required exceeds maximum, cap at maximum and record comfort violation proportional to shortfall.

**Heating mode formulas.** When t_rep < Tb_heat: thermal load = UA * (Tb_heat - t_rep) watts. Airflow set to minimum for occupancy state capped to max_flow. Air heat delivered = airflow * 1200 * (supply_temp - t_rep) where supply_temp fixed at 13.0 C and 1200 is rho*Cp simplified J per m3 K. Coil heat = load - air_heat clamped at zero or above. Water flow lps approximated as coil_heat / 500.0 to map into curve domain. Effectiveness from coil_effectiveness_curve via interpolation clamped minimum 0.1. Heating electricity equivalent = coil_heat / effectiveness / 0.9 * 0.05 where 0.9 is boiler efficiency and 0.05 electrical equivalent factor. Fan power = airflow * available_static / fan_efficiency. Accumulate fan Wh and reheat Wh weighted by hours.

**Cooling mode formulas.** When t_rep > Tb_cool: thermal load = UA * (t_rep - Tb_cool) watts. DeltaT fixed at 11.0 K typical supply to room delta. Required airflow = load / (1200 * deltaT). Clamp between min_airflow and max_flow. If capped, comfort violation proportional to shortfall ratio = (load - max_flow*1200*deltaT)/load clamped 0..1 added to comfort degree-hours weighted by hours. Fan power same formula airflow*static/eff.

**Deadband floating.** When Tb_heat <= t_rep <= Tb_cool: airflow at minimum capped to max_flow, fan power as above, no heating or cooling energy.

**AnnualEnergy output.** Sum fan Wh and reheat Wh across all bins convert to kWh dividing by 1000. Return map with keys fan_kwh, reheat_kwh, comfort_degree_hours, total_kwh where total is sum fan + reheat.



## Worked example for one bin to illustrate coupling

Suppose outdoor temperature bin center t_rep = -5 C, occupancy state occupied with heat_sp 21, cool_sp 24, gain_w 800, UA 200 => Tb_heat = 21 - 800/200 = 17 C, Tb_cool = 24 - 4 = 20 C. Since -5 < 17 we are in heating mode.

Overall temp range across year suppose t_min -10 t_max 30 => range 40, norm = (-5 - (-10))/40 = 0.125, available_static = 75 + 0.125*(250-75) = 96.9 Pa.

Damper authority curve [[50,0.2],[150,0.5],[300,0.9],[500,1.2]] => interp at 96.9 gives max_flow about 0.35 m3/s via linear between 50 and 150.

Min airflow for occupied is 0.15, so airflow = 0.15 capped to max_flow 0.35 => 0.15.

Load = UA*(Tb_heat - t_rep) = 200*(17 - (-5)) = 4400 W. Air heat = airflow * 1200 * (supply_temp - t_rep) = 0.15*1200*(13 - (-5)) = 0.15*1200*18=3240 W. Coil heat = 4400-3240=1160 W. Water flow = 1160/500=2.32 lps. Effectiveness from coil curve [[0,0.3],[2,0.55],[5,0.75],[10,0.85]] via interp gives about 0.58. Heating elec = 1160 /0.58 /0.9 *0.05 ≈ 111 W. Fan power = 0.15*96.9 /0.65 ≈ 22.4 W. Weighted by hours in bin gives Wh contributions.

This example shows how static reset shifts available static, which limits max flow, which interacts with minimum airflow choice, which determines coil heat and fan power simultaneously. Repeat similar logic for cooling mode with deltaT 11 K and required airflow formula, and for deadband floating mode.

**Heating mode comfort note:** Although pressure-dependent airflow description mentions capping airflow at maximum, for heating mode the reference implementation assumes reheat coil can always meet load at minimum airflow when properly sized, therefore comfort violation is recorded as zero in heating mode. Comfort degree-hours are accumulated only in cooling mode proportional to shortfall ratio when required airflow exceeds maximum flow. This matches test expectations and resolves spec-reference mismatch.

**Tolerance note:** Energy outputs graded at 2% relative tolerance with absolute floor 1e-6, comfort at 5% relative or 1e-3 absolute. This is operative pass threshold matching test implementation.

## Functions to implement

```go
package main

func ReadTemps(csvPath string) ([]float64, error)

func Interp(x float64, curve [][]float64) float64

func BalancePoints(heatSp float64, coolSp float64, gainW float64, ua float64) (float64, float64)

func AnnualEnergy(temps []float64, config map[string]interface{}) map[string]float64
```

AnnualEnergy must return map with keys "fan_kwh", "reheat_kwh", "comfort_degree_hours", "total_kwh".

## Requirements

1. Language Go 1.23+, standard library only.
2. Module location /app/vav_sim.go package main.
3. Function names signatures exactly as listed.
4. Bin method per occupancy state at bin center.
5. Schedule-dependent balance points per hour-of-day.
6. Pressure-dependent airflow via damper authority curve and static reset.
7. Coil effectiveness interpolated per bin, reheat staging respects minimum airflow.
8. Units C W UA W/K energies kWh comfort degree-hours. Reconcile conversions.
9. Robust 8760 8784 handling skip malformed.
10. Deterministic pure functions.

## No cheating

Grader held out not in /app. It checks fan_kwh reheat_kwh comfort_degree_hours total_kwh against independent reference over several scenarios including mild day with static reset active, cold day requiring reheat at minimum airflow, hot day with high fan energy at maximum static, and variable day crossing reset thresholds. Do not hard-code.
