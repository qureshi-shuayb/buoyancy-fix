#!/bin/bash
set -e

cat > /app/fuel_calc.py << 'PY'
#!/usr/bin/env python3
"""
Fuel calculator CLI - built in step 1
Supports mpg <-> L/100km conversion and fuel cost calculation
"""

import argparse
import sys


def mpg_to_l_per_100km(mpg: float) -> float:
    if mpg <= 0:
        raise ValueError("MPG must be positive")
    return 235.215 / mpg


def l_per_100km_to_mpg(l100: float) -> float:
    if l100 <= 0:
        raise ValueError("L/100km must be positive")
    return 235.215 / l100


def calculate_fuel_needed(distance_miles: float, mpg: float) -> float:
    if mpg <= 0:
        raise ValueError("MPG must be positive")
    if distance_miles < 0:
        raise ValueError("Distance cannot be negative")
    return distance_miles / mpg


def calculate_cost(fuel_gallons: float, price_per_gallon: float) -> float:
    if fuel_gallons < 0 or price_per_gallon < 0:
        raise ValueError("Fuel and price must be non-negative")
    return fuel_gallons * price_per_gallon


def main():
    parser = argparse.ArgumentParser(description="Fuel calculator - converts efficiency and calculates fuel cost")
    parser.add_argument('--distance', type=float, help='Distance in miles')
    parser.add_argument('--mpg', type=float, help='Fuel efficiency in MPG')
    parser.add_argument('--price', type=float, help='Price per gallon')
    parser.add_argument('--from-unit', choices=['mpg', 'l100km'], help='Source unit for conversion')
    parser.add_argument('--to-unit', choices=['mpg', 'l100km'], help='Target unit for conversion')
    parser.add_argument('--value', type=float, help='Value to convert')

    args = parser.parse_args()

    # Conversion mode
    if args.from_unit and args.to_unit and args.value is not None:
        if args.from_unit == 'mpg' and args.to_unit == 'l100km':
            result = mpg_to_l_per_100km(args.value)
            print(f"{result:.2f}")
        elif args.from_unit == 'l100km' and args.to_unit == 'mpg':
            result = l_per_100km_to_mpg(args.value)
            print(f"{result:.2f}")
        elif args.from_unit == args.to_unit:
            print(f"{args.value:.2f}")
        else:
            parser.error(f"Unsupported conversion {args.from_unit} -> {args.to_unit}")
        return

    # Fuel calculation mode
    if args.distance is not None:
        if args.mpg is None or args.price is None:
            parser.error("--distance requires --mpg and --price")
        fuel = calculate_fuel_needed(args.distance, args.mpg)
        cost = calculate_cost(fuel, args.price)
        print(f"Fuel: {fuel:.2f} gallons, Cost: ${cost:.2f}")
        return

    parser.print_help()
    sys.exit(0)


if __name__ == '__main__':
    main()
PY

chmod +x /app/fuel_calc.py
echo "Step 1 solution: /app/fuel_calc.py created"
