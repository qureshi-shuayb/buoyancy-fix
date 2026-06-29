# Pelton Turbine Penstock Head-Loss and Governor Equilibrium Solver

## Overview
Implement Pelton turbine penstock steady-state solver with Darcy-Weisbach Colebrook-White friction iteration and droop governor equilibrium. Target file `/app/pelton_power.py` must be created with three functions described below. Tests import functions directly; no CLI, do not modify tests.

## Physical Model

Penstock circular pipe:
* Gross head Hg [m]
* Length L [m], diameter D [m], roughness epsilon [m]
* Area A = pi * D**2 / 4
* Velocity V = Q / A
* Reynolds Re = V * D / nu ; nu = 1.004e-6 m2/s water at 20C
* Colebrook-White implicit: 1/sqrt(f) = -2 * log10( epsilon/(3.7*D) + 2.51/(Re*sqrt(f)) )
  Pinned solver: fixed-point iteration starting f0 = 0.02, repeat exactly 5 times:
  f_{k+1} = ( -2 * log10( epsilon/(3.7*D) + 2.51/(Re * sqrt(f_k)) ) ) ** -2
  If Re < 2000 use laminar f = 64 / Re override after iterations.

* Darcy-Weisbach head loss: hf = f * L/D * V**2 / (2*g) ; g = 9.81
* Net head: Hn = Hg - hf ; if Hn <= 0 raise ValueError("Net head non-positive").

Pelton jet:
* n_nozzle nozzles, each diameter d_nozzle [m], velocity coefficient Cv in [0.97,0.99]
* Jet area Aj = pi * d_nozzle**2 / 4 ; total Aj_tot = n_nozzle * Aj
* Jet velocity Vj = Cv * sqrt(2 * g * Hn)
* Discharge Q = Aj_tot * Vj  — Q is implicit because hf depends on Q. Solve by fixed-point outer iteration pinned to exactly 10 iterations: start Q0 = Aj_tot * Cv * sqrt(2*g*Hg); for i in 0..9 compute V=Q/A, Re, f via colebrook_f, hf, Hn = Hg - hf, Q_new = Aj_tot * Cv * sqrt(2*g*max(Hn,1e-6)); set Q=Q_new continue.

* Wheel diameter D_wheel [m], speed N [rpm] -> U = pi * D_wheel * N / 60  [m/s]
* Bucket efficiency eta_b, mechanical eta_m.
* Pelton Euler shaft power pinned formula exactly:
  P_shaft = rho * Q * U * (Vj - U) * 2.0 * eta_b * eta_m
  where rho = 1000 kg/m3. Use this formula verbatim for pinning; do not substitute alternative equivalent forms that introduce rounding differences beyond tolerance. Maximum theoretical at U/Vj = 0.5.

Governor droop equilibrium after load step:
* Rated power Prated [W], rated speed Nrated [rpm] from steady operating point.
* Droop R per unit e.g. 0.05 for 5%
* Deadband db [rpm], rate limit rl [rpm/s], load step dP [W] positive = load increase, negative = load rejection.
* Clamp effective power to avoid negative: Pr_eff = max(Prated + dP, 1.0)
* Speed deviation steady-state without limits: delta_N_ss = - R * Nrated * dP / Prated
* Apply deadband: if abs(delta_N_ss) < db then delta_target = 0 else delta_target = delta_N_ss
* Apply rate limit via discrete simulation pinned: dt=1.0 s, max_iter=60, start delta=0. For step in 1..max_iter: step_change = max(-rl*dt, min(rl*dt, delta_target - delta)); delta += step_change; if abs(delta - delta_target) < 0.1 break. Return iterations = step count.
* N_eq = Nrated + delta ; clamp N_eq to [0.0, 2.0 * Nrated]
* Return delta = delta_final.

## Functions to Implement in /app/pelton_power.py

### colebrook_f(Re: float, epsilon_D: float) -> float
Return friction factor using exactly 5 fixed-point iterations from f0=0.02 as defined above, then laminar override if Re < 2000 return 64 / max(Re,1). epsilon_D = epsilon / D dimensionless. Use math.log10.

### steady_power(Hg: float, L: float, D: float, epsilon: float, n_nozzle: int, d_nozzle: float, D_wheel: float, N_rpm: float, Cv: float, eta_b: float, eta_m: float, rho: float=1000.0, g: float=9.81) -> dict
Return dict `{"Hn": float, "Q": float, "P": float, "Vj": float, "U": float, "f": float}` following pinned 10-iteration outer loop described above. Use nu=1.004e-6. Final f is from last iteration colebrook_f call. Raise ValueError if Hn <=0 at any iteration.

### governor_equilibrium(Nrated: float, Prated: float, R: float, deadband: float, rate_limit: float, load_step: float, dt: float=1.0, max_iter: int=60) -> dict
Return `{"N_eq": float, "iterations": int, "delta": float}` following pinned discrete rate-limit simulation described above with deadband and clamp to [0, 2*Nrated].

## Deliverable
Only `/app/pelton_power.py` is graded. Functions must match names and signatures exactly. Do not create other files.

Allowed libraries: python standard library math, numpy optional. No external CFD or fluids libraries.

## Test Constraints
* Hg 100-800 m
* L 200-2000 m, D 0.8-2.5 m, epsilon 0.000045-0.0003 m
* n_nozzle 1-6, d_nozzle 0.05-0.25 m
* D_wheel 1.0-3.5 m, N 300-900 rpm
* Cv 0.97-0.99, eta_b 0.85-0.92, eta_m 0.94-0.98
* R 0.04-0.06, deadband 2-10 rpm, rate_limit 5-20 rpm/s, load_step +-30% Prated
* Randomized geometries per seed prevent hardcode.
* Tolerances: Hn within 1% relative, Q within 1.5%, P within 2%, N_eq within 0.5 rpm absolute, iterations exact match reference.

## Naive Failure Modes Tests Catch
* Constant f=0.02 instead of Colebrook 5-iteration -> hf error >5%
* Wrong Pelton power missing factor 2 or U term -> P error >10%
* Ignoring deadband -> N_eq off by db
* Ignoring rate limit -> iterations always 1
* Using Haaland approximation instead of pinned 5-iteration Colebrook -> deviation beyond tolerance
* Q implicit loop not iterated or single iteration -> large Q error
* Not clamping Hn or N_eq -> ValueError mismatch or out of bounds

## Example Usage
```python
from pelton_power import colebrook_f, steady_power, governor_equilibrium
f = colebrook_f(1e6, 0.0001)
out = steady_power(Hg=450, L=800, D=1.4, epsilon=0.0001, n_nozzle=2, d_nozzle=0.12, D_wheel=2.1, N_rpm=600, Cv=0.98, eta_b=0.89, eta_m=0.96)
gov = governor_equilibrium(Nrated=600, Prated=out["P"], R=0.05, deadband=5, rate_limit=10, load_step=-0.2*out["P"])
```

## Anti-Cheating Notes
* Geometries randomized per seed; hard-coded outputs fail.
* Colebrook pinned to exactly 5 fixed-point iterations; Haaland or Swamee-Jain approximations deviate beyond tolerance by design.
* Pelton power formula pinned verbatim; alternative equivalent forms must match within tolerance but factor errors caught.
* Governor rate-limit simulation pinned to discrete 1s steps; analytic solution without rate limit fails iteration count test.
