# Fuel Fleet Analyzer - Multi-turn T-Bench Task

## Description

This is a 2-step `terminal_bench_multi_turn` task testing **context-following**. 

**Step 1** builds a reusable fuel calculator CLI at `/app/fuel_calc.py` that supports:
- mpg <-> L/100km conversions (formula 235.215)
- fuel needed = distance / mpg
- cost = fuel * price
- CLI with argparse handling both fuel calculation and unit conversion modes

**Step 2** reuses the same CLI built in step 1 to analyze fleet data with variable gas prices. The agent must:
- Read vehicles.json (mpg per vehicle), trips.csv (25 trips across 3 vehicles), fuel_prices.csv (sparse dates)
- Implement most-recent-<= price lookup (realistic, not exact match)
- Import and use functions from fuel_calc.py (must not re-implement formulas)
- Aggregate per vehicle and generate /app/report.json with per_vehicle totals, fleet_total_cost, and most_inefficient_vehicle

Why naive approach fails:
- Step 1 if agent hardcodes outputs or forgets to make file executable, step 2 will fail because fuel_calc.py missing
- Step 2 if agent hardcodes report.json or uses exact price match instead of most-recent-<= lookup, cost totals will be off by ~$10-15
- If agent does both steps in step 1 (over-execution), negative tests in step 1 will fail and block progress
- If agent rewrites fuel_calc.py in step 2 and breaks step 1 API, step 2 tests still check fuel_calc remains usable

## Completion Rates

| Model | Step | Pass Rate (of trials reaching this step) | Last Updated |
|---|---|---|---|
| Oracle | 1_build_calculator | 3/3 | 2026-07-22, iter 1 |
| Oracle | 2_fleet_report | 3/3 | 2026-07-22, iter 1 |
| meta/avocado | 1_build_calculator | TBD | - |
| meta/avocado | 2_fleet_report | TBD | - |
| anthropic/claude-sonnet-4-6 | 1_build_calculator | TBD | - |
| anthropic/claude-sonnet-4-6 | 2_fleet_report | TBD | - |
| anthropic/claude-opus-4-6 | 1_build_calculator | TBD | - |
| anthropic/claude-opus-4-6 | 2_fleet_report | TBD | - |

Cascade verdict: GOOD expected - each reached step independently filters trials. Step1 easy (CLI), Step2 harder (date lookup + reuse).

Local manual test: 15/15 passed step1, 13/13 passed step2

## Model Analysis

TBD after running:
- `codimango bench run -p fuel-fleet-analyzer -a oracle -k 3`
- `codimango bench run -p fuel-fleet-analyzer -a metacode -m meta/avocado_dvsc_tester -k 5`
- `codimango bench run -p fuel-fleet-analyzer -a claude-code -m claude-sonnet-4-6 -k 5`
- `codimango bench run -p fuel-fleet-analyzer -a claude-code -m claude-opus-4-6 -k 5`

Expected failure modes:
- Step1: model forgets chmod +x, or conversion formula inverted (235.215 wrong), or output format not exactly 2 decimals
- Step2: model doesn't import fuel_calc, implements fuel = distance * mpg (wrong), uses exact price match leading to missing price error, forgets rounding, or hardcodes report that passes schema but fails numeric tolerance

## Anti-Cheating Analysis

- Hardcoded outputs: Step2 tests recompute expected report from CSVs independently (compute_expected()) and compare with tolerance, not exact file hash. Hardcoded values would need to match dynamic computation which requires correct price lookup logic.
- Overfitting to visible tests: No visible tests - tests hidden in /tests/. Agent only sees data files.
- Modifying test files: Tests run in verifier container at /tests/, not writable by agent in normal flow. Reward file at /logs/verifier.
- Bypassing intended path: Step2 tests check fuel_calc.py still exists and its functions work after step2, and heuristic checks that some .py file in /app imports fuel_calc. CLI reuse via subprocess also valid.
- Over-execution: Step1 includes negative tests asserting /app/report.json and fleet_total_cost artifacts do NOT exist after step1, preventing agent from solving both steps at once.
