import os
import json
import csv
import sys
import importlib.util
from datetime import datetime
from pathlib import Path
from collections import defaultdict

REPORT_PATH = "/app/report.json"
FUEL_CALC_PATH = "/app/fuel_calc.py"
VEHICLES_PATH = "/app/data/vehicles.json"
TRIPS_PATH = "/app/data/trips.csv"
PRICES_PATH = "/app/data/fuel_prices.csv"


def load_fuel_calc():
    spec = importlib.util.spec_from_file_location("fuel_calc", FUEL_CALC_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_date(d):
    return datetime.strptime(d, "%Y-%m-%d")


def compute_expected():
    """Oracle logic for hard version: 2D price lookup (date + fuel_type), cargo penalty, tax, co2"""
    with open(VEHICLES_PATH) as f:
        vehicles = {v["id"]: v for v in json.load(f)}

    # Group prices by fuel_type
    grouped = defaultdict(list)
    with open(PRICES_PATH) as f:
        reader = csv.DictReader(f)
        for row in reader:
            if "fuel_type" in row and row["fuel_type"]:
                ft = row["fuel_type"].lower()
                date = parse_date(row["date"])
                price = float(row["price_per_gallon"])
                tax = float(row.get("tax_rate", 0.0))
                grouped[ft].append((date, price, tax))
            else:
                date = parse_date(row["date"])
                price = float(row["price_per_gallon"])
                tax = float(row.get("tax_rate", 0.0))
                grouped["gasoline"].append((date, price, tax))
    for ft in grouped:
        grouped[ft].sort(key=lambda x: x[0])

    def get_price(trip_date, fuel_type):
        ft = fuel_type.lower()
        prices = grouped.get(ft, grouped.get("gasoline", []))
        cand = None
        cand_tax = 0.0
        for pd, pp, pt in prices:
            if pd <= trip_date:
                cand = pp
                cand_tax = pt
            else:
                break
        if cand is None:
            if prices:
                cand = prices[0][1]
                cand_tax = prices[0][2]
            else:
                cand = 0.0
                cand_tax = 0.0
        return cand, cand_tax

    per_vehicle = {}
    for vid, vinfo in vehicles.items():
        per_vehicle[vid] = {
            "total_miles": 0.0,
            "total_fuel_gallons": 0.0,
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
        has_cargo = "cargo_kg" in reader.fieldnames
        for row in reader:
            vid = row["vehicle_id"]
            if vid not in vehicles:
                continue
            miles = float(row["miles"])
            td = parse_date(row["date"])
            cargo_kg = float(row["cargo_kg"]) if has_cargo and row.get("cargo_kg") else 0.0
            vinfo = vehicles[vid]
            mpg = vinfo["mpg"]
            fuel_type = vinfo.get("fuel_type", "gasoline").lower()
            capacity = vinfo.get("cargo_capacity_kg", 2000)
            cargo_for_calc = min(cargo_kg, capacity) if capacity else cargo_kg

            # Replicate fuel_calc formulas directly for expected (no import to avoid circular)
            fuel_base = miles / mpg if mpg>0 else 0
            factor = 1.0 + max(0.0, cargo_for_calc) * 0.0005
            fuel_adj = fuel_base * factor
            price, tax_rate = get_price(td, fuel_type)
            cost = fuel_adj * price
            cost_with_tax = fuel_adj * price * (1.0 + tax_rate)
            co2_factor = 8.887 if fuel_type == "gasoline" else 10.21
            co2 = fuel_adj * co2_factor

            pv = per_vehicle[vid]
            pv["total_miles"] += miles
            pv["total_fuel_gallons"] += fuel_base
            pv["total_fuel_adjusted"] += fuel_adj
            pv["total_cost"] += cost
            pv["total_cost_with_tax"] += cost_with_tax
            pv["total_co2_kg"] += co2
            pv["total_cargo_kg"] += cargo_kg
            pv["trip_count"] += 1

            ym = td.strftime("%Y-%m")
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

            ftb = fuel_type_breakdown[fuel_type]
            ftb["miles"] += miles
            ftb["fuel_gallons"] += fuel_adj
            ftb["cost"] += cost
            ftb["cost_with_tax"] += cost_with_tax
            ftb["co2_kg"] += co2

    for vid in per_vehicle:
        pv = per_vehicle[vid]
        pv["total_miles"] = round(pv["total_miles"], 2)
        pv["total_fuel_gallons"] = round(pv["total_fuel_gallons"], 2)
        pv["total_fuel_adjusted"] = round(pv["total_fuel_adjusted"], 2)
        pv["total_cost"] = round(pv["total_cost"], 2)
        pv["total_cost_with_tax"] = round(pv["total_cost_with_tax"], 2)
        pv["total_co2_kg"] = round(pv["total_co2_kg"], 2)
        pv["total_cargo_kg"] = round(pv["total_cargo_kg"], 2)
        pv["avg_mpg"] = round(pv["total_miles"] / pv["total_fuel_adjusted"], 2) if pv["total_fuel_adjusted"]>0 else 0.0
        pv["avg_cost_per_mile"] = round(pv["total_cost_with_tax"] / pv["total_miles"], 2) if pv["total_miles"]>0 else 0.0
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

    fleet_total_cost = round(sum(v["total_cost"] for v in per_vehicle.values()), 2)
    fleet_total_cost_with_tax = round(sum(v["total_cost_with_tax"] for v in per_vehicle.values()), 2)
    fleet_total_fuel = round(sum(v["total_fuel_adjusted"] for v in per_vehicle.values()), 2)
    fleet_total_co2 = round(sum(v["total_co2_kg"] for v in per_vehicle.values()), 2)

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
    rounded_ft = {}
    for ft, stats in fuel_type_breakdown.items():
        rounded_ft[ft] = {
            "miles": round(stats["miles"], 2),
            "fuel_gallons": round(stats["fuel_gallons"], 2),
            "cost": round(stats["cost"], 2),
            "cost_with_tax": round(stats["cost_with_tax"], 2),
            "co2_kg": round(stats["co2_kg"], 2)
        }

    most_inefficient = None
    max_ratio = -1
    for vid, stats in per_vehicle.items():
        if stats["total_miles"]>0:
            ratio = stats["total_fuel_adjusted"] / stats["total_miles"]
            if ratio > max_ratio:
                max_ratio = ratio
                most_inefficient = vid

    most_expensive = max(per_vehicle, key=lambda vid: per_vehicle[vid]["total_cost_with_tax"]) if per_vehicle else None
    highest_co2 = max(per_vehicle, key=lambda vid: per_vehicle[vid]["total_co2_kg"]) if per_vehicle else None
    most_expensive_month = max(monthly_totals, key=lambda ym: monthly_totals[ym]["cost_with_tax"]) if monthly_totals else None

    return {
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
        "fleet_total_cost": fleet_total_cost,
        "most_inefficient_vehicle": most_inefficient
    }


# === BASIC EXISTENCE ===

def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"{REPORT_PATH} must exist"


def test_report_valid_json():
    with open(REPORT_PATH) as f:
        data = json.load(f)
    assert isinstance(data, dict)


def test_report_schema():
    with open(REPORT_PATH) as f:
        data = json.load(f)
    assert "per_vehicle" in data
    assert "fleet" in data
    assert "fleet_total_cost" in data
    assert "most_inefficient_vehicle" in data
    assert isinstance(data["per_vehicle"], dict)
    assert len(data["per_vehicle"]) == 3
    # fleet keys
    fleet = data["fleet"]
    for k in ["fleet_total_cost", "fleet_total_cost_with_tax", "fleet_total_fuel_gallons", "fleet_total_co2_kg",
              "most_inefficient_vehicle", "most_expensive_vehicle", "highest_co2_vehicle", "most_expensive_month",
              "monthly_totals", "fuel_type_breakdown"]:
        assert k in fleet, f"fleet missing {k}"


# === FUEL_CALC REUSE - STRICT ===

def test_fuel_calc_still_exists_and_usable():
    assert os.path.exists(FUEL_CALC_PATH), "fuel_calc.py from step1 must still exist"
    mod = load_fuel_calc()
    for fn in ["mpg_to_l_per_100km", "l_per_100km_to_mpg", "calculate_fuel_needed", "calculate_cost",
               "miles_to_km", "km_to_miles", "gallons_to_liters", "liters_to_gallons",
               "mpg_to_km_per_liter", "calculate_fuel_needed_with_cargo",
               "calculate_co2_emissions", "calculate_cost_with_tax"]:
        assert hasattr(mod, fn), f"fuel_calc missing {fn}"
    assert abs(mod.calculate_fuel_needed(100, 25) - 4.0) < 0.001
    assert abs(mod.calculate_fuel_needed_with_cargo(100, 25, 200) - 4.4) < 0.01


def test_report_uses_fuel_calc_import_strict():
    """STRICT: Must reuse at least 3 advanced funcs from fuel_calc.py"""
    required_funcs = ["calculate_fuel_needed_with_cargo", "calculate_co2_emissions", "calculate_cost_with_tax"]
    found_funcs = set()
    found_details = []
    checked_files = []

    for py_file in Path("/app").glob("*.py"):
        if py_file.name == "fuel_calc.py":
            continue
        checked_files.append(py_file.name)
        try:
            txt = py_file.read_text()
        except:
            continue
        # AST
        try:
            import ast
            tree = ast.parse(txt)
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    for alias in node.names:
                        if "fuel_calc" in alias.name:
                            found_details.append(f"{py_file.name}: import {alias.name}")
                if isinstance(node, ast.ImportFrom):
                    if node.module and "fuel_calc" in node.module:
                        found_details.append(f"{py_file.name}: from {node.module} import")
        except:
            pass
        for fn in required_funcs + ["calculate_fuel_needed", "calculate_cost"]:
            if fn in txt and "fuel_calc" in txt:
                found_funcs.add(fn)
                found_details.append(f"{py_file.name}: uses {fn}")
        if "fuel_calc.py" in txt and "subprocess" in txt:
            found_details.append(f"{py_file.name}: subprocess fuel_calc.py")
            # Count as reuse but not specific func
            for fn in required_funcs:
                if fn in txt or "calc" in txt:
                    found_funcs.add(fn)

    missing = [fn for fn in required_funcs if fn not in found_funcs]

    assert len(found_funcs.intersection(required_funcs)) >= 3, (
        f"STRICT REUSE CHECK FAILED: Step2 must reuse at least 3 advanced functions from fuel_calc.py.\n"
        f"Required: {required_funcs}\nFound: {found_funcs}\nMissing: {missing}\n"
        f"Details: {found_details}\nChecked files: {checked_files}\n"
        f"Must import fuel_calc via importlib.util.spec_from_file_location and use "
        f"calculate_fuel_needed_with_cargo, calculate_co2_emissions, calculate_cost_with_tax, "
        f"or call via subprocess with subcommands calc/co2."
    )


# === PER VEHICLE TOTALS ===

def test_per_vehicle_totals_miles():
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    for vid in expected["per_vehicle"]:
        assert vid in actual["per_vehicle"], f"{vid} missing"
        exp = expected["per_vehicle"][vid]["total_miles"]
        act = actual["per_vehicle"][vid]["total_miles"]
        assert abs(exp - act) < 0.1, f"{vid} miles mismatch exp {exp} got {act}"


def test_per_vehicle_fuel_gallons():
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    for vid in expected["per_vehicle"]:
        exp = expected["per_vehicle"][vid]["total_fuel_gallons"]
        act = actual["per_vehicle"][vid]["total_fuel_gallons"]
        assert abs(exp - act) < 0.1, f"{vid} fuel_gallons mismatch exp {exp} got {act}"


def test_per_vehicle_fuel_adjusted():
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    for vid in expected["per_vehicle"]:
        exp = expected["per_vehicle"][vid]["total_fuel_adjusted"]
        act = actual["per_vehicle"][vid]["total_fuel_adjusted"]
        assert abs(exp - act) < 0.1, f"{vid} fuel_adjusted mismatch exp {exp} got {act}"


def test_per_vehicle_cost():
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    for vid in expected["per_vehicle"]:
        exp = expected["per_vehicle"][vid]["total_cost"]
        act = actual["per_vehicle"][vid]["total_cost"]
        assert abs(exp - act) < 0.2, f"{vid} cost mismatch exp {exp} got {act} - check fuel_type price lookup"


def test_per_vehicle_cost_with_tax():
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    for vid in expected["per_vehicle"]:
        exp = expected["per_vehicle"][vid]["total_cost_with_tax"]
        act = actual["per_vehicle"][vid]["total_cost_with_tax"]
        assert abs(exp - act) < 0.2, f"{vid} cost_with_tax mismatch exp {exp} got {act} - must use tax_rate"


def test_per_vehicle_co2():
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    for vid in expected["per_vehicle"]:
        exp = expected["per_vehicle"][vid]["total_co2_kg"]
        act = actual["per_vehicle"][vid]["total_co2_kg"]
        assert abs(exp - act) < 0.5, f"{vid} co2 mismatch exp {exp} got {act}"


def test_cargo_adjusted_fuel_greater_than_base():
    with open(REPORT_PATH) as f:
        data = json.load(f)
    for vid, stats in data["per_vehicle"].items():
        # With cargo, adjusted should be >= base (since factor >=1)
        assert stats["total_fuel_adjusted"] >= stats["total_fuel_gallons"] - 0.01, \
            f"{vid} cargo adjusted fuel {stats['total_fuel_adjusted']} should be >= base {stats['total_fuel_gallons']} - cargo penalty missing"


def test_co2_diesel_vs_gasoline_factor():
    mod = load_fuel_calc()
    # gasoline factor 8.887, diesel 10.21
    assert abs(mod.calculate_co2_emissions(10, "gasoline") - 88.87) < 0.1
    assert abs(mod.calculate_co2_emissions(10, "diesel") - 102.1) < 0.1
    # report: diesel vehicles should have higher co2 per fuel than gasoline for same fuel amount
    with open(REPORT_PATH) as f:
        data = json.load(f)
    # Check per vehicle co2 per fuel ratio
    for vid, stats in data["per_vehicle"].items():
        if stats["total_fuel_adjusted"]>0:
            ratio = stats["total_co2_kg"] / stats["total_fuel_adjusted"]
            # gasoline ratio ~8.887, diesel ~10.21
            assert 8.0 < ratio < 11.0, f"{vid} co2 ratio {ratio} out of expected range"


def test_cost_with_tax_includes_tax():
    with open(REPORT_PATH) as f:
        data = json.load(f)
    for vid, stats in data["per_vehicle"].items():
        assert stats["total_cost_with_tax"] >= stats["total_cost"] - 0.01, \
            f"{vid} cost_with_tax {stats['total_cost_with_tax']} should be >= cost {stats['total_cost']}"


def test_fleet_total_cost():
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    assert abs(expected["fleet"]["fleet_total_cost"] - actual["fleet"]["fleet_total_cost"]) < 0.3
    assert abs(expected["fleet"]["fleet_total_cost_with_tax"] - actual["fleet"]["fleet_total_cost_with_tax"]) < 0.3


def test_most_inefficient_vehicle():
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    assert actual["most_inefficient_vehicle"] == expected["most_inefficient_vehicle"]
    assert actual["fleet"]["most_inefficient_vehicle"] == expected["fleet"]["most_inefficient_vehicle"]
    # With cargo, V003 lowest mpg still most inefficient
    assert actual["most_inefficient_vehicle"] == "V003"


def test_most_expensive_and_highest_co2():
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    assert actual["fleet"]["most_expensive_vehicle"] == expected["fleet"]["most_expensive_vehicle"]
    assert actual["fleet"]["highest_co2_vehicle"] == expected["fleet"]["highest_co2_vehicle"]
    assert actual["fleet"]["most_expensive_month"] == expected["fleet"]["most_expensive_month"]


# === PRICE LOOKUP 2D ===

def test_price_lookup_2d_fuel_type():
    """Fuel_type filtering: gasoline and diesel prices differ on same date"""
    with open(PRICES_PATH) as f:
        reader = csv.DictReader(f)
        prices = list(reader)
    # Find same date with both fuel types
    from collections import defaultdict
    by_date = defaultdict(dict)
    for row in prices:
        by_date[row["date"]][row["fuel_type"]] = float(row["price_per_gallon"])
    for date, d in by_date.items():
        if "gasoline" in d and "diesel" in d:
            assert abs(d["gasoline"] - d["diesel"]) > 0.1, f"Prices should differ per fuel_type on {date}"
            break


def test_price_lookup_2024_01_04_gasoline_3_52():
    trip_date = parse_date("2024-01-04")
    with open(PRICES_PATH) as f:
        reader = csv.DictReader(f)
        grouped = defaultdict(list)
        for row in reader:
            ft = row["fuel_type"].lower()
            grouped[ft].append((parse_date(row["date"]), float(row["price_per_gallon"]), float(row.get("tax_rate",0))))
        for ft in grouped:
            grouped[ft].sort(key=lambda x: x[0])
    # gasoline
    cand = None
    for pd, pp, pt in grouped["gasoline"]:
        if pd <= trip_date:
            cand = pp
        else:
            break
    assert cand is not None
    assert abs(cand - 3.52) < 0.001, (
        f"PRICE LOOKUP FAILED: Gasoline trip on 2024-01-04 must use gasoline price from 2024-01-03 $3.52, got {cand}. "
        f"Use most recent <= per fuel_type."
    )


def test_price_lookup_2024_01_04_diesel_4_05():
    trip_date = parse_date("2024-01-04")
    with open(PRICES_PATH) as f:
        reader = csv.DictReader(f)
        grouped = defaultdict(list)
        for row in reader:
            ft = row["fuel_type"].lower()
            grouped[ft].append((parse_date(row["date"]), float(row["price_per_gallon"]), float(row.get("tax_rate",0))))
        for ft in grouped:
            grouped[ft].sort(key=lambda x: x[0])
    cand = None
    for pd, pp, pt in grouped["diesel"]:
        if pd <= trip_date:
            cand = pp
        else:
            break
    assert abs(cand - 4.05) < 0.001, (
        f"PRICE LOOKUP FAILED: Diesel trip on 2024-01-04 must use diesel price from 2024-01-03 $4.05, got {cand}. "
        f"Must filter by fuel_type AND most recent <= date."
    )
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    # V002 diesel has trip on 2024-01-04
    exp = expected["per_vehicle"]["V002"]["total_cost"]
    act = actual["per_vehicle"]["V002"]["total_cost"]
    assert abs(exp - act) < 0.3, f"V002 cost mismatch indicates diesel price lookup bug exp {exp} got {act}"


def test_price_lookup_fallback_before_first_price():
    early = parse_date("2023-12-31")
    with open(PRICES_PATH) as f:
        reader = csv.DictReader(f)
        grouped = defaultdict(list)
        for row in reader:
            ft = row["fuel_type"].lower()
            grouped[ft].append((parse_date(row["date"]), float(row["price_per_gallon"]), float(row.get("tax_rate",0))))
        for ft in grouped:
            grouped[ft].sort(key=lambda x: x[0])
    for ft, expected_first_price in [("gasoline", 3.45), ("diesel", 3.95)]:
        cand = None
        for pd, pp, pt in grouped[ft]:
            if pd <= early:
                cand = pp
            else:
                break
        if cand is None:
            cand = grouped[ft][0][1]
        assert abs(cand - expected_first_price) < 0.001, \
            f"Fallback for {ft} on 2023-12-31 should be {expected_first_price}, got {cand}"


# === MONTHLY & FUEL TYPE BREAKDOWN ===

def test_monthly_breakdown_exists():
    expected = compute_expected()
    with open(REPORT_PATH) as f:
        actual = json.load(f)
    for vid in expected["per_vehicle"]:
        assert "monthly_breakdown" in actual["per_vehicle"][vid], f"{vid} missing monthly_breakdown"
        exp_mb = expected["per_vehicle"][vid]["monthly_breakdown"]
        act_mb = actual["per_vehicle"][vid]["monthly_breakdown"]
        for ym in exp_mb:
            assert ym in act_mb, f"{vid} missing month {ym}"
            assert abs(exp_mb[ym]["miles"] - act_mb[ym]["miles"]) < 0.1
    # fleet monthly_totals should have 2023-12 and 2024-01
    assert "2023-12" in actual["fleet"]["monthly_totals"], "monthly_totals should include 2023-12 fallback month"
    assert "2024-01" in actual["fleet"]["monthly_totals"]


def test_fuel_type_breakdown():
    with open(REPORT_PATH) as f:
        data = json.load(f)
    assert "fuel_type_breakdown" in data["fleet"]
    fb = data["fleet"]["fuel_type_breakdown"]
    assert "gasoline" in fb
    assert "diesel" in fb
    assert fb["gasoline"]["miles"] > 0
    assert fb["diesel"]["miles"] > 0


def test_rounding_to_2_decimals():
    with open(REPORT_PATH) as f:
        data = json.load(f)
    for vid, stats in data["per_vehicle"].items():
        for k in ["total_miles", "total_fuel_gallons", "total_fuel_adjusted", "total_cost", "total_cost_with_tax", "total_co2_kg"]:
            val = stats[k]
            assert abs(val - round(val, 2)) < 0.001, f"{vid} {k} not rounded to 2 dec: {val}"


def test_report_not_hardcoded_empty():
    with open(REPORT_PATH) as f:
        data = json.load(f)
    assert data["fleet"]["fleet_total_cost"] > 100
    assert data["fleet"]["fleet_total_cost_with_tax"] > 100
    assert data["fleet"]["fleet_total_fuel_gallons"] > 0
    assert data["fleet"]["fleet_total_co2_kg"] > 100
