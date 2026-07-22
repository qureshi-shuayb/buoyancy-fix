# Step 1 - Build Fuel Calculator CLI

You are working in a Linux terminal. Your task is to build a reusable fuel calculator CLI tool that will be reused in Step 2.

## Objective

Create an executable Python CLI tool at `/app/fuel_calc.py` that calculates fuel consumption and cost, and converts between fuel efficiency units (mpg and L/100km).

## Requirements

### File Location and Setup

- File must be at `/app/fuel_calc.py`
- Must be executable (`chmod +x /app/fuel_calc.py`) and runnable via `python3 /app/fuel_calc.py ...`
- Must use only Python standard library (no external pip packages)
- Must use `argparse` for CLI parsing
- Include shebang `#!/usr/bin/env python3`

### Functions (must be implemented and importable)

Implement these four functions in `/app/fuel_calc.py` so they can be imported by Step 2:

1. `mpg_to_l_per_100km(mpg: float) -> float`
   - Convert mpg to L/100km using formula `235.215 / mpg`
   - Raise `ValueError` if `mpg <= 0`
   - Example: `mpg_to_l_per_100km(23.5215)` ≈ `10.0`

2. `l_per_100km_to_mpg(l100: float) -> float`
   - Convert L/100km to mpg using `235.215 / l100`
   - Raise `ValueError` if `l100 <= 0`
   - Example: `l_per_100km_to_mpg(10.0)` ≈ `23.5215`
   - Roundtrip property must hold: `l_per_100km_to_mpg(mpg_to_l_per_100km(x)) ≈ x`

3. `calculate_fuel_needed(distance_miles: float, mpg: float) -> float`
   - Returns `distance_miles / mpg`
   - Raise `ValueError` if `mpg <= 0`
   - Example: `calculate_fuel_needed(100, 25)` = `4.0`

4. `calculate_cost(fuel_gallons: float, price_per_gallon: float) -> float`
   - Returns `fuel_gallons * price_per_gallon`
   - Example: `calculate_cost(4.0, 3.5)` = `14.0`

These functions will be imported in Step 2 - do not change their names or signatures.

### CLI Interface

The tool must support two modes plus help. Use `argparse` with these arguments:
- `--distance FLOAT` (miles)
- `--mpg FLOAT` (fuel efficiency)
- `--price FLOAT` (price per gallon)
- `--from-unit {mpg,l100km}` source unit for conversion
- `--to-unit {mpg,l100km}` target unit for conversion
- `--value FLOAT` value to convert

**1. Fuel calculation mode:**

```bash
python3 /app/fuel_calc.py --distance 100 --mpg 25 --price 3.5
```

- Requires `--distance`, `--mpg`, and `--price` together. If `--distance` is provided without `--mpg` or `--price`, exit with error via `parser.error()`.
- Output must be exactly: `Fuel: X.XX gallons, Cost: $Y.YY` rounded to 2 decimals.
- Example: `Fuel: 4.00 gallons, Cost: $14.00`
- Realistic example: `python3 /app/fuel_calc.py --distance 120.5 --mpg 22.5 --price 3.45` should output fuel `5.36` gallons and cost around `18.48`.

**2. Unit conversion mode:**

```bash
python3 /app/fuel_calc.py --from-unit mpg --to-unit l100km --value 23.5215
# Output: 10.00

python3 /app/fuel_calc.py --from-unit l100km --to-unit mpg --value 10
# Output: 23.52
```

- Requires all three: `--from-unit`, `--to-unit`, `--value`
- Supported units: `mpg` and `l100km`
- If `from-unit == to-unit`, echo value with 2 decimals.
- Output must be a single number formatted to 2 decimals (e.g., `10.00`).
- Logic:
  - `mpg -> l100km`: use `mpg_to_l_per_100km`
  - `l100km -> mpg`: use `l_per_100km_to_mpg`

**3. Help:**

```bash
python3 /app/fuel_calc.py --help
```

- Must exit 0.
- Output must mention `--distance`.

### Examples of Expected CLI Usage

```bash
# Help
python3 /app/fuel_calc.py --help

# Fuel calc
python3 /app/fuel_calc.py --distance 100 --mpg 25 --price 3.5
# => Fuel: 4.00 gallons, Cost: $14.00

python3 /app/fuel_calc.py --distance 60.25 --mpg 22.5 --price 3.52
# => Fuel: 2.68 gallons, Cost: $9.43

# Conversions
python3 /app/fuel_calc.py --from-unit mpg --to-unit l100km --value 22.5
# => 10.45

python3 /app/fuel_calc.py --from-unit l100km --to-unit mpg --value 10.45
# => ~22.50

# Same unit
python3 /app/fuel_calc.py --from-unit mpg --to-unit mpg --value 25
# => 25.00
```

### Constraints

- Do NOT create `/app/report.json` or `/app/fleet_report.json` or `/app/costs.json` or any fleet aggregation files in this step. Those are for Step 2 only. Negative tests will fail if those files exist after Step 1.
- No external dependencies beyond stdlib.
- Handle rounding to 2 decimals for all CLI outputs.
- Make file executable.

## Verification (what tests will check)

- `ls /app/fuel_calc.py` exists and is executable
- Functions `mpg_to_l_per_100km`, `l_per_100km_to_mpg`, `calculate_fuel_needed`, `calculate_cost` exist and return correct values within tolerance
- `python3 /app/fuel_calc.py --help` exits 0 and mentions `--distance`
- Fuel calculation CLI outputs contain correctly rounded fuel and cost
- Conversion CLI `mpg->l100km` and `l100km->mpg` correct within 0.05-0.1 tolerance
- `/app/report.json` must NOT exist after this step
