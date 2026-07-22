#!/bin/bash
set -e

# Step 2 oracle: uses fuel_calc.py from step 1 to generate /app/report.json

cat > /app/generate_report.py << 'PY'
import json
import csv
import os
import sys
from datetime import datetime

# Import fuel_calc from step 1 - must reuse it
import importlib.util
spec = importlib.util.spec_from_file_location("fuel_calc", "/app/fuel_calc.py")
fuel_calc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fuel_calc)

VEHICLES_PATH = "/app/data/vehicles.json"
TRIPS_PATH = "/app/data/trips.csv"
PRICES_PATH = "/app/data/fuel_prices.csv"
REPORT_PATH = "/app/report.json"

def parse_date(d):
    return datetime.strptime(d, "%Y-%m-%d")

def load_vehicles():
    with open(VEHICLES_PATH) as f:
        data = json.load(f)
    return {v["id"]: v for v in data}

def load_prices():
    prices = []
    with open(PRICES_PATH) as f:
        reader = csv.DictReader(f)
        for row in reader:
            prices.append((parse_date(row["date"]), float(row["price_per_gallon"])))
    prices.sort(key=lambda x: x[0])
    return prices

def get_price_for_date(trip_date, prices):
    # most recent price <= trip date
    candidate = None
    for p_date, p_price in prices:
        if p_date <= trip_date:
            candidate = p_price
        else:
            break
    if candidate is None:
        # if trip before first price, use first price
        candidate = prices[0][1] if prices else 0.0
    return candidate

def main():
    vehicles = load_vehicles()
    prices = load_prices()

    per_vehicle = {}
    for vid in vehicles:
        per_vehicle[vid] = {"total_miles": 0.0, "total_fuel_gallons": 0.0, "total_cost": 0.0}

    with open(TRIPS_PATH) as f:
        reader = csv.DictReader(f)
        for row in reader:
            vid = row["vehicle_id"]
            if vid not in vehicles:
                continue
            miles = float(row["miles"])
            trip_date = parse_date(row["date"])
            mpg = vehicles[vid]["mpg"]

            # MUST use fuel_calc functions
            fuel = fuel_calc.calculate_fuel_needed(miles, mpg)
            price = get_price_for_date(trip_date, prices)
            cost = fuel_calc.calculate_cost(fuel, price)

            per_vehicle[vid]["total_miles"] += miles
            per_vehicle[vid]["total_fuel_gallons"] += fuel
            per_vehicle[vid]["total_cost"] += cost

    # Round to 2 decimals
    for vid in per_vehicle:
        per_vehicle[vid]["total_miles"] = round(per_vehicle[vid]["total_miles"], 2)
        per_vehicle[vid]["total_fuel_gallons"] = round(per_vehicle[vid]["total_fuel_gallons"], 2)
        per_vehicle[vid]["total_cost"] = round(per_vehicle[vid]["total_cost"], 2)

    fleet_total = round(sum(v["total_cost"] for v in per_vehicle.values()), 2)

    # most inefficient = highest fuel per mile = lowest mpg, but computed from totals to be robust
    # efficiency = total_fuel / total_miles, higher means more inefficient
    most_inefficient = None
    max_ratio = -1
    for vid, stats in per_vehicle.items():
        if stats["total_miles"] > 0:
            ratio = stats["total_fuel_gallons"] / stats["total_miles"]
            if ratio > max_ratio:
                max_ratio = ratio
                most_inefficient = vid

    report = {
        "per_vehicle": per_vehicle,
        "fleet_total_cost": fleet_total,
        "most_inefficient_vehicle": most_inefficient
    }

    with open(REPORT_PATH, "w") as out:
        json.dump(report, out, indent=2)

    print(f"Report written to {REPORT_PATH}")
    print(json.dumps(report, indent=2))

if __name__ == "__main__":
    main()
PY

chmod +x /app/generate_report.py
python3 /app/generate_report.py
echo "Step 2 solution done"
