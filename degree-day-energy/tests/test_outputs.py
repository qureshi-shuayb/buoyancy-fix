"""
Black-box grader for the degree-day energy estimator.

Imports the agent's module from /app/degree_days.py via importlib and compares its
outputs against an INDEPENDENT reference computed inside this test (the golden values
never import the agent's code). Synthetic hourly climates are generated deterministically
from a fixed seed, with a strong diurnal swing so that temperatures cross the balance
point *within* a day -- this is what separates a correct PER-HOUR degree-day
accumulation from a naive PER-DAY (daily-mean) one. Multiple balance points plus
all-heating and all-cooling climates exercise the sign convention, the
degree-hours -> degree-days conversion, the UA thermal-energy formula, and the
efficiency division.
"""
import csv
import importlib.util
import math
import os
import random
import tempfile

import pytest

# ---------------------------------------------------------------------------
# Load the agent's module from /app without requiring it to be on sys.path.
# ---------------------------------------------------------------------------
AGENT_PATH = "/app/degree_days.py"


def _load_agent():
    spec = importlib.util.spec_from_file_location("agent_degree_days", AGENT_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


agent = _load_agent()

HOURS = 8760
REL = 1e-6   # both sides use the same formula, so the tolerance can be tight
ABS = 1e-6


def approx(x):
    return pytest.approx(x, rel=REL, abs=ABS)


# ---------------------------------------------------------------------------
# Independent reference implementation (NOT imported from the agent).
# ---------------------------------------------------------------------------
def ref_hdd(temps, bp):
    total = 0.0
    for t in temps:
        diff = bp - t
        if diff > 0.0:
            total += diff
    return total / 24.0


def ref_cdd(temps, bp):
    total = 0.0
    for t in temps:
        diff = t - bp
        if diff > 0.0:
            total += diff
    return total / 24.0


def ref_energy(temps, bp, UA, heating_eff, cooling_cop):
    hdd = ref_hdd(temps, bp)
    cdd = ref_cdd(temps, bp)
    heating_thermal_kwh = UA * hdd * 24.0 / 1000.0
    cooling_thermal_kwh = UA * cdd * 24.0 / 1000.0
    return {
        "heating_kwh": heating_thermal_kwh / heating_eff,
        "cooling_kwh": cooling_thermal_kwh / cooling_cop,
    }


# A naive PER-DAY estimator (daily mean, then threshold) -- used ONLY to assert that
# the chosen climates/balance points actually separate it from the per-hour answer,
# so the fail-signal is guaranteed to exist. The agent is never graded against this.
def naive_perday_hdd(temps, bp):
    total = 0.0
    for d in range(0, len(temps), 24):
        day = temps[d:d + 24]
        mean = sum(day) / len(day)
        if bp - mean > 0.0:
            total += bp - mean
    return total


# ---------------------------------------------------------------------------
# Deterministic synthetic climates.
# ---------------------------------------------------------------------------
def make_climate(seed, annual_mean, annual_amp, diurnal_amp, noise):
    """Seasonal sinusoid (period = year) + diurnal sinusoid (period = 24h) + noise."""
    rng = random.Random(seed)
    temps = []
    for h in range(HOURS):
        seasonal = annual_mean - annual_amp * math.cos(2.0 * math.pi * h / HOURS)
        diurnal = diurnal_amp * math.sin(2.0 * math.pi * (h % 24) / 24.0)
        temps.append(seasonal + diurnal + rng.uniform(-noise, noise))
    return temps


# A temperate climate whose temperatures repeatedly cross a mid-range balance point
# within each day (so per-hour != per-day).
TEMPERATE = make_climate(seed=1234, annual_mean=12.0, annual_amp=12.0,
                         diurnal_amp=7.0, noise=1.5)
# A cold climate that stays well below typical balance points all year (all-heating).
COLD = make_climate(seed=99, annual_mean=-10.0, annual_amp=6.0,
                    diurnal_amp=3.0, noise=1.0)
# A hot climate that stays well above typical balance points all year (all-cooling).
HOT = make_climate(seed=7, annual_mean=34.0, annual_amp=4.0,
                   diurnal_amp=3.0, noise=1.0)


def write_csv(temps):
    fd, path = tempfile.mkstemp(suffix=".csv")
    with os.fdopen(fd, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["hour", "temp_c"])
        for h, t in enumerate(temps):
            w.writerow([h, repr(t)])
    return path


# ===========================================================================
# Contract / IO
# ===========================================================================
def test_read_temps_roundtrip_small():
    vals = [4.1, 3.7, -2.5, 0.0, 18.25]
    path = write_csv(vals)
    try:
        got = agent.read_temps(path)
    finally:
        os.remove(path)
    assert isinstance(got, list)
    assert len(got) == len(vals)
    for a, b in zip(got, vals):
        assert float(a) == approx(b)


def test_read_temps_full_year_length():
    path = write_csv(TEMPERATE)
    try:
        got = agent.read_temps(path)
    finally:
        os.remove(path)
    assert len(got) == HOURS
    assert got[0] == approx(TEMPERATE[0])
    assert got[-1] == approx(TEMPERATE[-1])


def test_annual_energy_returns_expected_keys():
    out = agent.annual_energy_kwh(TEMPERATE, 16.0, 250.0, 0.95, 3.5)
    assert set(out.keys()) >= {"heating_kwh", "cooling_kwh"}


# ===========================================================================
# Degree days across multiple balance points (per-hour accumulation)
# ===========================================================================
@pytest.mark.parametrize("bp", [10.0, 15.5, 18.0, 21.0])
def test_hdd_matches_reference(bp):
    assert agent.heating_degree_days(TEMPERATE, bp) == approx(ref_hdd(TEMPERATE, bp))


@pytest.mark.parametrize("bp", [10.0, 15.5, 18.0, 21.0])
def test_cdd_matches_reference(bp):
    assert agent.cooling_degree_days(TEMPERATE, bp) == approx(ref_cdd(TEMPERATE, bp))


def test_degree_days_units_are_days_not_hours():
    """HDD/CDD must be reported in degC*day. The per-hour sum divided by 24 differs
    from the un-divided degC*hour sum by a factor of 24; pin the days convention."""
    bp = 16.0
    hdd = agent.heating_degree_days(TEMPERATE, bp)
    degree_hours = sum(max(0.0, bp - t) for t in TEMPERATE)
    assert hdd == approx(degree_hours / 24.0)
    assert abs(hdd - degree_hours) > 1.0   # not the un-converted degree-hours value


# ===========================================================================
# Per-hour vs per-day fail signal: the temperate climate + mid balance point
# must make the two methods disagree materially.
# ===========================================================================
def test_perhour_differs_from_perday_reference():
    bp = 16.0
    per_hour = ref_hdd(TEMPERATE, bp)
    per_day = naive_perday_hdd(TEMPERATE, bp)
    # The two methods must differ by a clear margin for this climate/balance point,
    # otherwise the task would not distinguish a per-hour from a per-day solution.
    assert abs(per_hour - per_day) / per_hour > 0.05
    # And the agent must match the per-hour value, not the per-day one.
    got = agent.heating_degree_days(TEMPERATE, bp)
    assert got == approx(per_hour)
    assert abs(got - per_day) > 1.0


# ===========================================================================
# Sign convention: all-heating and all-cooling climates
# ===========================================================================
def test_cold_climate_is_all_heating():
    bp = 18.0
    assert min(COLD) < bp and max(COLD) < bp   # sanity: entirely below balance point
    assert agent.cooling_degree_days(COLD, bp) == approx(0.0)
    assert agent.heating_degree_days(COLD, bp) == approx(ref_hdd(COLD, bp))
    assert agent.heating_degree_days(COLD, bp) > 0.0


def test_hot_climate_is_all_cooling():
    bp = 18.0
    assert min(HOT) > bp and max(HOT) > bp   # sanity: entirely above balance point
    assert agent.heating_degree_days(HOT, bp) == approx(0.0)
    assert agent.cooling_degree_days(HOT, bp) == approx(ref_cdd(HOT, bp))
    assert agent.cooling_degree_days(HOT, bp) > 0.0


def test_degree_days_never_negative():
    for bp in (-20.0, 0.0, 12.0, 25.0, 50.0):
        assert agent.heating_degree_days(TEMPERATE, bp) >= -ABS
        assert agent.cooling_degree_days(TEMPERATE, bp) >= -ABS


# ===========================================================================
# Annual energy: UA thermal formula + efficiency division
# ===========================================================================
@pytest.mark.parametrize(
    "bp,UA,heating_eff,cooling_cop",
    [
        (16.0, 250.0, 0.95, 3.5),
        (18.0, 180.0, 3.2, 4.0),
        (20.0, 400.0, 0.80, 2.8),
        (14.5, 120.5, 1.00, 3.0),
    ],
)
def test_annual_energy_matches_reference(bp, UA, heating_eff, cooling_cop):
    out = agent.annual_energy_kwh(TEMPERATE, bp, UA, heating_eff, cooling_cop)
    exp = ref_energy(TEMPERATE, bp, UA, heating_eff, cooling_cop)
    assert out["heating_kwh"] == approx(exp["heating_kwh"])
    assert out["cooling_kwh"] == approx(exp["cooling_kwh"])


def test_efficiency_divides_thermal_load():
    """Holding everything else fixed, halving the efficiency must double the delivered
    energy -- pins that efficiency DIVIDES the thermal load (not multiplies)."""
    bp, UA = 16.0, 250.0
    base = agent.annual_energy_kwh(TEMPERATE, bp, UA, 1.0, 1.0)
    half = agent.annual_energy_kwh(TEMPERATE, bp, UA, 0.5, 0.5)
    assert half["heating_kwh"] == approx(2.0 * base["heating_kwh"])
    assert half["cooling_kwh"] == approx(2.0 * base["cooling_kwh"])
    # With unit efficiency, delivered == thermal == UA * DD * 24 / 1000.
    assert base["heating_kwh"] == approx(UA * ref_hdd(TEMPERATE, bp) * 24.0 / 1000.0)
    assert base["cooling_kwh"] == approx(UA * ref_cdd(TEMPERATE, bp) * 24.0 / 1000.0)


def test_cop_above_one_reduces_electricity_below_thermal():
    """A heat pump / chiller with COP > 1 delivers less electrical energy than the
    thermal load it moves."""
    bp, UA = 16.0, 300.0
    out = agent.annual_energy_kwh(TEMPERATE, bp, UA, 3.0, 4.0)
    heating_thermal = UA * ref_hdd(TEMPERATE, bp) * 24.0 / 1000.0
    cooling_thermal = UA * ref_cdd(TEMPERATE, bp) * 24.0 / 1000.0
    assert out["heating_kwh"] == approx(heating_thermal / 3.0)
    assert out["cooling_kwh"] == approx(cooling_thermal / 4.0)
    assert out["heating_kwh"] < heating_thermal
    assert out["cooling_kwh"] < cooling_thermal


def test_cold_climate_energy_cooling_zero():
    out = agent.annual_energy_kwh(COLD, 18.0, 200.0, 0.9, 3.0)
    exp = ref_energy(COLD, 18.0, 200.0, 0.9, 3.0)
    assert out["cooling_kwh"] == approx(0.0)
    assert out["heating_kwh"] == approx(exp["heating_kwh"])


def test_hot_climate_energy_heating_zero():
    out = agent.annual_energy_kwh(HOT, 18.0, 200.0, 0.9, 3.0)
    exp = ref_energy(HOT, 18.0, 200.0, 0.9, 3.0)
    assert out["heating_kwh"] == approx(0.0)
    assert out["cooling_kwh"] == approx(exp["cooling_kwh"])


def test_end_to_end_from_csv():
    """Full pipeline: read the CSV the agent parses, then estimate energy, against the
    independent reference over the parsed values."""
    path = write_csv(TEMPERATE)
    try:
        temps = agent.read_temps(path)
    finally:
        os.remove(path)
    out = agent.annual_energy_kwh(temps, 17.0, 275.0, 0.92, 3.3)
    exp = ref_energy(TEMPERATE, 17.0, 275.0, 0.92, 3.3)
    assert out["heating_kwh"] == approx(exp["heating_kwh"])
    assert out["cooling_kwh"] == approx(exp["cooling_kwh"])
