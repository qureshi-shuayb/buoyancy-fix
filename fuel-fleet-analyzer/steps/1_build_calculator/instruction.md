# Step 1 - Build Advanced Fuel Calculator CLI (Hard)

You are working in a Linux terminal. Your task is to build a reusable, advanced fuel calculator CLI tool that will be heavily reused in Step 2.

## Objective
Create an executable Python CLI tool at `/app/fuel_calc.py` that handles unit conversions, cargo-adjusted fuel consumption, CO2 emissions, and tax-inclusive costs.

## Requirements

### File Location and Setup
- File must be at `/app/fuel_calc.py`
- Must be executable (`chmod +x`) and runnable via `python3 /app/fuel_calc.py ...`
- Must use only Python standard library (no pip)
- Must use `argparse` with **subparsers** (required subcommands)
- Include shebang `#!/usr/bin/env python3`
- All functions must have type hints and docstrings

### Functions (must be implemented and importable - 12 total)
Implement these 12 functions so Step 2 can import them. Do NOT change names or signatures.

1. `mpg_to_l_per_100km(mpg: float) -> float` : 235.215 / mpg, ValueError if mpg<=0, ex 23.5215->10.0
2. `l_per_100km_to_mpg(l100: float) -> float` : 235.215 / l100, ValueError if <=0
3. `calculate_fuel_needed(distance_miles: float, mpg: float) -> float` : distance/mpg, ValueError if mpg<=0 or distance<0
4. `calculate_cost(fuel_gallons: float, price_per_gallon: float) -> float` : fuel*price, ValueError if <0
5. `miles_to_km(miles: float) -> float` : miles*1.60934, ValueError if miles<0
6. `km_to_miles(km: float) -> float` : km/1.60934, ValueError if km<0
7. `gallons_to_liters(gallons: float) -> float` : gallons*3.78541, ValueError if <0
8. `liters_to_gallons(liters: float) -> float` : liters/3.78541, ValueError if <0
9. `mpg_to_km_per_liter(mpg: float) -> float` : mpg*0.425144, ValueError if mpg<=0
10. `calculate_fuel_needed_with_cargo(distance_miles: float, mpg: float, cargo_kg: float = 0) -> float`
    - Formula: base = distance/mpg; factor = 1 + max(0,cargo_kg)*0.0005 (0.05% per kg, 200kg=10% extra)
    - Returns base*factor, ValueError if mpg<=0, distance<0, cargo<0, ex 100,25,200 -> 4.4
11. `calculate_co2_emissions(fuel_gallons: float, fuel_type: str = "gasoline") -> float`
    - gasoline 8.887 kg/gal, diesel 10.21, ValueError if fuel<0 or fuel_type not in gasoline/diesel (case-insensitive), ex 10 gal gasoline 88.87, diesel 102.1
12. `calculate_cost_with_tax(fuel_gallons: float, price_per_gallon: float, tax_rate: float = 0.0) -> float`
    - fuel*price*(1+tax_rate), ValueError if fuel<0, price<0, tax<0 or >1, ex 10*3.5*1.08=37.8

### CLI Interface - Subparsers Required (Hard)
Must use argparse with required subcommands: `convert`, `calc`, `co2`. Each subcommand must have its own help. Top-level help must show subcommands convert, calc, co2.

**1. convert subcommand:**
```bash
python3 /app/fuel_calc.py convert --from-unit mpg --to-unit l100km --value 25
# Output: 9.41

python3 /app/fuel_calc.py convert --from-unit miles --to-unit km --value 100
# Output: 160.93
```
- Required: --from-unit, --to-unit, --value FLOAT
- Supported from/to: mpg, l100km, kmpl or km_per_liter, miles, km, gallons, liters
  - mpg->l100km mpg_to_l_per_100km
  - l100km->mpg l_per_100km_to_mpg
  - mpg->kmpl mpg_to_km_per_liter
  - kmpl->mpg /0.425144
  - miles->km miles_to_km
  - km->miles km_to_miles
  - gallons->liters gallons_to_liters
  - liters->gallons liters_to_gallons
  - Same unit echo with 2 decimals
- Output single number 2 decimals

**2. calc subcommand:**
```bash
python3 /app/fuel_calc.py calc --distance 100 --mpg 25 --price 3.5
# Text default: Fuel: 4.00 gallons, Cost: $14.00, CO2: 35.55 kg

python3 /app/fuel_calc.py calc --distance 100 --mpg 25 --price 3.5 --cargo 200 --fuel-type diesel --tax-rate 0.08 --output-format json
# JSON: {"fuel_gallons": 4.40, "cost": 16.63, "co2_kg": 44.92}
```
- Required: --distance, --mpg, --price
- Optional: --cargo default 0, --fuel-type {gasoline,diesel} default gasoline, --tax-rate 0-1 default 0, --output-format {text,json} default text
- Logic: fuel = calculate_fuel_needed_with_cargo(distance, mpg, cargo), cost = calculate_cost_with_tax(fuel, price, tax_rate), co2 = calculate_co2_emissions(fuel, fuel_type)
- text: Fuel: X.XX gallons, Cost: $Y.YY, CO2: Z.ZZ kg
- json: {"fuel_gallons": X.XX, "cost": Y.YY, "co2_kg": Z.ZZ}

**3. co2 subcommand:**
```bash
python3 /app/fuel_calc.py co2 --fuel 10 --fuel-type gasoline
# Output contains 88.87

python3 /app/fuel_calc.py co2 --fuel 10 --fuel-type diesel --output-format json
# {"co2_kg": 102.10}
```
- Required: --fuel FLOAT gallons
- Optional: --fuel-type default gasoline, --output-format text/json default text
- Uses calculate_co2_emissions
- text must contain number 2 decimals, json key co2_kg

**Error handling:** Invalid units, negative distance/mpg, cargo<0, tax>1, invalid fuel_type should cause error exit non-zero.

### Examples
```bash
python3 /app/fuel_calc.py --help
python3 /app/fuel_calc.py convert --help
python3 /app/fuel_calc.py calc --help

python3 /app/fuel_calc.py convert --from-unit mpg --to-unit l100km --value 23.5215
python3 /app/fuel_calc.py convert --from-unit miles --to-unit km --value 100
python3 /app/fuel_calc.py convert --from-unit gallons --to-unit liters --value 10

python3 /app/fuel_calc.py calc --distance 100 --mpg 25 --price 3.5
python3 /app/fuel_calc.py calc --distance 100 --mpg 25 --price 3.5 --cargo 200 --fuel-type diesel --tax-rate 0.08 --output-format json

python3 /app/fuel_calc.py co2 --fuel 10 --fuel-type gasoline
python3 /app/fuel_calc.py co2 --fuel 10 --fuel-type diesel --output-format json
```

### Constraints
- Do NOT create /app/report.json or fleet files in this step (negative tests fail if exists)
- No external deps
- Must be executable
- Must have docstrings for all functions
- Subparsers required

## Verification
- File exists and executable
- All 12 functions exist, correct within tolerance, ValueError on invalid
- convert: mpg<->l100km, miles<->km, gallons<->liters within 0.05, same-unit echo
- calc: text contains Fuel, Cost, CO2 2 decimals; json valid; cargo increases fuel 200kg 10% more; tax increases cost; diesel CO2 > gasoline same fuel
- co2: gasoline 10 gal 88.87, diesel 102.1
- Help mentions convert, calc, co2 and --distance
- No report.json after step1
