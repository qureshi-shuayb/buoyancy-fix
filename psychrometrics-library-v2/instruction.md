# Psychrometrics Library

Implement a psychrometrics library for moist air in SI units.

## Output location

Create exactly `/app/psychrometrics.py` exposing six module-level functions with exactly these signatures:

```python
def sat_pressure(t_db): ...
def hum_ratio_from_rh(t_db, rh, p=101325): ...
def rh_from_hum_ratio(t_db, w, p=101325): ...
def dew_point(t_db, rh, p=101325): ...
def enthalpy(t_db, w): ...
def wet_bulb(t_db, rh, p=101325): ...
```

## Units

- Temperatures in degrees Celsius.
- Pressures in pascals. Default p 101325 Pa sea level.
- Humidity ratio W in kg water vapor per kg dry air.
- Relative humidity rh fraction 0 to 1.
- Enthalpy in kJ per kg dry air.

## Task

Your functions will be evaluated against an independent reference implementation across a range of conditions including temperatures from -10 to 45 C, relative humidities from very dry to saturated, and pressures from sea level down to high altitude. Return accurate values within tight tolerances. No third-party psychrometrics libraries allowed; implement the physical relations yourself using Python standard library only.

## Constraints

- Pure standard library only, math allowed. Do not import psychrolib, CoolProp, pyromat or similar — verifier scans source and rejects.
- Do not hardcode outputs; functions evaluated on unseen conditions.
- Module must be at /app/psychrometrics.py importable.

## Grading

Outputs compared against reference across grid of dry-bulb temperatures, relative humidities, pressures including sea level and altitude cases plus edge cases saturated and very dry. All test groups must pass.
