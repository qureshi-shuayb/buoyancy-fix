import os
import sys
import subprocess
import importlib.util
import json
import pytest

FUEL_CALC_PATH = "/app/fuel_calc.py"


def load_fuel_calc():
    spec = importlib.util.spec_from_file_location("fuel_calc", FUEL_CALC_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_fuel_calc_file_exists():
    assert os.path.exists(FUEL_CALC_PATH), f"{FUEL_CALC_PATH} must exist"


def test_fuel_calc_executable():
    assert os.access(FUEL_CALC_PATH, os.X_OK) or os.path.exists(FUEL_CALC_PATH)


def test_functions_exist():
    mod = load_fuel_calc()
    for fn in ["mpg_to_l_per_100km", "l_per_100km_to_mpg", "calculate_fuel_needed", "calculate_cost",
               "miles_to_km", "km_to_miles", "gallons_to_liters", "liters_to_gallons",
               "mpg_to_km_per_liter", "calculate_fuel_needed_with_cargo",
               "calculate_co2_emissions", "calculate_cost_with_tax"]:
        assert hasattr(mod, fn), f"Missing function {fn}"


def test_docstrings_exist():
    mod = load_fuel_calc()
    for fn in ["mpg_to_l_per_100km", "calculate_fuel_needed_with_cargo", "calculate_co2_emissions"]:
        assert getattr(mod, fn).__doc__, f"{fn} should have docstring"


# Original functions
def test_mpg_to_l100():
    mod = load_fuel_calc()
    result = mod.mpg_to_l_per_100km(23.5)
    assert abs(result - 10.009148) < 0.05
    assert abs(mod.mpg_to_l_per_100km(10.0) - 23.5215) < 0.01


def test_l100_to_mpg():
    mod = load_fuel_calc()
    result = mod.l_per_100km_to_mpg(10.0)
    assert abs(result - 23.5215) < 0.05
    orig = 22.5
    l100 = mod.mpg_to_l_per_100km(orig)
    back = mod.l_per_100km_to_mpg(l100)
    assert abs(back - orig) < 0.001


def test_calculate_fuel_needed():
    mod = load_fuel_calc()
    assert abs(mod.calculate_fuel_needed(100, 25) - 4.0) < 0.001
    assert abs(mod.calculate_fuel_needed(0, 25) - 0.0) < 0.001


def test_calculate_cost():
    mod = load_fuel_calc()
    assert abs(mod.calculate_cost(4.0, 3.5) - 14.0) < 0.001


# New unit conversions
def test_miles_to_km():
    mod = load_fuel_calc()
    assert abs(mod.miles_to_km(100) - 160.934) < 0.05
    assert abs(mod.miles_to_km(0) - 0.0) < 0.001
    try:
        mod.miles_to_km(-1)
        assert False, "Should raise ValueError for negative"
    except ValueError:
        pass


def test_km_to_miles():
    mod = load_fuel_calc()
    assert abs(mod.km_to_miles(160.934) - 100.0) < 0.05


def test_gallons_to_liters():
    mod = load_fuel_calc()
    assert abs(mod.gallons_to_liters(10) - 37.8541) < 0.05


def test_liters_to_gallons():
    mod = load_fuel_calc()
    assert abs(mod.liters_to_gallons(37.8541) - 10.0) < 0.05


def test_mpg_to_kmpl():
    mod = load_fuel_calc()
    assert abs(mod.mpg_to_km_per_liter(23.5215) - 10.0) < 0.05


# Cargo and CO2 and tax
def test_calculate_fuel_needed_with_cargo():
    mod = load_fuel_calc()
    base = mod.calculate_fuel_needed_with_cargo(100, 25, 0)
    assert abs(base - 4.0) < 0.01
    with_cargo = mod.calculate_fuel_needed_with_cargo(100, 25, 200)
    # 200kg *0.0005=0.1 factor => 4.0*1.1=4.4
    assert abs(with_cargo - 4.4) < 0.01
    assert with_cargo > base
    try:
        mod.calculate_fuel_needed_with_cargo(100, 25, -5)
        assert False
    except ValueError:
        pass
    try:
        mod.calculate_fuel_needed_with_cargo(100, 0, 100)
        assert False
    except ValueError:
        pass


def test_calculate_co2_emissions():
    mod = load_fuel_calc()
    assert abs(mod.calculate_co2_emissions(10, "gasoline") - 88.87) < 0.05
    assert abs(mod.calculate_co2_emissions(10, "diesel") - 102.1) < 0.05
    assert abs(mod.calculate_co2_emissions(10, "GASOLINE") - 88.87) < 0.05  # case insensitive
    try:
        mod.calculate_co2_emissions(10, "electric")
        assert False
    except ValueError:
        pass
    try:
        mod.calculate_co2_emissions(-1, "gasoline")
        assert False
    except ValueError:
        pass


def test_calculate_cost_with_tax():
    mod = load_fuel_calc()
    assert abs(mod.calculate_cost_with_tax(10, 3.5, 0.0) - 35.0) < 0.001
    assert abs(mod.calculate_cost_with_tax(10, 3.5, 0.08) - 37.8) < 0.01
    assert abs(mod.calculate_cost_with_tax(4.4, 3.5, 0.08) - 16.632) < 0.01
    try:
        mod.calculate_cost_with_tax(10, 3.5, 1.5)
        assert False
    except ValueError:
        pass


# CLI help
def test_cli_help():
    result = subprocess.run([sys.executable, FUEL_CALC_PATH, "--help"],
                            capture_output=True, text=True, timeout=5)
    assert result.returncode == 0
    out = result.stdout + result.stderr
    assert "convert" in out.lower()
    assert "calc" in out.lower()
    assert "co2" in out.lower()


def test_cli_help_calc_mentions_distance():
    result = subprocess.run([sys.executable, FUEL_CALC_PATH, "calc", "--help"],
                            capture_output=True, text=True, timeout=5)
    assert result.returncode == 0
    out = result.stdout + result.stderr
    assert "--distance" in out
    assert "--cargo" in out.lower()


# Convert subcommand
def test_cli_convert_mpg_to_l100():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "convert", "--from-unit", "mpg", "--to-unit", "l100km", "--value", "23.5215"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, result.stderr
    val = float(result.stdout.strip())
    assert abs(val - 10.0) < 0.05


def test_cli_convert_miles_to_km():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "convert", "--from-unit", "miles", "--to-unit", "km", "--value", "100"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    val = float(result.stdout.strip())
    assert abs(val - 160.93) < 0.1


def test_cli_convert_gallons_to_liters():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "convert", "--from-unit", "gallons", "--to-unit", "liters", "--value", "10"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    val = float(result.stdout.strip())
    assert abs(val - 37.85) < 0.1


def test_cli_convert_same_unit():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "convert", "--from-unit", "mpg", "--to-unit", "mpg", "--value", "25"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    assert "25.00" in result.stdout


def test_cli_convert_kmpl_to_mpg():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "convert", "--from-unit", "kmpl", "--to-unit", "mpg", "--value", "10"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    val = float(result.stdout.strip())
    assert abs(val - 23.52) < 0.1


# Calc subcommand
def test_cli_calc_text_default():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "calc", "--distance", "100", "--mpg", "25", "--price", "3.5"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, result.stderr
    out = result.stdout
    assert "4.00" in out
    assert "14.00" in out
    assert "35.55" in out or "CO2" in out


def test_cli_calc_with_cargo():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "calc", "--distance", "100", "--mpg", "25", "--price", "3.5", "--cargo", "200"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    # 4.4 fuel
    assert "4.40" in result.stdout


def test_cli_calc_with_tax():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "calc", "--distance", "100", "--mpg", "25", "--price", "3.5", "--tax-rate", "0.08"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    # cost with tax 4*3.5*1.08=15.12
    assert "15.12" in result.stdout


def test_cli_calc_json():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "calc", "--distance", "100", "--mpg", "25", "--price", "3.5",
         "--cargo", "200", "--fuel-type", "diesel", "--tax-rate", "0.08", "--output-format", "json"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout.strip())
    assert "fuel_gallons" in data
    assert "cost" in data
    assert "co2_kg" in data
    assert abs(data["fuel_gallons"] - 4.4) < 0.01
    assert abs(data["cost"] - 16.63) < 0.05
    # diesel co2 4.4*10.21=44.92
    assert abs(data["co2_kg"] - 44.92) < 0.1


def test_cli_calc_diesel_co2_greater():
    res_gas = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "calc", "--distance", "100", "--mpg", "25", "--price", "3.5", "--fuel-type", "gasoline", "--output-format", "json"],
        capture_output=True, text=True, timeout=5
    )
    res_diesel = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "calc", "--distance", "100", "--mpg", "25", "--price", "3.5", "--fuel-type", "diesel", "--output-format", "json"],
        capture_output=True, text=True, timeout=5
    )
    gas = json.loads(res_gas.stdout.strip())
    diesel = json.loads(res_diesel.stdout.strip())
    assert diesel["co2_kg"] > gas["co2_kg"]


# CO2 subcommand
def test_cli_co2_gasoline():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "co2", "--fuel", "10", "--fuel-type", "gasoline"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    assert "88.87" in result.stdout


def test_cli_co2_diesel():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "co2", "--fuel", "10", "--fuel-type", "diesel"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    assert "102.1" in result.stdout


def test_cli_co2_json():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "co2", "--fuel", "10", "--fuel-type", "diesel", "--output-format", "json"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    data = json.loads(result.stdout.strip())
    assert abs(data["co2_kg"] - 102.1) < 0.1


# Legacy flat mode still should work for backward compat
def test_cli_legacy_flat_fuel():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "--distance", "100", "--mpg", "25", "--price", "3.5"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    assert "4.00" in result.stdout


# Negative tests
def test_step1_does_NOT_create_report_json():
    assert not os.path.exists("/app/report.json"), "Step 1 must NOT create /app/report.json"


def test_step1_does_NOT_create_most_inefficient_marker():
    for path in ["/app/report.json", "/app/fleet_report.json", "/app/costs.json"]:
        assert not os.path.exists(path), f"{path} must not exist after step 1"


def test_step1_does_NOT_contain_fleet_aggregation_logic():
    assert not os.path.exists("/app/report.json")
    assert not os.path.exists("/app/per_vehicle.json")
