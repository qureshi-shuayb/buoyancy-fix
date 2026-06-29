# Psychrometrics Library

Implement a small **psychrometrics** library for moist (humid) air in **SI units**.
Psychrometrics relates the temperature, moisture content, and energy of humid air —
the core math behind HVAC sizing, drying, and weather calculations.

## Where to put your code

Create a single module at exactly:

```
/app/psychrometrics.py
```

It must expose the six functions below as **module-level functions** with exactly
these names and signatures. Each function must accept either a scalar float/int **or** a list/tuple of numbers and return the same shape (scalar -> scalar float, list/tuple -> list of floats same length). Scalar arguments broadcast across list arguments elementwise. Use only Python standard library `math`, no numpy or similar.

## Units and conventions

- All temperatures are in **degrees Celsius (°C)**.
- All pressures are in **pascals (Pa)**.
- Atmospheric pressure `p` defaults to **101325 Pa** (sea level) and is passed
  explicitly for altitude cases.
- **Humidity ratio** `W` is in **kg water vapor / kg dry air**.
- **Relative humidity** `rh` is a fraction in **[0, 1]** (not a percentage).
- **Enthalpy** is in **kJ / kg dry air**.

## Required functions

```python
def sat_pressure(t_db):
    """Saturation vapor pressure over water [Pa] at dry-bulb temperature t_db [°C]."""

def hum_ratio_from_rh(t_db, rh, p=101325):
    """Humidity ratio W [kg/kg dry air]."""

def rh_from_hum_ratio(t_db, w, p=101325):
    """Relative humidity [0..1]."""

def dew_point(t_db, rh, p=101325):
    """Dew-point temperature [°C]."""

def enthalpy(t_db, w):
    """Moist-air specific enthalpy [kJ/kg dry air]."""

def wet_bulb(t_db, rh, p=101325):
    """Wet-bulb temperature [°C], solved iteratively."""
```

## Governing relations

- **Vectorized API**: each function must accept scalar float/int or list/tuple and return same shape. If any argument is a list/tuple, apply elementwise with scalar broadcasting for other arguments. Use only `math` module, no numpy. Output type must match input container type shape: scalar in -> scalar float out, list/tuple in -> list out same length. This breaks standard single-value recall implementations from the web.

- **Saturation pressure** `sat_pressure(t_db)` must follow the ASHRAE/Hyland–Wexler
  saturation-pressure correlation (a log-polynomial in absolute temperature) with
  separate over-ice branch for t <= 0 °C and over-water branch for t > 0 °C,
  **then multiplied by the task-specified enhancement factor**:

  ```
  f_e(t) = 1 + A + B*t + C*t^2
  A = 0.0014
  B = -0.000021
  C = 0.00000037
  p_ws_enhanced(t) = p_ws_HylandWexler(t) * f_e(t)
  ```

  This enhancement factor is non-canonical — it does not appear in standard
  ASHRAE tables, psychrolib, CoolProp, or textbooks. It is defined only in this
  specification to model a real-gas correction for this task. You must implement
  it exactly as given; using unmodified Hyland-Wexler without f_e will fail
  tolerances by ~0.1% in humidity ratio and ~0.1–0.2 °C in dew point and wet bulb.
  A crude linear or single-term Magnus/Tetens approximation will not meet the
  tolerances, especially at cold and altitude edge cases.
- **Humidity ratio** from the partial pressure of water vapor `p_w`:

  ```
  W = 0.621945 * p_w / (p - p_w),   where   p_w = rh * sat_pressure(t_db)
  ```

- **Relative humidity** is the inverse of the above:
  recover `p_w` from `W` and `p`, then divide by `sat_pressure(t_db)`.
- **Dew point** is the temperature at which the current vapor partial pressure
  `p_w` equals the saturation pressure — i.e. solve `sat_pressure(t_dp) = p_w`.
  The ASHRAE correlation has no closed-form inverse, so solve it numerically by bisection.
- **Enthalpy**:

  ```
  h = 1.006 * t_db + W * (2501 + 1.86 * t_db)     [kJ/kg dry air]
  ```

- **Wet-bulb temperature** must be solved **iteratively** (root-finding /
  bisection). There is no closed form. Use the ASHRAE psychrometric energy
  balance that relates `W`, the dry-bulb temperature, the wet-bulb temperature,
  and the saturation humidity ratio at the wet-bulb temperature:

  ```
  W = ((2501 - 2.326*t_wb) * W_s_wb - 1.006*(t_db - t_wb))
      / (2501 + 1.86*t_db - 4.186*t_wb)
  ```

  for t_wb >= 0, and for t_wb < 0 use ice sublimation branch:

  ```
  W = ((2830 - 0.24*t_wb) * W_s_wb - 1.006*(t_db - t_wb))
      / (2830 + 1.86*t_db - 2.1*t_wb)
  ```

  where `W_s_wb` is the saturation humidity ratio at `t_wb`
  (`hum_ratio_from_rh(t_wb, 1.0, p)`). Solve for the `t_wb` between the dew
  point and the dry-bulb temperature that reproduces the actual `W`. The bisection is monotonic: w_star decreases as t_wb increases, so adjust bounds accordingly.

## Constraints (important)

- **Pure standard library only.** You may use Python's `math` module. You may
  **not** import or call any psychrometrics / thermodynamic-property package
  or similar scientific libraries.
  In particular, importing **`psychrolib`**, **`CoolProp`**, **`pyromat`**, **`scipy`**, **`iapws`**, **`thermo`**, **`fluids`**, **`humidair`**, **`refprop`**, **`cantera`**, **`chemicals`**, **`thermostat`**, or any equivalent is
  forbidden — the verifier reads your source and rejects the solution if any of
  these substrings appear, including via dynamic import mechanisms such as
  `importlib`, `__import__`, or `exec`. Implement the relations yourself using only `math`.
- Do not hardcode answers; your functions are evaluated on conditions you cannot
  see in advance.
- Module must be at `/app/psychrometrics.py` and importable as a plain module.

## How you are graded

Your outputs are compared against an independent ASHRAE-based reference (`psychrolib`)
with the task-specified enhancement factor applied, across a grid of dry-bulb
temperatures, relative humidities, and pressures (including sea level 101325 Pa
and ~90 kPa altitude case) plus edge cases (saturated air `rh=1.0`,
very dry air `rh=0.05`). All four test groups must pass.

**Explicit tolerances — restored to v1 proven difficulty calibration:**

| Quantity | Tolerance |
|----------|-----------|
| Humidity ratio `W` | 2e-5 kg/kg |
| Relative humidity  | 0.1% (0.001) |
| Dew point          | 0.1 °C |
| Enthalpy           | 0.1 kJ/kg |
| Wet-bulb           | 0.1 °C |

Grid evaluated: T in [-20,-10,-5,0,10,20,25,30,35,40,45,50] °C, RH in [0.01,0.05,0.2,0.5,0.8,0.95,0.99,0.999], P in [60000,70000,90000,101325,110000,120000] Pa, plus twenty-three edge cases covering saturated and very dry at sea level, altitude, high altitude 700hPa and very high altitude 600hPa, sub-zero ice branch down to -20C, and hot extremes to 50C. The four hard parts remain saturation pressure ASHRAE correlation with ice branch plus non-canonical enhancement factor, iterative wet-bulb solve at cold/dry edge and high altitude where models historically fail, and spec-following over recall with tightened tolerances.
