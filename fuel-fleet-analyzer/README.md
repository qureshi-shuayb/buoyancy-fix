# Fuel Fleet Analyzer - Multi-turn T-Bench Task (Hard)

## Description

This is a 2-step `terminal_bench_multi_turn` task testing **context-following** with significantly hardened difficulty (v2).

**Step 1** builds an advanced reusable fuel calculator CLI at `/app/fuel_calc.py` that supports:
- 12 importable functions: mpg<->L/100km, miles<->km, gallons<->liters, mpg->kmpl, cargo-adjusted fuel (`factor=1+cargo*0.0005`), CO2 emissions (gasoline 8.887 kg/gal, diesel 10.21), cost with tax
- Subcommands via argparse subparsers: `convert` (supports mpg,l100km,kmpl,miles,km,gallons,liters), `calc` (--distance, --mpg, --price, --cargo, --fuel-type, --tax-rate, --output-format json/text), `co2` (--fuel, --fuel-type)
- Text and JSON output modes, docstrings, type hints, error handling

**Step 2** reuses the same CLI built in step 1 to analyze fleet data with variable fuel-type-specific prices, cargo penalties, tax, CO2, monthly aggregation. The agent must:
- Read vehicles.json (mpg, fuel_type gasoline/diesel, cargo_capacity_kg per vehicle), trips.csv (36 trips across 3 vehicles, includes cargo_kg, includes fallback trip 2023-12-31 before first price), fuel_prices.csv (12 rows: 6 dates x2 fuel types, columns date,fuel_type,price_per_gallon,tax_rate, gasoline vs diesel prices differ)
- Implement 2D most-recent-<= price lookup: price.date <= trip.date AND price.fuel_type == vehicle.fuel_type, fallback to first price of that fuel_type
- Cargo handling: cap cargo to vehicle capacity for penalty, penalty formula must use fuel_calc.calculate_fuel_needed_with_cargo (0.05% per kg, 200kg=10% extra)
- Import and use at least 3 advanced functions from fuel_calc.py: `calculate_fuel_needed_with_cargo`, `calculate_co2_emissions`, `calculate_cost_with_tax` plus base `calculate_fuel_needed` and `calculate_cost` (AST + string strict check)
- Aggregate per vehicle: total_miles, total_fuel_gallons (base), total_fuel_adjusted (cargo), total_cost, total_cost_with_tax, total_co2_kg, avg_mpg, avg_cost_per_mile, total_cargo_kg, trip_count, monthly_breakdown {YYYY-MM: {miles,fuel,cost,cost_with_tax,co2,cargo,trip_count}}
- Fleet totals: fleet_total_cost, fleet_total_cost_with_tax, fleet_total_fuel_gallons, fleet_total_co2_kg, most_inefficient_vehicle (max fuel_adjusted/mile), most_expensive_vehicle, highest_co2_vehicle, most_expensive_month, monthly_totals, fuel_type_breakdown
- Generate /app/report.json with expanded schema (per_vehicle + fleet nested object) plus backward compat top-level keys

Why naive approach fails (now much harder):
- Step 1: Agent must implement 12 functions with correct formulas and ValueError handling, plus 3 subcommands with subparsers, json/text output modes, cargo/tax/fuel_type handling. Forgetting chmod +x, missing docstring, wrong conversion (1.60934, 3.78541, 0.425144), or not handling same-unit echo, cargo penalty (0.0005 factor), CO2 factors (8.887 vs 10.21), tax (0-1 range) causes failure. Flat flags only won't pass new subcommand tests.
- Step 2: Agent must handle 2D price lookup (date <= AND fuel_type match) - exact match or ignoring fuel_type fails (gasoline $3.52 vs diesel $4.05 on 2024-01-04). Must handle fallback 2023-12-31 per fuel_type (gasoline 3.45 vs diesel 3.95). Must cap cargo to capacity, use fuel_calc functions for cargo-adjusted fuel (not manual multiplication), CO2, tax-inclusive cost. Must do monthly grouping (YYYY-MM) and fuel_type breakdown. Hardcoded report fails because tests recompute expected dynamically from CSVs with tolerance. Reuse check now strict: requires at least 3 advanced functions referenced via AST/string scan, otherwise REUSE CHECK FAILED.
- Over-execution: Step1 negative tests assert /app/report.json does NOT exist after step1
- Context: Step2 checks fuel_calc.py still exists and all 12 functions work after step2

## Completion Rates (Hard v2)

| Model | Step | Pass Rate (of trials reaching this step) | Last Updated |
|---|---|---|---|
| Oracle | 1_build_calculator | 3/3 | 2026-07-22, iter 2 hard |
| Oracle | 2_fleet_report | 3/3 | 2026-07-22, iter 2 hard |
| meta/avocado | 1_build_calculator | TBD - expected 40-60% (harder) | - |
| meta/avocado | 2_fleet_report | TBD - expected 20-40% (much harder) | - |
| anthropic/claude-sonnet-4-6 | 1_build_calculator | TBD | - |
| anthropic/claude-sonnet-4-6 | 2_fleet_report | TBD | - |
| anthropic/claude-opus-4-6 | 1_build_calculator | TBD | - |
| anthropic/claude-opus-4-6 | 2_fleet_report | TBD | - |

Cascade verdict: GOOD expected - each reached step independently filters trials. Step1 now hard (12 funcs + subparsers), Step2 much harder (2D price lookup + cargo + CO2 + tax + monthly + fuel_type breakdown + strict 3-func reuse).

Local manual test (hard v2): 35/35 passed step1, 25/25 passed step2

## Model Analysis (Hard v2)

TBD after running:
- `codimango bench run -p fuel-fleet-analyzer -a oracle -k 3`
- `codimango bench run -p fuel-fleet-analyzer -a metacode -m meta/avocado_dvsc_tester -k 5`
- `codimango bench run -p fuel-fleet-analyzer -a claude-code -m claude-sonnet-4-6 -k 5`
- `codimango bench run -p fuel-fleet-analyzer -a claude-code -m claude-opus-4-6 -k 5`

Expected failure modes (Hard v2):
- Step1: model forgets subparsers required, implements flat flags only; missing miles_to_km (1.60934) or gallons_to_liters (3.78541) or mpg_to_kmpl (0.425144); cargo formula wrong (not 0.0005 factor, e.g., uses 0.02 per 100kg without threshold); CO2 factors inverted (uses 8.887 for diesel); tax_rate validation missing (allows >1); json output not rounded to 2 decimals or missing keys; help doesn't mention convert/calc/co2; docstrings missing
- Step2: model doesn't import fuel_calc with 3 advanced funcs (only uses base distance/mpg manually); uses exact price match instead of most-recent-<= per fuel_type; ignores fuel_type (uses gasoline price for diesel vehicles, off by $0.5/gal); ignores cargo penalty (fuel_adjusted == fuel_base); ignores tax (cost_with_tax == cost); doesn't cap cargo to capacity; doesn't do monthly_breakdown (YYYY-MM grouping); doesn't do fuel_type_breakdown; hardcodes report with old totals (816 miles etc) that fail new schema; breaks fuel_calc.py subcommands so step2 reuse fails

## Anti-Cheating Analysis (Hard v2)

- Hardcoded outputs: Step2 tests recompute expected report from CSVs independently via compute_expected() that handles 2D price lookup per fuel_type, cargo penalty (0.0005 factor), tax, CO2 (8.887/10.21), monthly grouping, fuel_type breakdown. Comparison with tolerance 0.1-0.5, not exact hash. Hardcoded values must match dynamic computation which requires correct cargo, fuel_type, tax logic.
- Overfitting to visible tests: No visible tests - tests hidden in /tests/. Agent only sees data files. Data files now larger (36 trips, 12 prices) with differing gasoline vs diesel prices to prevent guessing.
- Modifying test files: Tests run in verifier container at /tests/, not writable by agent. Reward at /logs/verifier.
- Bypassing intended path: Step2 strict reuse check via AST: scans /app/*.py (excluding fuel_calc.py) for import of fuel_calc and usage of at least 3 advanced functions (calculate_fuel_needed_with_cargo, calculate_co2_emissions, calculate_cost_with_tax) plus base functions, OR subprocess calling fuel_calc.py with subcommands calc/co2. Fails with message listing checked files and missing funcs if not found. Also checks fuel_calc still exists and all 12 funcs work after step2.
- Over-execution: Step1 includes negative tests asserting /app/report.json, fleet_report.json, costs.json do NOT exist after step1, preventing solving both steps at once.
- Cargo penalty cheat: Test cargo_adjusted_fuel_greater_than_base asserts total_fuel_adjusted >= total_fuel_gallons, and per-trip cargo increases fuel by expected 10% @200kg. Manual multiplication without calling fuel_calc function fails reuse check.
- CO2 and tax cheat: Tests co2_diesel_vs_gasoline_factor, cost_with_tax_includes_tax check that diesel CO2 factor > gasoline and tax adds cost. Ignoring these makes tests fail.
