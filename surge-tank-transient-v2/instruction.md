# Surge Tank Mass Oscillation Transient Simulator

## Overview
Implement rigid water-column ODE simulation of surge tank mass oscillation after turbine load rejection. Target file `/app/surge_transient.py` must be created with function `simulate`. Tests import directly; do not modify tests.

## Physical Model

Surge tank connected to reservoir via tunnel length L, diameter D, area A_tunnel = pi * D**2 / 4. Surge tank cross-section area A_surge.

Variables:
* Z(t) surge tank water level relative to reservoir static level [m], positive upward.
* V(t) tunnel velocity positive toward surge tank and turbine [m/s].
* Qt(t) turbine discharge [m3/s].

Continuity at surge junction:
```
A_surge * dZ/dt = A_tunnel * V - Qt
```

Momentum rigid water column pinned:
```
L/g * dV/dt + Z + hf + hm = 0
```
with hm = 0 pinned for this task (minor losses neglected, Ke = 0). Do not add entrance loss unless Ke parameter passed non-zero but default tests use Ke=0.

Darcy-Weisbach friction hf:
```
hf = f * L/D * V * abs(V) / (2*g)
```
f from Swamee-Jain explicit formula pinned:
```
Re = abs(V) * D / nu ; nu = 1e-6
if Re < 2000: f = 64 / max(Re, 1.0)
else: f = 0.25 / ( log10( epsilon/(3.7*D) + 5.74 / Re**0.9 ) )**2
```
epsilon = roughness [m] input parameter. Use math.log10.

Turbine closure ramp pinned:
* Initial steady discharge Q0 at t=0.
* Trip time t_trip [s] when closure starts.
* Closure time constant tau_close [s] linear ramp to zero.
```
Qt(t) = Q0                              for t < t_trip
Qt(t) = Q0 * max(0.0, 1 - (t - t_trip)/tau_close)   for t >= t_trip
```

Initial condition steady state before trip pinned:
* V0 = Q0 / A_tunnel
* Compute f0 via Swamee-Jain using V0, then hf0 = f0 * L/D * V0*abs(V0)/(2*g)
* Z0 = - hf0   (reservoir to surge drop negative)
* Initial Z list starts at Z0, V list starts at V0 at t=0.

## Numerical Scheme Pinned

Explicit Euler with fixed dt, exactly this order each step, no predictor-corrector, no scipy integrators:

```
V_{n+1} = V_n + dt * g / L * ( - Z_n - hf_n - hm_n )
Z_{n+1} = Z_n + dt * ( A_tunnel * V_n - Qt_n ) / A_surge
```

where hf_n computed from V_n using Swamee-Jain above, hm_n = Ke * V_n*abs(V_n)/(2*g) with Ke default 0, Qt_n evaluated at time t_n = n*dt using closure ramp formula.

Compute exactly in this order each step to ensure deterministic rounding match with reference.

## Function to Implement

Create `/app/surge_transient.py` with:

```python
def simulate(dt: float, n_steps: int, L: float, D: float, A_surge: float, A_tunnel: float, H_res: float, Q0: float, t_trip: float, tau_close: float, roughness: float, g: float=9.81, nu: float=1e-6, Ke: float=0.0) -> dict:
```

Parameters: H_res is reservoir head absolute for signature compatibility only and is ignored in calculation of Z relative to reservoir; keep in signature but do not use except perhaps for documentation. Tests will pass value but expect it ignored.

Return dict with exact keys:
```
{
  "Z": list[float],        # length n_steps+1, Z[0]=Z0
  "V": list[float],        # length n_steps+1, V[0]=V0
  "peak_Z": float,         # max Z over all steps including initial
  "min_Z": float,          # min Z over all steps
  "steady_Z": float,       # Z at final step n_steps
  "damping_time": float    # first time t = i*dt where for all j>=i, abs(Z[j]-steady_Z) < 0.01 ; if never satisfied return n_steps*dt
}
```

Compute damping_time by scanning forward: find smallest i such that max_{j=i..n_steps} abs(Z[j]-steady_Z) < 0.01 ; return i*dt ; else n_steps*dt.

## Deliverable
Only `/app/surge_transient.py` is graded. Function must match name and signature exactly.

Allowed libraries: python standard library math, numpy optional. Do not use scipy.integrate or ODE solvers. Pure standard-library Python only per spec; no file IO via open(), no eval(), no exec() per pure deterministic no file access requirement and C18 mitigation. Allowed imports are math, sys, os, json, typing, collections, itertools, functools, heapq, bisect, random, statistics, decimal, fractions, datetime.

## Test Constraints
* dt 0.1 to 0.5 s pinned per test case
* n_steps 600 to 2400 => total 60 to 600 s simulation
* L 200-1200 m, D 2-6 m, A_surge 20-200 m2, A_tunnel either given or computed as pi*D**2/4 consistent per case
* Q0 10-150 m3/s  # expanded range to cover edge-case test scenarios including 120 and 150 m3/s for high-flow regime testing per v0.21 hardening
* t_trip 5-20 s, tau_close 3-15 s
* roughness 0.0001 to 0.001 m
* Randomized per seed.
* Tolerances: peak_Z within 0.05 m absolute or 0.2% relative whichever larger, min_Z within 0.05 m absolute, steady_Z within 0.005 m absolute, damping_time within 0.5*dt. These tightened tolerances increase sensitivity to numerical order errors and friction mis-modeling compared to earlier looser specification, aligning spec text with actual test enforcement to resolve spec-test contradiction per AI feedback and target 2-3/5 difficulty band. Test suite expanded to 9 cases including high-friction low-surge-area edge, long-tunnel slow-closure, high-flow 120-150 m3/s regimes, plus explicit naive failure traps for frictionless, wrong sign, RK4, wrong Z0, wrong update order.

## Naive Failure Modes Tests Catch
* Ignoring friction setting f=0 -> over-predicts amplitude >30%
* Using Hagen-Poiseuille laminar only f=64/Re -> wrong f in turbulent regime
* Using scipy solve_ivp or RK4 instead of explicit Euler -> phase deviation beyond tolerance by design
* Wrong sign in momentum equation -> divergent or inverted oscillation
* Qt not ramped staying at Q0 -> no transient
* Swamee-Jain missing abs(V) -> asymmetric friction
* Steady state initialization wrong Z0=0 instead of -hf0 -> offset bias >0.5 m
* Wrong order of Euler update using V_{n+1} in Z update -> phase shift beyond tolerance

## Example Usage
```python
from surge_transient import simulate
out = simulate(dt=0.2, n_steps=1500, L=600, D=4.0, A_surge=78.5, A_tunnel=12.57,
               H_res=100, Q0=40, t_trip=10, tau_close=8, roughness=0.0003)
print(out["peak_Z"], out["min_Z"], out["damping_time"])
```

## Anti-Cheating Notes
* Geometries randomized per seed; hard-coded outputs fail.
* Explicit Euler pinned order prevents bypass via higher-order integrators; those deviate beyond tolerance by design.
* Swamee-Jain formula pinned with exact parentheses; Haaland or Colebrook iterative approximations deviate.
* Damping time definition pinned to 0.01 m threshold scanning forward ensures deterministic grading.
