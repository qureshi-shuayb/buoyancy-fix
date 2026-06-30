# Pelton Turbine Penstock and Governor Solver

## Overview
Implement a steady-state Pelton turbine penstock solver in Python at `/app/pelton_power.py`. The module must expose three functions with exact signatures described below. Tests import the module directly; do not modify tests or add CLI.

This is a mechanical engineering simulation task combining fluid mechanics (Darcy-Weisbach head loss with Colebrook-White friction), Pelton turbine Euler power, and discrete droop governor dynamics.

## Physical Background

A Pelton impulse turbine is fed by a circular penstock of length L, diameter D, roughness epsilon, carrying gross head Hg. Kinematic viscosity nu = 1.004e-6 m2/s, gravity g=9.81 m/s2, water density rho defaults to 1000 kg/m3.

Penstock area A = pi D^2 /4. Mean velocity V = Q / A. Reynolds number Re = V D / nu.

Friction factor f follows Colebrook-White implicit relation:
  1/sqrt(f) = -2 log10( epsilon/(3.7 D) + 2.51/(Re sqrt(f)) )
Solve by fixed-point iteration from initial guess 0.02 for exactly 5 iterations using math.log10. Apply laminar override f = 64 / Re when Re < 2000.

Darcy-Weisbach head loss hf = f L/D V^2 / (2g). Net head Hn = Hg - hf. Raise ValueError if Hn is not positive.

Pelton nozzle assembly: n_nozzle nozzles of diameter d_nozzle, velocity coefficient Cv. Jet area per nozzle Aj = pi d_nozzle^2 /4, total Aj_tot = n_nozzle * Aj. Jet velocity Vj = Cv sqrt(2 g Hn). Discharge Q = Aj_tot * Vj.

Because hf depends on Q, Q is implicit. Solve with outer fixed-point loop of exactly 10 iterations: initialize Q from gross head, then each iteration recompute V, Re, f, hf, Hn, and update Q. Clamp Hn to at least 1e-6 during iteration to avoid sqrt domain error; final Hn must still be checked for positivity.

Wheel tangential speed U = pi D_wheel N / 60 where N is rpm.

Pelton shaft power from Euler turbine equation: P = rho * Q * U * (Vj - U) * 2 * eta_b * eta_m. Use this exact form.

## Governor Model

Droop governor with permanent droop R, rated speed Nrated rpm, rated power Prated W, deadband db rpm, rate limit rpm/s.

For a load step dP (positive = load increase, negative = load decrease):
 steady speed deviation delta_N_ss = - R * Nrated * dP / Prated
 deadband logic: if |delta_N_ss| < db then target delta = 0 else target = delta_N_ss

Simulate discrete approach with timestep dt=1.0 s up to max_iter=60 steps. Each step change is limited in magnitude to rate_limit*dt toward target. Stop early when within 0.1 rpm of target. Return final equilibrium speed N_eq = Nrated + delta, clamped to [0, 2*Nrated], along with iteration count and final delta.

## Required API in /app/pelton_power.py

```python
def colebrook_f(Re: float, epsilon_D: float) -> float
```
epsilon_D is epsilon/D. Return friction factor after 5 fixed-point iterations then laminar check.

```python
def steady_power(Hg: float, L: float, D: float, epsilon: float, n_nozzle: int, d_nozzle: float, D_wheel: float, N_rpm: float, Cv: float, eta_b: float, eta_m: float, rho: float=1000.0, g: float=9.81) -> dict
```
Return dict with keys Hn, Q, P, Vj, U, f computed via 10-iteration outer loop. Raise ValueError on non-positive Hn.

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

Tolerances for grading: Hn 1% relative, Q 1.5%, P 2%, Vj 1%, U 1%, f 2%, N_eq 0.5 rpm absolute, iterations exact match.

Geometries are randomized per test seed to prevent hard-coding. Implement general physics, not case-specific constants.
