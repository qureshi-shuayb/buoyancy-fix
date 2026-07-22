#!/bin/bash
set -e

cat > /app/generate_report.py << 'PY'
import json
import csv
import os
from datetime import datetime
from collections import defaultdict
import importlib.util

# Import fuel_calc from step 1 - must reuse it
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
    """Group prices by fuel_type, sorted ascending by date.
    CSV columns: date,fuel_type,price_per_gallon,tax_rate
    Returns dict fuel_type -> list of (date, price, tax_rate) sorted
    """
    grouped = defaultdict(list)
    with open(PRICES_PATH) as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Handle both old single column and new multi fuel_type schema
            if "fuel_type" in row and row["fuel_type"]:
                ft = row["fuel_type"].lower()
                date = parse_date(row["date"])
                price = float(row["price_per_gallon"])
                tax = float(row.get("tax_rate", 0.0))
                grouped[ft].append((date, price, tax))
            else:
                # Fallback old schema: single price column treated as gasoline
                date = parse_date(row["date"])
                price = float(row["price_per_gallon"])
                tax = float(row.get("tax_rate", 0.0))
                grouped["gasoline"].append((date, price, tax))
    for ft in grouped:
        grouped[ft].sort(key=lambda x: x[0])
    return grouped

def get_price_for_date(trip_date, fuel_type, grouped_prices):
    """Most recent price <= trip_date for given fuel_type, fallback to first"""
    ft = fuel_type.lower()
    prices = grouped_prices.get(ft, [])
    if not prices:
        # try gasoline as fallback if fuel_type not found
        prices = grouped_prices.get("gasoline", [])
    candidate = None
    candidate_tax = 0.0
    for p_date, p_price, p_tax in prices:
        if p_date <= trip_date:
            candidate = p_price
            candidate_tax = p_tax
        else:
            break
    if candidate is None:
        # before first price, use first
        if prices:
            candidate = prices[0][1]
            candidate_tax = prices[0][2]
        else:
            candidate = 0.0
            candidate_tax = 0.0
    return candidate, candidate_tax

def main():
    vehicles = load_vehicles()
    grouped_prices = load_prices()

    per_vehicle = {}
    for vid, vinfo in vehicles.items():
        per_vehicle[vid] = {
            "total_miles": 0.0,
            "total_fuel_gallons": 0.0,  # base without cargo
            "total_fuel_adjusted": 0.0,
            "total_cost": 0.0,
            "total_cost_with_tax": 0.0,
            "total_co2_kg": 0.0,
            "total_cargo_kg": 0.0,
            "trip_count": 0,
            "monthly_breakdown": defaultdict(lambda: {"miles": 0.0, "fuel_gallons": 0.0, "cost": 0.0, "cost_with_tax": 0.0, "co2_kg": 0.0, "cargo_kg": 0.0, "trip_count": 0})
        }

    monthly_totals = defaultdict(lambda: {"miles": 0.0, "fuel_gallons": 0.0, "cost": 0.0, "cost_with_tax": 0.0, "co2_kg": 0.0, "trip_count": 0})
    fuel_type_breakdown = defaultdict(lambda: {"miles": 0.0, "fuel_gallons": 0.0, "cost": 0.0, "cost_with_tax": 0.0, "co2_kg": 0.0})

    with open(TRIPS_PATH) as f:
        reader = csv.DictReader(f)
        # Support both old schema (no cargo) and new
        has_cargo = "cargo_kg" in reader.fieldnames
        for row in reader:
            vid = row["vehicle_id"]
            if vid not in vehicles:
                continue
            miles = float(row["miles"])
            trip_date = parse_date(row["date"])
            cargo_kg = float(row["cargo_kg"]) if has_cargo and row.get("cargo_kg") else 0.0
            vinfo = vehicles[vid]
            mpg = vinfo["mpg"]
            fuel_type = vinfo.get("fuel_type", "gasoline")
            capacity = vinfo.get("cargo_capacity_kg", 2000)
            # Cap cargo to capacity for fuel penalty
            cargo_for_calc = min(cargo_kg, capacity) if capacity else cargo_kg

            # MUST use fuel_calc functions
            fuel_base = fuel_calc.calculate_fuel_needed(miles, mpg)
            fuel_adj = fuel_calc.calculate_fuel_needed_with_cargo(miles, mpg, cargo_for_calc)
            price, tax_rate = get_price_for_date(trip_date, fuel_type, grouped_prices)
            cost = fuel_calc.calculate_cost(fuel_adj, price)
            cost_with_tax = fuel_calc.calculate_cost_with_tax(fuel_adj, price, tax_rate)
            co2 = fuel_calc.calculate_co2_emissions(fuel_adj, fuel_type)

            pv = per_vehicle[vid]
            pv["total_miles"] += miles
            pv["total_fuel_gallons"] += fuel_base
            pv["total_fuel_adjusted"] += fuel_adj
            pv["total_cost"] += cost
            pv["total_cost_with_tax"] += cost_with_tax
            pv["total_co2_kg"] += co2
            pv["total_cargo_kg"] += cargo_kg
            pv["trip_count"] += 1

            ym = trip_date.strftime("%Y-%m")
            mb = pv["monthly_breakdown"][ym]
            mb["miles"] += miles
            mb["fuel_gallons"] += fuel_adj
            mb["cost"] += cost
            mb["cost_with_tax"] += cost_with_tax
            mb["co2_kg"] += co2
            mb["cargo_kg"] += cargo_kg
            mb["trip_count"] += 1

            mt = monthly_totals[ym]
            mt["miles"] += miles
            mt["fuel_gallons"] += fuel_adj
            mt["cost"] += cost
            mt["cost_with_tax"] += cost_with_tax
            mt["co2_kg"] += co2
            mt["trip_count"] += 1

            ftb = fuel_type_breakdown[fuel_type.lower()]
            ftb["miles"] += miles
            ftb["fuel_gallons"] += fuel_adj
            ftb["cost"] += cost
            ftb["cost_with_tax"] += cost_with_tax
            ftb["co2_kg"] += co2

    # Final rounding and avg calculations per vehicle
    for vid in per_vehicle:
        pv = per_vehicle[vid]
        # Round totals to 2 decimals
        pv["total_miles"] = round(pv["total_miles"], 2)
        pv["total_fuel_gallons"] = round(pv["total_fuel_gallons"], 2)
        pv["total_fuel_adjusted"] = round(pv["total_fuel_adjusted"], 2)
        pv["total_cost"] = round(pv["total_cost"], 2)
        pv["total_cost_with_tax"] = round(pv["total_cost_with_tax"], 2)
        pv["total_co2_kg"] = round(pv["total_co2_kg"], 2)
        pv["total_cargo_kg"] = round(pv["total_cargo_kg"], 2)
        # avg
        if pv["total_fuel_adjusted"] > 0:
            pv["avg_mpg"] = round(pv["total_miles"] / pv["total_fuel_adjusted"], 2)
        else:
            pv["avg_mpg"] = 0.0
        if pv["total_miles"] > 0:
            pv["avg_cost_per_mile"] = round(pv["total_cost_with_tax"] / pv["total_miles"], 2)
        else:
            pv["avg_cost_per_mile"] = 0.0
        # monthly breakdown rounding
        rounded_mb = {}
        for ym, stats in pv["monthly_breakdown"].items():
            rounded_mb[ym] = {
                "miles": round(stats["miles"], 2),
                "fuel_gallons": round(stats["fuel_gallons"], 2),
                "cost": round(stats["cost"], 2),
                "cost_with_tax": round(stats["cost_with_tax"], 2),
                "co2_kg": round(stats["co2_kg"], 2),
                "cargo_kg": round(stats["cargo_kg"], 2),
                "trip_count": stats["trip_count"]
            }
        pv["monthly_breakdown"] = rounded_mb

    # Fleet totals
    fleet_total_cost = round(sum(v["total_cost"] for v in per_vehicle.values()), 2)
    fleet_total_cost_with_tax = round(sum(v["total_cost_with_tax"] for v in per_vehicle.values()), 2)
    fleet_total_fuel = round(sum(v["total_fuel_adjusted"] for v in per_vehicle.values()), 2)
    fleet_total_co2 = round(sum(v["total_co2_kg"] for v in per_vehicle.values()), 2)

    # monthly totals rounding
    rounded_monthly = {}
    for ym, stats in monthly_totals.items():
        rounded_monthly[ym] = {
            "miles": round(stats["miles"], 2),
            "fuel_gallons": round(stats["fuel_gallons"], 2),
            "cost": round(stats["cost"], 2),
            "cost_with_tax": round(stats["cost_with_tax"], 2),
            "co2_kg": round(stats["co2_kg"], 2),
            "trip_count": stats["trip_count"]
        }

    # fuel type breakdown rounding
    rounded_ft = {}
    for ft, stats in fuel_type_breakdown.items():
        rounded_ft[ft] = {
            "miles": round(stats["miles"], 2),
            "fuel_gallons": round(stats["fuel_gallons"], 2),
            "cost": round(stats["cost"], 2),
            "cost_with_tax": round(stats["cost_with_tax"], 2),
            "co2_kg": round(stats["co2_kg"], 2)
        }

    # most inefficient = highest fuel_adjusted / miles
    most_inefficient = None
    max_ratio = -1
    for vid, stats in per_vehicle.items():
        if stats["total_miles"] > 0:
            ratio = stats["total_fuel_adjusted"] / stats["total_miles"]
            if ratio > max_ratio:
                max_ratio = ratio
                most_inefficient = vid

    most_expensive = None
    max_cost = -1
    for vid, stats in per_vehicle.items():
        if stats["total_cost_with_tax"] > max_cost:
            max_cost = stats["total_cost_with_tax"]
            most_expensive = vid

    highest_co2 = None
    max_co2 = -1
    for vid, stats in per_vehicle.items():
        if stats["total_co2_kg"] > max_co2:
            max_co2 = stats["total_co2_kg"]
            highest_co2 = vid

    most_expensive_month = None
    max_month_cost = -1
    for ym, stats in monthly_totals.items():
        # use cost_with_tax for month expensive
        c = stats["cost_with_tax"]
        if c > max_month_cost:
            max_month_cost = c
            most_expensive_month = ym

    report = {
        "per_vehicle": per_vehicle,
        "fleet": {
            "fleet_total_cost": fleet_total_cost,
            "fleet_total_cost_with_tax": fleet_total_cost_with_tax,
            "fleet_total_fuel_gallons": fleet_total_fuel,
            "fleet_total_co2_kg": fleet_total_co2,
            "most_inefficient_vehicle": most_inefficient,
            "most_expensive_vehicle": most_expensive,
            "highest_co2_vehicle": highest_co2,
            "most_expensive_month": most_expensive_month,
            "monthly_totals": rounded_monthly,
            "fuel_type_breakdown": rounded_ft
        },
        # backward compat aliases
        "fleet_total_cost": fleet_total_cost,
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
echo "Step 2 hard solution done"
