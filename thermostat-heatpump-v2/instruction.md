# Thermostat Heat Pump Simulation

Implement Python simulation of one day single-zone building heated by thermostat controlling heat pump with anti-short-cycle, defrost, part-load degradation, backup heat.

## Deliverable
Create `/app/hvac_sim.py` defining exactly:

```python
def simulate(t_out, dt, n_steps, setpoint, deadband, R, C, t_initial, cop_curve, hp_capacity, backup_capacity, internal_gain, defrost_band, defrost_interval, defrost_duration, defrost_cop_factor, Cd, min_runtime, min_offtime) -> dict: ...
```

Return dict with energy_kwh float, comfort_degree_hours float, indoor_temp list length n_steps+1.

t_out and internal_gain may be scalar or list length n_steps. dt min_runtime min_offtime seconds; defrost_interval defrost_duration minutes.

Implement 1R1C zone thermal model with exact analytic integration, deadband hysteresis control with anti-short-cycle override, defrost scheduling, COP interpolation, part-load factor, capacity limit backup, energy and comfort accounting. Pure standard library only.

Outputs compared against independent reference across multiple scenarios with tight tolerances. All test groups must pass.
