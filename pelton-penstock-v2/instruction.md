# Pelton Turbine Penstock Head-Loss and Governor Equilibrium Solver

## Overview
Implement Pelton turbine penstock steady-state solver with Darcy-Weisbach Colebrook-White friction iteration and droop governor equilibrium. Target file `/app/pelton_power.py` must be created with three functions described below. Tests import functions directly; no CLI, do not modify tests.

## Physical Model

Penstock circular pipe with gross head Hg, length L, diameter D, roughness epsilon. Area A = pi*D^2/4, velocity V=Q/A, Reynolds Re=V*D/nu with nu=1.004e-6.

Colebrook-White friction factor f is defined implicitly via 1/sqrt(f) = -2 log10( epsilon/(3.7 D) + 2.51/(Re sqrt(f)) ). For this task use fixed-point iteration starting from 0.02 repeating exactly 5 times, then apply laminar override f=64/Re if Re<2000. Use math.log10.

Darcy-Weisbach head loss hf = f * L/D * V^2/(2g) with g=9.81. Net head Hn = Hg - hf; raise ValueError if Hn non-positive.

Pelton jet with n_nozzle nozzles diameter d_nozzle, velocity coefficient Cv. Jet area Aj = pi d_nozzle^2/4, total Aj_tot = n_nozzle Aj. Jet velocity Vj = Cv sqrt(2 g Hn). Discharge Q = Aj_tot * Vj is implicit because hf depends on Q. Solve by outer fixed-point iteration exactly 10 times starting from Q based on gross head, each iteration recomputing velocity Reynolds friction head loss net head and updated Q, clamping Hn to at least 1e-6 to avoid sqrt domain error.

Wheel tangential speed U = pi D_wheel N /60 with N in rpm. Pelton shaft power uses Euler turbine equation pinned as P = rho Q U (Vj-U) 2 eta_b eta_m with rho=1000. Use this exact form to ensure deterministic rounding match within 2% tolerance.

Governor droop equilibrium after load step dP: compute steady speed deviation delta_N_ss = -R Nrated dP / Prated. Apply deadband db: if absolute deviation less than db set target to zero else target equals delta_N_ss. Then simulate discrete rate-limited approach with dt 1s up to 60 steps, limiting per-step change magnitude to rate_limit*dt, stopping when within 0.1 rpm of target. Clamp final speed N_eq to [0, 2 Nrated] and return delta final and iteration count.

## Functions to Implement in /app/pelton_power.py

### colebrook_f(Re: float, epsilon_D: float) -> float
Return friction factor using exactly 5 fixed-point iterations from initial 0.02 as defined by Colebrook-White relation, then laminar override if Re < 2000. epsilon_D is epsilon divided by D. Use math.log10 for base-10 logarithm.

### steady_power(Hg: float, L: float, D: float, epsilon: float, n_nozzle: int, d_nozzle: float, D_wheel: float, N_rpm: float, Cv: float, eta_b: float, eta_m: float, rho: float=1000.0, g: float=9.81) -> dict
Return dict with keys Hn, Q, P, Vj, U, f following 10-iteration outer loop for implicit Q as described. Use nu=1.004e-6. Raise ValueError if Hn <=0 at any iteration. Final f from last colebrook call.

### governor_equilibrium(Nrated: float, Prated: float, R: float, deadband: float, rate_limit: float, load_step: float, dt: float=1.0, max_iter: int=60) -> dict
Return dict with keys N_eq float, iterations int, delta float following discrete rate-limit simulation with deadband and clamp as described.

## Deliverable
Only `/app/pelton_power.py` is graded. Functions must match names and signatures exactly.

Allowed libraries: python standard library math, numpy optional. No external CFD libraries.

## Test Constraints
* Hg 100-800 m, L 200-2000 m, D 0.8-2.5 m, epsilon 0.000045-0.0003 m
* n_nozzle 1-6, d_nozzle 0.05-0.25 m, D_wheel 1.0-3.5 m, N 300-900 rpm
* Cv 0.97-0.99, eta_b 0.85-0.92, eta_m 0.94-0.98
* R 0.04-0.06, deadband 2-10 rpm, rate_limit 5-20 rpm/s, load_step +-30% Prated
* Randomized geometries per seed prevent hardcode.
* Tolerances: Hn 1% relative, Q 1.5%, P 2%, N_eq 0.5 rpm absolute, iterations exact.

## Naive Failure Modes Tests Catch
* Constant f=0.02 instead of Colebrook 5-iteration -> hf error >5%
* Wrong Pelton power missing factor 2 or U term -> P error >10%
* Ignoring deadband -> N_eq off by db
* Ignoring rate limit -> iterations always 1
* Using Haaland approximation instead of pinned 5-iteration Colebrook -> deviation beyond tolerance
* Q implicit loop not iterated -> large Q error
* Not clamping Hn or N_eq -> ValueError mismatch

## Example Usage
```python
from pelton_power import colebrook_f, steady_power, governor_equilibrium
f = colebrook_f(1e6, 0.0001)
out = steady_power(Hg=450, L=800, D=1.4, epsilon=0.0001, n_nozzle=2, d_nozzle=0.12, D_wheel=2.1, N_rpm=600, Cv=0.98, eta_b=0.89, eta_m=0.96)
gov = governor_equilibrium(Nrated=600, Prated=out["P"], R=0.05, deadband=5, rate_limit=10, load_step=-0.2*out["P"])
```

## Anti-Cheating Notes
* Geometries randomized per seed; hard-coded outputs fail.
* Colebrook pinned to exactly 5 fixed-point iterations; Haaland approximations deviate beyond tolerance.
* Pelton power formula pinned; factor errors caught by 2% P tolerance.
* Governor rate-limit simulation pinned to discrete steps; analytic bypass fails iteration count.
