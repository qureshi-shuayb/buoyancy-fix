# Pelton Turbine Penstock and Governor Solver

## Overview
Implement a steady-state Pelton turbine penstock solver in Python at `/app/pelton_power.py`. The module must expose three functions with exact signatures described below. Tests import the module directly; do not modify tests or add CLI.

This is a mechanical engineering simulation task combining fluid mechanics (Darcy-Weisbach head loss with Colebrook-White friction), Pelton turbine Euler power, and discrete droop governor dynamics.

## Physical Background

A Pelton impulse turbine is fed by a circular penstock carrying gross head Hg. Water properties use standard kinematic viscosity and gravity, density defaults to 1000 kg/m3. The penstock geometry is defined by length, diameter and absolute roughness.

Flow in the penstock is characterized by cross-sectional area, mean velocity derived from discharge, and Reynolds number based on diameter and viscosity. Friction factor follows the Colebrook-White implicit relationship between relative roughness and Reynolds number, solved iteratively via fixed-point using base-10 logarithm. For laminar regime apply the classical inverse Reynolds scaling.

Head loss along the penstock follows Darcy-Weisbach proportional to friction factor, length-to-diameter ratio and velocity head. Net head available at the nozzle is gross head minus friction loss. The implementation must raise ValueError when net head is non-positive after convergence.

The Pelton nozzle assembly converts net head to jet kinetic energy via a velocity coefficient accounting for nozzle losses. Total jet area aggregates multiple identical nozzles. Jet velocity derives from Torricelli-type square root relationship with net head. Discharge is jet area times jet velocity.

Because head loss depends on discharge which itself depends on net head, the system is implicit. Solve by outer fixed-point iteration starting from gross-head estimate, then repeatedly update velocity, Reynolds number, friction factor, head loss, net head and discharge until stable. Guard against non-physical intermediate net head during iteration but enforce positivity check at the end.

Wheel tangential speed converts rotational speed in rpm to linear rim speed using wheel diameter. Pelton shaft power follows Euler turbine equation for impulse machines, incorporating mass flow rate, change in tangential momentum between jet and bucket speed, bucket efficiency and mechanical efficiency. The factor accounting for jet turning angle near 180 degrees must be included.

## Governor Model

Droop governor with permanent droop coefficient, rated speed, rated power, speed deadband and slew rate limit.

For a load step, compute steady-state speed deviation proportional to droop, rated speed and per-unit load change, with sign convention such that load increase reduces speed. Apply deadband: small deviations within band produce zero target change, otherwise target equals steady deviation.

Simulate discrete-time approach to target with fixed timestep defaulting to one second and configurable maximum steps. At each step the speed change is limited in magnitude by rate limit times timestep, moving toward target without overshoot. Terminate early when sufficiently close to target. Return equilibrium speed as rated plus accumulated delta, clamped to physical bounds between zero and twice rated, along with iteration count used and final delta achieved.

## Required API in /app/pelton_power.py

```python
def colebrook_f(Re: float, epsilon_D: float) -> float
```
epsilon_D is epsilon/D. Return friction factor using Colebrook fixed-point then laminar check.

```python
def steady_power(Hg: float, L: float, D: float, epsilon: float, n_nozzle: int, d_nozzle: float, D_wheel: float, N_rpm: float, Cv: float, eta_b: float, eta_m: float, rho: float=1000.0, g: float=9.81) -> dict
```
Return dict with keys Hn, Q, P, Vj, U, f computed via outer fixed-point loop. Raise ValueError on non-positive Hn.

```python
def governor_equilibrium(Nrated: float, Prated: float, R: float, deadband: float, rate_limit: float, load_step: float, dt: float=1.0, max_iter: int=60) -> dict
```
Return dict with keys N_eq, iterations, delta following droop deadband rate-limit logic.

## Constraints

Input ranges typical for high-head Pelton plants:
 Hg 100-800 m, L 200-2000 m, D 0.8-2.5 m, epsilon 45e-6 to 300e-6 m
 n_nozzle 1-6, d_nozzle 0.05-0.25 m, D_wheel 1.0-3.5 m, N 300-900 rpm
 Cv 0.97-0.99, eta_b 0.85-0.92, eta_m 0.94-0.98
 R 0.04-0.06, deadband 2-10 rpm, rate_limit 5-20 rpm/s, load_step within +-30% Prated

Tolerances for grading: Hn 0.3% relative, Q 0.5%, P 0.7%, Vj 0.3%, U 0.3%, f 0.5%, N_eq 0.1 rpm absolute, iterations exact match.

Geometries are randomized per test seed to prevent hard-coding. Implement general physics, not case-specific constants.
