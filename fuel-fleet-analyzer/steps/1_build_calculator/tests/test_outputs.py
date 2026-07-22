import os
import sys
import subprocess
import importlib.util
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
    assert hasattr(mod, "mpg_to_l_per_100km")
    assert hasattr(mod, "l_per_100km_to_mpg")
    assert hasattr(mod, "calculate_fuel_needed")
    assert hasattr(mod, "calculate_cost")


def test_mpg_to_l100():
    mod = load_fuel_calc()
    # 235.215 / 23.5215 = 10.0, and 235.215 / 23.5 ≈ 10.009
    result = mod.mpg_to_l_per_100km(23.5)
    assert abs(result - 10.009148) < 0.05, f"mpg_to_l_per_100km(23.5) should be ~10.00, got {result}"
    assert abs(mod.mpg_to_l_per_100km(10.0) - 23.5215) < 0.01


def test_l100_to_mpg():
    mod = load_fuel_calc()
    result = mod.l_per_100km_to_mpg(10.0)
    assert abs(result - 23.5215) < 0.05
    # roundtrip
    orig = 22.5
    l100 = mod.mpg_to_l_per_100km(orig)
    back = mod.l_per_100km_to_mpg(l100)
    assert abs(back - orig) < 0.001


def test_calculate_fuel_needed():
    mod = load_fuel_calc()
    assert abs(mod.calculate_fuel_needed(100, 25) - 4.0) < 0.001
    assert abs(mod.calculate_fuel_needed(0, 25) - 0.0) < 0.001
    assert abs(mod.calculate_fuel_needed(120.5, 22.5) - (120.5/22.5)) < 0.001


def test_calculate_cost():
    mod = load_fuel_calc()
    assert abs(mod.calculate_cost(4.0, 3.5) - 14.0) < 0.001
    assert abs(mod.calculate_cost(0, 3.5) - 0.0) < 0.001


def test_cli_help():
    result = subprocess.run([sys.executable, FUEL_CALC_PATH, "--help"],
                            capture_output=True, text=True, timeout=5)
    assert result.returncode == 0
    out = result.stdout + result.stderr
    assert "--distance" in out
    assert "--mpg" in out


def test_cli_fuel_calculation():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "--distance", "100", "--mpg", "25", "--price", "3.5"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, f"CLI failed: {result.stderr}"
    out = result.stdout
    # Should contain fuel 4.00 and cost $14.00
    assert "4.00" in out, f"Expected fuel 4.00 in output, got {out}"
    assert "14.00" in out, f"Expected cost 14.00 in output, got {out}"


def test_cli_fuel_calculation_realistic():
    # From trips data: 120.5 miles, 22.5 mpg, price 3.45 => fuel 5.355..., cost 18.476...
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "--distance", "120.5", "--mpg", "22.5", "--price", "3.45"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    assert "5.36" in result.stdout  # rounded to 2 dec
    assert "18.48" in result.stdout or "18.47" in result.stdout  # allow rounding diff


def test_cli_conversion_mpg_to_l100():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "--from-unit", "mpg", "--to-unit", "l100km", "--value", "23.5215"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    val = float(result.stdout.strip())
    assert abs(val - 10.0) < 0.05, f"Expected ~10.0, got {val}"


def test_cli_conversion_l100_to_mpg():
    result = subprocess.run(
        [sys.executable, FUEL_CALC_PATH, "--from-unit", "l100km", "--to-unit", "mpg", "--value", "10"],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0
    val = float(result.stdout.strip())
    assert abs(val - 23.5215) < 0.1


# === NEGATIVE TESTS AGAINST OVER-EXECUTION ===
# These ensure step 1 does NOT already create artifacts from step 2
# Identifiers are from steps/2_fleet_report/instruction.md: report.json, most_inefficient_vehicle, fleet_total_cost

def test_step1_does_NOT_create_report_json():
    assert not os.path.exists("/app/report.json"), "Step 1 must NOT create /app/report.json (that's step 2's artifact)"


def test_step1_does_NOT_create_most_inefficient_marker():
    # Ensure no report files that would indicate step 2 over-execution
    for path in ["/app/report.json", "/app/fleet_report.json", "/app/costs.json"]:
        assert not os.path.exists(path), f"{path} must not exist after step 1"


def test_step1_does_NOT_contain_fleet_aggregation_logic():
    # We allow import in fuel_calc but file should not contain fleet report keys implementation as top-level
    # Check that report.json would need to be created by reading data files - ensure step1 didn't pre-generate it
    # This is a filesystem check, not code inspection
    assert not os.path.exists("/app/report.json")
    # Also ensure per_vehicle aggregation file not created
    assert not os.path.exists("/app/per_vehicle.json")
