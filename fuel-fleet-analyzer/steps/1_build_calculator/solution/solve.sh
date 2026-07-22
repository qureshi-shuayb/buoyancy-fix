#!/bin/bash
set -e

cat > /app/fuel_calc.py << 'PY'
#!/usr/bin/env python3
"""
Advanced Fuel calculator CLI - built in step 1 (hard version)
Supports unit conversions, cargo-adjusted fuel, CO2, tax, subcommands convert/calc/co2
"""

import argparse
import json
import sys


def mpg_to_l_per_100km(mpg: float) -> float:
    """Convert mpg to L/100km using formula 235.215 / mpg."""
    if mpg <= 0:
        raise ValueError("MPG must be positive")
    return 235.215 / mpg


def l_per_100km_to_mpg(l100: float) -> float:
    """Convert L/100km to mpg using formula 235.215 / l100."""
    if l100 <= 0:
        raise ValueError("L/100km must be positive")
    return 235.215 / l100


def calculate_fuel_needed(distance_miles: float, mpg: float) -> float:
    """Calculate fuel needed: distance / mpg."""
    if mpg <= 0:
        raise ValueError("MPG must be positive")
    if distance_miles < 0:
        raise ValueError("Distance cannot be negative")
    return distance_miles / mpg


def calculate_cost(fuel_gallons: float, price_per_gallon: float) -> float:
    """Calculate cost: fuel * price."""
    if fuel_gallons < 0 or price_per_gallon < 0:
        raise ValueError("Fuel and price must be non-negative")
    return fuel_gallons * price_per_gallon


def miles_to_km(miles: float) -> float:
    """Convert miles to km: miles * 1.60934."""
    if miles < 0:
        raise ValueError("Miles cannot be negative")
    return miles * 1.60934


def km_to_miles(km: float) -> float:
    """Convert km to miles: km / 1.60934."""
    if km < 0:
        raise ValueError("KM cannot be negative")
    return km / 1.60934


def gallons_to_liters(gallons: float) -> float:
    """Convert gallons to liters: gallons * 3.78541."""
    if gallons < 0:
        raise ValueError("Gallons cannot be negative")
    return gallons * 3.78541


def liters_to_gallons(liters: float) -> float:
    """Convert liters to gallons: liters / 3.78541."""
    if liters < 0:
        raise ValueError("Liters cannot be negative")
    return liters / 3.78541


def mpg_to_km_per_liter(mpg: float) -> float:
    """Convert mpg to km per liter: mpg * 0.425144."""
    if mpg <= 0:
        raise ValueError("MPG must be positive")
    return mpg * 0.425144


def calculate_fuel_needed_with_cargo(distance_miles: float, mpg: float, cargo_kg: float = 0) -> float:
    """Calculate fuel needed with cargo penalty.
    base = distance / mpg
    factor = 1 + max(0, cargo_kg) * 0.0005 (0.05% per kg, 200kg=10% extra)
    """
    if mpg <= 0:
        raise ValueError("MPG must be positive")
    if distance_miles < 0:
        raise ValueError("Distance cannot be negative")
    if cargo_kg < 0:
        raise ValueError("Cargo cannot be negative")
    base = distance_miles / mpg
    factor = 1.0 + max(0.0, cargo_kg) * 0.0005
    return base * factor


def calculate_co2_emissions(fuel_gallons: float, fuel_type: str = "gasoline") -> float:
    """Calculate CO2 emissions in kg.
    gasoline: 8.887 kg/gal, diesel: 10.21 kg/gal
    """
    if fuel_gallons < 0:
        raise ValueError("Fuel cannot be negative")
    ft = fuel_type.lower().strip()
    if ft == "gasoline":
        return fuel_gallons * 8.887
    elif ft == "diesel":
        return fuel_gallons * 10.21
    else:
        raise ValueError(f"Unsupported fuel_type {fuel_type}, must be gasoline or diesel")


def calculate_cost_with_tax(fuel_gallons: float, price_per_gallon: float, tax_rate: float = 0.0) -> float:
    """Calculate cost with tax: fuel*price*(1+tax_rate). tax_rate 0-1"""
    if fuel_gallons < 0 or price_per_gallon < 0:
        raise ValueError("Fuel and price must be non-negative")
    if tax_rate < 0 or tax_rate > 1:
        raise ValueError("Tax rate must be between 0 and 1")
    return fuel_gallons * price_per_gallon * (1.0 + tax_rate)


def _normalize_unit(u: str) -> str:
    """Normalize unit aliases"""
    u = u.lower().strip()
    alias = {
        "kmpl": "kmpl",
        "km_per_liter": "kmpl",
        "km_per_l": "kmpl",
        "kpl": "kmpl",
        "l/100km": "l100km",
        "l100km": "l100km",
        "mpg": "mpg",
        "miles": "miles",
        "mile": "miles",
        "km": "km",
        "kilometers": "km",
        "gallons": "gallons",
        "gallon": "gallons",
        "liters": "liters",
        "liter": "liters",
        "l": "liters",
    }
    return alias.get(u, u)


def _do_conversion(from_unit: str, to_unit: str, value: float) -> float:
    fu = _normalize_unit(from_unit)
    tu = _normalize_unit(to_unit)
    if fu == tu:
        return value
    # mpg <-> l100km
    if fu == "mpg" and tu == "l100km":
        return mpg_to_l_per_100km(value)
    if fu == "l100km" and tu == "mpg":
        return l_per_100km_to_mpg(value)
    # mpg <-> kmpl
    if fu == "mpg" and tu == "kmpl":
        return mpg_to_km_per_liter(value)
    if fu == "kmpl" and tu == "mpg":
        if value <= 0:
            raise ValueError("kmpl must be positive")
        return value / 0.425144
    # kmpl <-> l100km
    if fu == "kmpl" and tu == "l100km":
        if value <= 0:
            raise ValueError("kmpl must be positive")
        return 100.0 / value
    if fu == "l100km" and tu == "kmpl":
        if value <= 0:
            raise ValueError("l100km must be positive")
        return 100.0 / value
    # miles <-> km
    if fu == "miles" and tu == "km":
        return miles_to_km(value)
    if fu == "km" and tu == "miles":
        return km_to_miles(value)
    # gallons <-> liters
    if fu == "gallons" and tu == "liters":
        return gallons_to_liters(value)
    if fu == "liters" and tu == "gallons":
        return liters_to_gallons(value)
    raise ValueError(f"Unsupported conversion {from_unit} -> {to_unit}")


def main():
    parser = argparse.ArgumentParser(description="Advanced Fuel calculator - converts efficiency and calculates fuel cost with cargo, CO2, tax. Subcommands: convert, calc, co2")
    subparsers = parser.add_subparsers(dest="subcommand", help="Available subcommands")

    # Also support old flat flags for backward compat (hidden)
    parser.add_argument('--distance', type=float, help='Distance in miles (legacy flat mode)')
    parser.add_argument('--mpg', type=float, help='Fuel efficiency in MPG (legacy flat mode)')
    parser.add_argument('--price', type=float, help='Price per gallon (legacy flat mode)')
    parser.add_argument('--from-unit', help='Source unit for conversion (legacy flat mode)')
    parser.add_argument('--to-unit', help='Target unit for conversion (legacy flat mode)')
    parser.add_argument('--value', type=float, help='Value to convert (legacy flat mode)')

    # convert subcommand
    p_convert = subparsers.add_parser("convert", help="Convert between units: mpg, l100km, kmpl, miles, km, gallons, liters")
    p_convert.add_argument('--from-unit', required=True, help='Source unit: mpg, l100km, kmpl, miles, km, gallons, liters')
    p_convert.add_argument('--to-unit', required=True, help='Target unit: mpg, l100km, kmpl, miles, km, gallons, liters')
    p_convert.add_argument('--value', type=float, required=True, help='Value to convert')

    # calc subcommand
    p_calc = subparsers.add_parser("calc", help="Calculate fuel, cost with cargo, tax, CO2")
    p_calc.add_argument('--distance', type=float, required=True, help='Distance in miles')
    p_calc.add_argument('--mpg', type=float, required=True, help='Fuel efficiency in MPG')
    p_calc.add_argument('--price', type=float, required=True, help='Price per gallon')
    p_calc.add_argument('--cargo', type=float, default=0.0, help='Cargo weight in kg (default 0, penalty 0.05%% per kg)')
    p_calc.add_argument('--fuel-type', choices=['gasoline', 'diesel'], default='gasoline', help='Fuel type for CO2 calculation')
    p_calc.add_argument('--tax-rate', type=float, default=0.0, help='Tax rate 0-1 (default 0.0)')
    p_calc.add_argument('--output-format', choices=['text', 'json'], default='text', help='Output format')

    # co2 subcommand
    p_co2 = subparsers.add_parser("co2", help="Calculate CO2 emissions from fuel")
    p_co2.add_argument('--fuel', type=float, required=True, help='Fuel in gallons')
    p_co2.add_argument('--fuel-type', choices=['gasoline', 'diesel'], default='gasoline', help='Fuel type')
    p_co2.add_argument('--output-format', choices=['text', 'json'], default='text', help='Output format')

    args = parser.parse_args()

    # Handle subcommands
    if args.subcommand == "convert":
        try:
            result = _do_conversion(args.from_unit, args.to_unit, args.value)
            print(f"{result:.2f}")
        except Exception as e:
            parser.error(str(e))
        return

    if args.subcommand == "calc":
        if args.mpg is None or args.price is None or args.distance is None:
            parser.error("--distance, --mpg, --price required for calc")
        if args.mpg <= 0:
            parser.error("--mpg must be positive")
        if args.distance < 0:
            parser.error("--distance must be >=0")
        if args.cargo < 0:
            parser.error("--cargo must be >=0")
        if args.tax_rate < 0 or args.tax_rate > 1:
            parser.error("--tax-rate must be 0-1")
        try:
            fuel = calculate_fuel_needed_with_cargo(args.distance, args.mpg, args.cargo)
            cost = calculate_cost_with_tax(fuel, args.price, args.tax_rate)
            co2 = calculate_co2_emissions(fuel, args.fuel_type)
        except ValueError as ve:
            parser.error(str(ve))
        if args.output_format == "json":
            out = {"fuel_gallons": round(fuel, 2), "cost": round(cost, 2), "co2_kg": round(co2, 2)}
            print(json.dumps(out))
        else:
            print(f"Fuel: {fuel:.2f} gallons, Cost: ${cost:.2f}, CO2: {co2:.2f} kg")
        return

    if args.subcommand == "co2":
        if args.fuel < 0:
            parser.error("--fuel must be >=0")
        try:
            co2 = calculate_co2_emissions(args.fuel, args.fuel_type)
        except ValueError as ve:
            parser.error(str(ve))
        if args.output_format == "json":
            print(json.dumps({"co2_kg": round(co2, 2)}))
        else:
            # Allow both formats, but contain number
            print(f"{co2:.2f}")
        return

    # Legacy flat mode fallback (for backward compat with old tests / simple usage)
    # Conversion legacy
    legacy_from = getattr(args, 'from_unit', None) if hasattr(args, 'from_unit') else parser.parse_known_args()[0].__dict__.get('from_unit')
    # Actually args.from_unit exists from top-level hidden args
    if args.__dict__.get('from_unit') and args.__dict__.get('to_unit') and args.__dict__.get('value') is not None:
        try:
            result = _do_conversion(args.from_unit, args.to_unit, args.value)
            print(f"{result:.2f}")
        except Exception as e:
            parser.error(str(e))
        return

    if args.__dict__.get('distance') is not None:
        if args.__dict__.get('mpg') is None or args.__dict__.get('price') is None:
            parser.error("--distance requires --mpg and --price")
        try:
            fuel = calculate_fuel_needed(args.distance, args.mpg)
            cost = calculate_cost(fuel, args.price)
            print(f"Fuel: {fuel:.2f} gallons, Cost: ${cost:.2f}")
        except ValueError as ve:
            parser.error(str(ve))
        return

    parser.print_help()
    sys.exit(0)


if __name__ == '__main__':
    main()
PY

chmod +x /app/fuel_calc.py
echo "Step 1 hard solution: /app/fuel_calc.py created with 12 funcs + subcommands"
/app/fuel_calc.py --help
echo "--- convert test ---"
python3 /app/fuel_calc.py convert --from-unit mpg --to-unit l100km --value 23.5215
python3 /app/fuel_calc.py convert --from-unit miles --to-unit km --value 100
python3 /app/fuel_calc.py convert --from-unit gallons --to-unit liters --value 10
echo "--- calc tests ---"
python3 /app/fuel_calc.py calc --distance 100 --mpg 25 --price 3.5
python3 /app/fuel_calc.py calc --distance 100 --mpg 25 --price 3.5 --cargo 200 --fuel-type diesel --tax-rate 0.08 --output-format json
echo "--- co2 tests ---"
python3 /app/fuel_calc.py co2 --fuel 10 --fuel-type gasoline
python3 /app/fuel_calc.py co2 --fuel 10 --fuel-type diesel --output-format json
