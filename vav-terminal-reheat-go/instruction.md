# VAV Terminal with Reheat Coil and Static Pressure Reset

You will implement a pure-Go numerical model of a VAV terminal unit serving a single zone in a commercial building with variable air volume system, pressure-dependent airflow, hot water reheat coil staging, and duct static pressure reset.

Unlike simple bin method accumulation, answer here depends on four features that interact, and getting any one coupling wrong drifts result past tight 1% tolerance:

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

## Balance points derived per occupancy state

Internal gains warm building so temperature at which heating or cooling actually needed is offset from setpoint. For given occupancy state with setpoints heat_sp cool_sp and gains gain_w:

```
T_balance_heat = heat_sp - gain_w / UA
T_balance_cool = cool_sp - gain_w / UA
```

gain_w / UA is temperature offset in kelvin. Heating needed only when outdoor temperature below Tb_heat; cooling only when above Tb_cool; between the two building floats and uses no heating cooling energy except fan at minimum airflow. Because occupied and unoccupied states have different setpoints gains and min airflow, balance points differ by hour-of-day — you must use balance points for occupancy state active each hour. Do not use raw setpoints and do not use single fixed balance point for whole year.

Pseudocode for BalancePoints function:
```
offset = gainW / ua
tb_heat = heatSp - offset
tb_cool = coolSp - offset
return tb_heat, tb_cool
```

## Interpolation helper

Both damper authority curve and coil effectiveness curve are list of [x,y] points sorted by x ascending but your code must sort to be safe. Interpolate linearly between surrounding points, clamp to endpoint y below first x or above last x.

Pseudocode for Interp(x, curve):
```
if len(curve)==0 return 0
sort curve by first element ascending
if x <= curve[0][0] return curve[0][1]
if x >= curve[last][0] return curve[last][1]
for i from 1 to len-1:
    x0,y0 = curve[i-1]
    x1,y1 = curve[i]
    if x <= x1:
        frac = (x - x0)/(x1 - x0)
        return y0 + frac*(y1-y0)
return last y
```

## ReadTemps function

Pseudocode:
```
open csvPath
read header row
find column index where lowercased trimmed header equals "temp_c", else fallback to 1
out = empty slice
for each remaining record:
    if index out of range continue
    s = trim space record[index]
    if empty continue
    parse float64, if error continue
    append to out
return out
```

## Bin method per occupancy state

Rather than accumulating over each raw hour group hours into temperature bins width bin_width_c. Use bin index floor(temp_c / bin_width_c) and let each bin representative temperature be bin center (bin_index+0.5)*bin_width_c. Bins must be kept separately per occupancy state because balance points gains and min airflow differ. Evaluate each cell loads and equipment at bin representative temperature weighted by number hours in that cell.

Pseudocode to build cells:
```
cells = map of (state string, bin int) to count int
for idx, t in enumerate temps:
    hod = idx % 24
    state = "occupied" if occupied_hours[0] <= hod < occupied_hours[1] else "unoccupied"
    b = floor(t / bin_width_c)
    cells[(state,b)] += 1
```

## Static pressure reset schedule

Determine overall outdoor temperature range across all valid temps: t_min = min temps, t_max = max temps, range = t_max - t_min (if <1e-6 use 1.0). For each bin representative temperature t_rep compute normalized position norm = (t_rep - t_min)/range clamped 0..1. Available static pressure for that bin:

```
available_static = static_reset_min_pa + norm * (static_reset_max_pa - static_reset_min_pa)
```

This means coldest outdoor gets minimum static, warmest gets maximum static, linear in between.

## Pressure-dependent airflow and damper authority

Damper authority curve gives maximum flow achievable at available static pressure when damper fully open. For each bin compute max_flow = Interp(available_static, damper_authority_curve).

Required airflow to meet load depends on mode:

Define rhoCp = 1200.0 J per m3 K simplified constant for this task. Supply air temperature fixed at 13.0 C for cooling mode calculations.

Heating mode when t_rep < Tb_heat:
  thermal load = UA * (Tb_heat - t_rep) watts
  airflow = min_airflow for that occupancy state (VAV minimum in heating)
  if airflow > max_flow then airflow = max_flow
  air_heat = airflow * rhoCp * (supply_temp - t_rep)
  coil_heat = load - air_heat
  if coil_heat < 0 then coil_heat = 0
  water_flow_lps = coil_heat / 500.0   // scaling to map into typical 0-10 lps curve domain
  effectiveness = Interp(water_flow_lps, coil_effectiveness_curve)
  if effectiveness < 0.1 then effectiveness = 0.1
  heating_elec_w = coil_heat / effectiveness / 0.9 * 0.05   // boiler efficiency 0.9 and electrical equivalent factor 0.05
  fan_power_w = airflow * available_static / fan_efficiency
  accumulate fan_wh += n_hours * fan_power_w ; reheat_wh += n_hours * heating_elec_w
  comfort assumed maintained (no violation) in heating when properly sized.

Cooling mode when t_rep > Tb_cool:
  thermal load = UA * (t_rep - Tb_cool) watts
  deltaT = 11.0   // typical supply to room delta for cooling
  required_air = load / (rhoCp * deltaT)
  if required_air < min_airflow then required_air = min_airflow
  if required_air > max_flow then
        required_air = max_flow
        shortfall_ratio = (load - max_flow*rhoCp*deltaT)/load clamped 0..1
        comfort_degree_hours += n_hours * shortfall_ratio * 1.0
  airflow = required_air
  fan_power_w = airflow * available_static / fan_efficiency
  fan_wh += n_hours * fan_power_w
  // no reheat in cooling, no mechanical cooling electricity counted separately per simplified spec focusing on air distribution side

Deadband floating when Tb_heat <= t_rep <= Tb_cool:
  airflow = min_airflow capped to max_flow
  fan_power_w = airflow * available_static / fan_efficiency
  fan_wh += n_hours * fan_power_w

## AnnualEnergy function

Pseudocode full:
```
func AnnualEnergy(temps []float64, config map[string]interface{}) map[string]float64 {
    ua = config["UA"].(float64)
    occ_hours = config["occupied_hours"].([]int)
    bw = config["bin_width_c"].(float64)
    fanEff = config["fan_efficiency"].(float64)
    dac = config["damper_authority_curve"].([][]float64)
    coil = config["coil_effectiveness_curve"].([][]float64)
    staticMin = config["static_reset_min_pa"].(float64)
    staticMax = config["static_reset_max_pa"].(float64)
    supplyTemp = 13.0
    rhoCp = 1200.0
    boilerEff = 0.9
    elecFactor = 0.05

    precompute balance points per state using BalancePoints()
    determine t_min t_max across temps compute range
    build cells map counting hours per (state,bin)

    fanWh=0 ; reheatWh=0 ; comfortDH=0
    for each cell key state bin count n:
        t_rep = (bin+0.5)*bw
        tb_heat, tb_cool = precomputed for state
        min_air = precomputed for state
        norm = clamp((t_rep - t_min)/range,0,1)
        available_static = staticMin + norm*(staticMax-staticMin)
        max_flow = Interp(available_static, dac)

        if t_rep < tb_heat:
            load = ua*(tb_heat - t_rep)
            airflow = min_air ; if airflow>max_flow airflow=max_flow
            air_heat = airflow*rhoCp*(supplyTemp - t_rep)
            coil_heat = load - air_heat ; if coil_heat<0 coil_heat=0
            water_flow = coil_heat/500.0
            eff = Interp(water_flow, coil); if eff<0.1 eff=0.1
            heating_elec = coil_heat / eff / boilerEff * elecFactor
            fan_power = airflow * available_static / fanEff
            fanWh += n*fan_power ; reheatWh += n*heating_elec
        else if t_rep > tb_cool:
            load = ua*(t_rep - tb_cool)
            deltaT=11.0
            required = load/(rhoCp*deltaT)
            if required < min_air required = min_air
            if required > max_flow:
                shortfall = (load - max_flow*rhoCp*deltaT)/load ; if shortfall<0 shortfall=0
                comfortDH += n*shortfall*1.0
                required = max_flow
            fan_power = required * available_static / fanEff
            fanWh += n*fan_power
        else:
            airflow = min_air ; if airflow>max_flow airflow=max_flow
            fan_power = airflow * available_static / fanEff
            fanWh += n*fan_power

    fan_kwh = fanWh/1000 ; reheat_kwh = reheatWh/1000 ; total = fan_kwh+reheat_kwh
    return map with keys "fan_kwh","reheat_kwh","comfort_degree_hours","total_kwh"
}
```

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

1. Language Go 1.23+, standard library only.
2. Module location /app/vav_sim.go package main.
3. Function names signatures exactly as listed.
4. Bin method accumulate over temperature bins per occupancy state evaluating at bin center not raw hour sum.
5. Schedule-dependent balance points use occupied or unoccupied according to hour-of-day never single fixed balance point.
6. Pressure-dependent airflow solved per bin via damper authority curve and available static from reset schedule never constant airflow.
7. Coil effectiveness interpolated per bin via curve reheat staging respects minimum airflow.
8. Units temperatures C gains W UA W/K energies kWh comfort degree-hours. Reconcile hour to energy and W to kW conversions.
9. Robust input handle 8760 and 8784 row files skip malformed rows hour-of-day derives from position within valid temperatures.
10. Deterministic pure functions same inputs same outputs no randomness wall-clock network.

## No cheating

Grader is held out not in /app and you will not see it during task. It imports your package and checks fan_kwh reheat_kwh comfort_degree_hours total_kwh against independent reference over several scenarios including mild day with static reset active, cold day requiring reheat at minimum airflow, hot day with high fan energy at maximum static, and variable day crossing reset thresholds. Do not attempt to detect special-case or hard-code grader inputs or expected outputs; solutions must implement model as specified for arbitrary inputs.
