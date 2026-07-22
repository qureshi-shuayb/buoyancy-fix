# Step 2 - Fleet Fuel Cost Report Using Your Calculator from Step 1

## Context

In Step 1 you built an executable fuel calculator CLI at `/app/fuel_calc.py`. This step runs in the **same session** (`inherit_prior_session = true`), so `/app/fuel_calc.py` still exists and must remain usable.

You must **reuse** your calculator from Step 1. Do not re-implement the fuel formulas (`distance / mpg`, `fuel * price`) with hardcoded math in this step. Instead, import functions from `fuel_calc.py` or call it via subprocess. The verifier checks that `fuel_calc.py` still exists after this step and that its functions work.

## Data Files (shared in environment)

All files are provided in the container under `/app/data/` (copied from `environment/data/` in the Dockerfile):

- `/app/data/vehicles.json`: List of vehicles.
  ```json
  [
    {"id": "V001", "make": "Ford Transit", "mpg": 22.5},
    {"id": "V002", "make": "Mercedes Sprinter", "mpg": 18.0},
    {"id": "V003", "make": "RAM ProMaster", "mpg": 15.2}
  ]
  ```
- `/app/data/trips.csv`: Trip log with header `vehicle_id,date,miles`
  ```
  vehicle_id,date,miles
  V001,2024-01-02,120.5
  V001,2024-01-03,85.0
  V001,2023-12-31,50.0   # edge: before first price
  ...
  ```
  26 trips total across 3 vehicles, including one before first price date (2023-12-31) to test fallback, dates in `YYYY-MM-DD` format.

- `/app/data/fuel_prices.csv`: Sparse daily fuel prices with header `date,price_per_gallon`
  ```
  date,price_per_gallon
  2024-01-01,3.45
  2024-01-03,3.52
  2024-01-06,3.60
  2024-01-08,3.55
  2024-01-11,3.70
  2024-01-13,3.65
  ```
  Only 6 price entries for a 15-day window.

## Task

Generate a fleet fuel cost report at `/app/report.json` by combining the three data sources and reusing your `fuel_calc.py`.

### Price Lookup Rule (Critical)

Fuel price for a trip is **NOT** an exact date match. The prices are sparse, so you must implement **most-recent-price <= trip date** logic:

- Sort `fuel_prices.csv` by date ascending.
- For a given trip date `T`, find the latest price entry where `price.date <= T`.
- If `T` is before the first price entry, use the first price (fallback).
- Example: Trip on `2024-01-04` must use price from `2024-01-03` (3.52), because `2024-01-04` has no entry. Trip on `2024-01-02` uses `2024-01-01` (3.45). Trip on `2023-12-31` is before first price 2024-01-01, so must use 2024-01-01 price $3.45 (fallback case).

Using exact-match lookup or forward-fill will cause cost totals to be off by $10-15 and fail tests.

### Calculation Steps

1. **Load vehicles**: Parse `/app/data/vehicles.json` into dict `id -> {make, mpg}`.
2. **Load prices**: Parse `/app/data/fuel_prices.csv`, parse dates, sort ascending by date.
3. **Process trips**: For each row in `/app/data/trips.csv`:
   - Lookup `mpg = vehicles[vehicle_id].mpg`
   - Lookup `price = get_price_for_date(trip_date)` using most-recent <= rule
   - Compute **using functions from fuel_calc.py**:
     ```python
     import importlib.util
     spec = importlib.util.spec_from_file_location("fuel_calc", "/app/fuel_calc.py")
     fuel_calc = importlib.util.module_from_spec(spec)
     spec.loader.exec_module(fuel_calc)

     fuel = fuel_calc.calculate_fuel_needed(miles, mpg)
     cost = fuel_calc.calculate_cost(fuel, price)
     ```
     You may also call the CLI via `subprocess` if you prefer, but import is recommended.
4. **Aggregate per vehicle**:
   - `total_miles` = sum of miles per vehicle
   - `total_fuel_gallons` = sum of fuel per vehicle
   - `total_cost` = sum of cost per vehicle
   - Round each aggregated value to 2 decimals **after** summing (not per-trip rounding).
5. **Compute fleet totals**:
   - `fleet_total_cost` = sum of all per-vehicle `total_cost`, rounded to 2 decimals
   - `most_inefficient_vehicle` = vehicle ID with highest `total_fuel_gallons / total_miles` ratio. This is equivalent to lowest mpg in this dataset, expected to be `V003` (15.2 mpg), but you must compute it from the aggregated data, not hardcode.
6. **Write output**: Create `/app/report.json` with exact schema below.

### Output File: `/app/report.json`

Write JSON with this exact structure (values shown are expected for current dataset with 26 trips including fallback edge):

```json
{
  "per_vehicle": {
    "V001": {"total_miles": 866.5, "total_fuel_gallons": 38.51, "total_cost": 137.15},
    "V002": {"total_miles": 1212.0, "total_fuel_gallons": 67.33, "total_cost": 240.19},
    "V003": {"total_miles": 1047.25, "total_fuel_gallons": 68.9, "total_cost": 247.59}
  },
  "fleet_total_cost": 624.93,
  "most_inefficient_vehicle": "V003"
}
```

Requirements for the output:
- Must be valid JSON, pretty-printed is okay
- `per_vehicle` must contain 3 keys: `V001`, `V002`, `V003`
- Each per-vehicle entry must have `total_miles`, `total_fuel_gallons`, `total_cost` as floats rounded to 2 decimals
- `fleet_total_cost` is a float rounded to 2 decimals
- `most_inefficient_vehicle` is a string vehicle ID
- File must be at exactly `/app/report.json`

### Reuse Requirement (Anti-Cheat)

- **Must reuse** `/app/fuel_calc.py`. Tests will:
  - Check `/app/fuel_calc.py` still exists and its functions `calculate_fuel_needed` and `calculate_cost` return correct values
  - Heuristically search `/app/*.py` for import of `fuel_calc` or string `fuel_calc` to ensure reuse (CLI subprocess usage also valid)
  - Recompute expected report independently from CSVs; if you hardcode values without correct price lookup logic, totals will mismatch
- You may create helper scripts like `/app/generate_report.py` that import `fuel_calc.py`.

### Constraints / Do NOT Do

- Do **NOT** modify `/app/fuel_calc.py` in a way that breaks its Step 1 contract (functions `mpg_to_l_per_100km`, `l_per_100km_to_mpg`, `calculate_fuel_needed`, `calculate_cost` and CLI `--distance`, `--from-unit`, `--help` must still work)
- Do **NOT** hardcode report values. Tests recompute expected dynamically; hardcoded output that doesn't follow most-recent <= price lookup will fail tolerance checks
- Do **NOT** use exact price matching. Implement the most-recent <= logic
- Use only Python standard library (no pip installs needed for this step)
- Handle rounding consistently: final aggregates rounded to 2 decimals

## Verification

You can verify locally:

```bash
cat /app/report.json
python3 -c "import json; print(json.load(open('/app/report.json')))"
python3 /app/fuel_calc.py --distance 100 --mpg 25 --price 3.5
```

Tests in `/tests/test_outputs.py` check:
- `report.json` exists and is valid JSON with required keys
- **Strict reuse check (AST + string):** At least one `/app/*.py` (excluding `fuel_calc.py`) must import or invoke `fuel_calc.py` via `importlib` or `subprocess` + usage of `calculate_fuel_needed` / `calculate_cost`. Test name `test_report_uses_fuel_calc_import` will fail with clear message if not found.
- Per-vehicle `total_miles`, `total_fuel_gallons`, `total_cost` within 0.05-0.10 tolerance of oracle recomputation
- `fleet_total_cost` within 0.15 tolerance
- `most_inefficient_vehicle == V003` (computed via max fuel/mile ratio)
- Price lookup uses most-recent <= logic:
  - Dedicated test `test_price_lookup_2024_01_04_must_use_3_52_exact_failure_message` asserts trip on 2024-01-04 must use 2024-01-03 price $3.52, with failure message "PRICE LOOKUP FAILED: Trip on 2024-01-04 must use price from 2024-01-03 ($3.52) as most recent <=."
  - Fallback test `test_price_lookup_fallback_before_first_price` asserts trip on 2023-12-31 must use first price $3.45
- `fuel_calc.py` still usable
- Rounding to 2 decimals
- Totals > 0 sanity check

Failure modes to avoid:
- Using `fuel = distance * mpg` instead of `distance / mpg`
- Using exact price match leading to missing prices or zero cost
- Rounding per-trip instead of after aggregation (causes drift > tolerance)
- Breaking Step 1 file so Step 2 reuse fails
