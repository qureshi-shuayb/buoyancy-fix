# Step 2 - Advanced Fleet Fuel Cost & CO2 Report Using Your Calculator from Step 1 (Hard)

**Context:** In Step 1 you built `/app/fuel_calc.py` with 12 functions and subcommands `convert`, `calc`, `co2`. This step runs in the **same session** (`inherit_prior_session = true`), so `/app/fuel_calc.py` still exists and must remain usable. You must **reuse** at least 3 functions from it: `calculate_fuel_needed_with_cargo`, `calculate_co2_emissions`, `calculate_cost_with_tax` (plus original fuel_needed/cost). Do not re-implement formulas manually.

## Data Files (shared in environment)

All files are provided under `/app/data/` (copied from `environment/data/`):

- `/app/data/vehicles.json`: List with fuel_type and cargo capacity
  ```json
  [
    {"id": "V001", "make": "Ford Transit", "mpg": 22.5, "fuel_type": "gasoline", "cargo_capacity_kg": 1500},
    {"id": "V002", "make": "Mercedes Sprinter", "mpg": 18.0, "fuel_type": "diesel", "cargo_capacity_kg": 2000},
    {"id": "V003", "make": "RAM ProMaster", "mpg": 15.2, "fuel_type": "diesel", "cargo_capacity_kg": 1800}
  ]
  ```

- `/app/data/trips.csv`: Trip log with cargo
  ```
  vehicle_id,date,miles,cargo_kg
  V001,2023-12-31,50.0,100
  V001,2024-01-02,120.5,250
  V002,2024-01-04,150.75,600
  ...
  ```
  36 trips total, including one before first price date (2023-12-31) to test fallback. Columns: vehicle_id,date(YYYY-MM-DD),miles,cargo_kg

- `/app/data/fuel_prices.csv`: Fuel-type-specific sparse prices with tax
  ```
  date,fuel_type,price_per_gallon,tax_rate
  2024-01-01,gasoline,3.45,0.08
  2024-01-01,diesel,3.95,0.08
  2024-01-03,gasoline,3.52,0.08
  2024-01-03,diesel,4.05,0.08
  ...
  ```
  12 rows: 6 dates x2 fuel types. Prices differ gasoline vs diesel to test fuel_type filtering. tax_rate 0.07-0.09

## Task

Generate advanced fleet report at `/app/report.json` by combining 3 data sources and reusing your `fuel_calc.py`.

### Price Lookup Rule (Critical - 2D: date AND fuel_type)

Fuel price for a trip is **most recent price where price.date <= trip.date AND price.fuel_type == vehicle.fuel_type**, sorted ascending by date.

- Sort fuel_prices.csv by date ascending.
- Filter to matching fuel_type (gasoline/diesel).
- For trip date T, find latest entry where price.date <= T with same fuel_type.
- If T before first price entry for that fuel_type, use first price of that fuel_type (fallback).
- Tax rate comes from same price row.

Examples:
- Trip V001 (gasoline) on 2024-01-04 must use gasoline price from 2024-01-03 $3.52 tax 0.08 (no 2024-01-04 entry)
- Trip V002 (diesel) on 2024-01-04 must use diesel price from 2024-01-03 $4.05 tax 0.08
- Trip on 2023-12-31 (before first price) must use first price of its fuel_type: gasoline 2024-01-01 $3.45, diesel 2024-01-01 $3.95

Using exact-match date OR ignoring fuel_type will cause costs off by $20-40 and fail.

### Cargo Handling (Critical)

- Each trip has cargo_kg.
- Vehicle has cargo_capacity_kg. If cargo_kg > capacity, **cap** cargo to capacity for fuel penalty calculation (but still count trip miles/cargo as given for totals? For simplicity, use capped cargo for fuel penalty, but totals use actual cargo_kg for cargo sum).
- Fuel penalty formula **must use** `fuel_calc.calculate_fuel_needed_with_cargo(distance, mpg, cargo_kg)` which implements factor `1 + max(0,cargo)*0.0005`.

### Calculation Steps (must use fuel_calc functions)

1. **Load vehicles:** dict id -> {mpg, fuel_type, cargo_capacity_kg}
2. **Load prices:** Parse fuel_prices.csv, parse dates, group by fuel_type, sort each group ascending by date. Keep list of tuples (date, price, tax_rate) per fuel_type.
3. **Define get_price_for_date(trip_date, fuel_type):** 
   - prices = fuel_type_prices[fuel_type] sorted ascending
   - Find latest price <= trip_date for that fuel_type, else fallback first
   - Return (price, tax_rate)
4. **Process trips:** For each row:
   - vid, date, miles, cargo_kg
   - Lookup vehicle mpg, fuel_type, capacity
   - Cap cargo for penalty: `cargo_for_calc = min(cargo_kg, capacity)`
   - Lookup price, tax_rate = get_price_for_date(date, fuel_type)
   - **Must use fuel_calc:**
     - `fuel_base = fuel_calc.calculate_fuel_needed(miles, mpg)`
     - `fuel_adj = fuel_calc.calculate_fuel_needed_with_cargo(miles, mpg, cargo_for_calc)`
     - `cost = fuel_calc.calculate_cost(fuel_adj, price)` (without tax)
     - `cost_with_tax = fuel_calc.calculate_cost_with_tax(fuel_adj, price, tax_rate)`
     - `co2 = fuel_calc.calculate_co2_emissions(fuel_adj, fuel_type)`
   - Accumulate per vehicle.

5. **Aggregate per vehicle:**
   - total_miles = sum miles
   - total_fuel_gallons = sum fuel_base (without cargo penalty, for baseline)
   - total_fuel_adjusted = sum fuel_adj (with cargo)
   - total_cost = sum cost (without tax)
   - total_cost_with_tax = sum cost_with_tax
   - total_co2_kg = sum co2
   - total_cargo_kg = sum cargo_kg (actual, not capped, for reporting)
   - trip_count = count trips
   - avg_mpg = total_miles / total_fuel_adjusted if fuel>0
   - avg_cost_per_mile = total_cost_with_tax / total_miles if miles>0
   - monthly_breakdown: key YYYY-MM -> {miles, fuel_gallons (adjusted), cost (without tax), cost_with_tax, co2_kg, cargo_kg, trip_count}
   - Round all final floats to 2 decimals after summing (not per-trip rounding)

6. **Fleet totals & analytics:**
   - fleet_total_cost = sum per_vehicle total_cost
   - fleet_total_cost_with_tax = sum per_vehicle total_cost_with_tax
   - fleet_total_fuel_gallons = sum total_fuel_adjusted (or total_fuel_gallons? Use adjusted for realism)
   - fleet_total_co2_kg = sum total_co2_kg
   - monthly_totals: YYYY-MM -> {miles, fuel_gallons, cost, cost_with_tax, co2_kg, trip_count}
   - fuel_type_breakdown: fuel_type -> {miles, fuel_gallons, cost, cost_with_tax, co2_kg}
   - most_inefficient_vehicle = vehicle with highest fuel_adjusted/miles ratio (lowest effective mpg)
   - most_expensive_vehicle = max total_cost_with_tax
   - highest_co2_vehicle = max total_co2_kg
   - most_expensive_month = month YYYY-MM with highest cost_with_tax total
   - fleet avg_mpg = fleet miles / fleet fuel adjusted

7. **Write output**

### Output File: `/app/report.json`

Write JSON with exact expanded schema (values illustrative, recomputed by tests):

```json
{
  "per_vehicle": {
    "V001": {
      "total_miles": 1037.0,
      "total_fuel_gallons": 46.09,
      "total_fuel_adjusted": 53.12,
      "total_cost": 187.45,
      "total_cost_with_tax": 203.12,
      "total_co2_kg": 472.08,
      "avg_mpg": 19.52,
      "avg_cost_per_mile": 0.20,
      "trip_count": 11,
      "total_cargo_kg": 3450,
      "monthly_breakdown": {
        "2023-12": {"miles": 50, "fuel_gallons": 2.33, "cost": 8.04, "cost_with_tax": 8.68, "co2_kg": 20.71, "cargo_kg": 100, "trip_count": 1},
        "2024-01": {"miles": 987, "fuel_gallons": 50.79, "cost": ..., "cost_with_tax": ..., "co2_kg": ..., "cargo_kg": 3350, "trip_count": 10}
      }
    },
    "V002": {...},
    "V003": {...}
  },
  "fleet": {
    "fleet_total_cost": 850.0,
    "fleet_total_cost_with_tax": 920.5,
    "fleet_total_fuel_gallons": 180.0,
    "fleet_total_co2_kg": 1800.0,
    "most_inefficient_vehicle": "V003",
    "most_expensive_vehicle": "V002",
    "highest_co2_vehicle": "V003",
    "most_expensive_month": "2024-01",
    "monthly_totals": {
      "2023-12": {"miles": 50, "fuel_gallons": 2.33, "cost": 8.04, "cost_with_tax": 8.68, "co2_kg": 20.71, "trip_count": 1},
      "2024-01": {...}
    },
    "fuel_type_breakdown": {
      "gasoline": {"miles": 1037, "fuel_gallons": 53.12, "cost": 187.45, "cost_with_tax": 203.12, "co2_kg": 472.08},
      "diesel": {"miles": 2600, "fuel_gallons": 130, "cost": 540, "cost_with_tax": 585, "co2_kg": 1327.3}
    }
  },
  "fleet_total_cost": 850.0,
  "most_inefficient_vehicle": "V003"
}
```

Requirements:
- Must be valid JSON
- per_vehicle 3 keys V001-V003
- Each per_vehicle must have at least: total_miles, total_fuel_gallons, total_fuel_adjusted, total_cost, total_cost_with_tax, total_co2_kg, avg_mpg, avg_cost_per_mile, trip_count, total_cargo_kg, monthly_breakdown
- fleet must have: fleet_total_cost, fleet_total_cost_with_tax, fleet_total_fuel_gallons, fleet_total_co2_kg, most_inefficient_vehicle, most_expensive_vehicle, highest_co2_vehicle, most_expensive_month, monthly_totals, fuel_type_breakdown
- Keep backward compat top-level keys fleet_total_cost and most_inefficient_vehicle (aliases to fleet values)
- All floats rounded to 2 decimals
- File at exactly /app/report.json

### Reuse Requirement (Strict Anti-Cheat)

- **Must reuse** `/app/fuel_calc.py` with at least 3 advanced functions:
  - `calculate_fuel_needed_with_cargo`
  - `calculate_co2_emissions`
  - `calculate_cost_with_tax`
  - Plus original `calculate_fuel_needed` and `calculate_cost` (total 5)
- Tests will:
  - Check fuel_calc.py still exists and all 12 functions work
  - AST scan /app/*.py for import of fuel_calc and usage of those 5 function names, OR subprocess calling fuel_calc.py with calc/co2 subcommands
  - If fewer than 3 advanced functions found, fail REUSE CHECK with message listing missing functions
  - Recompute expected report independently from CSVs; hardcoded values without correct fuel_type price lookup, cargo penalty, tax, co2 will fail tolerance

You may create helper script `/app/generate_report.py` that imports fuel_calc.

### Constraints / Do NOT Do
- Do NOT modify fuel_calc.py to break Step1 contract (12 functions + subcommands convert/calc/co2 + help mentioning convert,calc,co2 and --distance must still work)
- Do NOT hardcode report - tests recompute expected dynamically
- Do NOT use exact price matching or ignore fuel_type - must implement most-recent <= per fuel_type + fallback
- Do NOT re-implement cargo penalty manually - must use fuel_calc.calculate_fuel_needed_with_cargo
- Use only stdlib

## Verification

Local:
```bash
cat /app/report.json | python3 -m json.tool
python3 /app/fuel_calc.py calc --distance 100 --mpg 25 --price 3.5 --cargo 200 --fuel-type diesel --tax-rate 0.08 --output-format json
```

Tests in `/tests/test_outputs.py` (22+):
- report exists, valid JSON, schema has per_vehicle 3, fleet with 10 keys, backward compat top-level keys
- fuel_calc still usable and all 12 funcs work
- Strict reuse: at least 3 advanced funcs referenced in /app/*.py
- Per-vehicle totals: miles, fuel, fuel_adjusted, cost, cost_with_tax, co2 within 0.1-0.2 tolerance
- Cargo adjusted fuel > base fuel for any cargo>0
- CO2 diesel factor 10.21 vs gasoline 8.887: diesel CO2 > gasoline for same fuel
- Cost with tax > cost without tax when tax>0
- Price lookup 2D: V001 gasoline on 2024-01-04 uses gasoline $3.52 (not diesel $4.05), V002 diesel on 2024-01-04 uses diesel $4.05
- Fallback: 2023-12-31 uses first price per fuel_type (gasoline 3.45, diesel 3.95)
- Monthly breakdown exists, has 2023-12 and 2024-01 keys, miles sum matches totals
- Fuel_type breakdown exists, gasoline and diesel keys
- most_inefficient_vehicle == V003 (lowest mpg 15.2 with cargo penalty)
- highest_co2_vehicle, most_expensive_month computed
- Rounding 2 decimals
- Totals >0 sanity

Failure modes:
- Using distance*mpg instead of /mpg
- Ignoring cargo penalty (fuel_adjusted == fuel_base)
- Ignoring fuel_type (using gasoline price for diesel)
- Ignoring tax (cost_with_tax == cost)
- Not capping cargo to capacity (fuel overestimated)
- Hardcoding report without CSVs
- Breaking fuel_calc.py subcommands
