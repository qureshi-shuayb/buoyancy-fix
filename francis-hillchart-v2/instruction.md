# Francis Turbine Hill-Chart Operating Point Solver

## Overview
Implement a Francis turbine operating-point solver that uses hill-chart interpolation to find discharge, rotational speed, and efficiency meeting a power target under cavitation constraints. Target file `/app/francis_hill.py` must be created with three functions described below. Tests import functions directly; do not modify tests or create CLI.

## Physical Model

Francis turbine hill chart gives efficiency eta as function of unit discharge Q11 and unit speed n11:

```
Q11 = Q / ( D**2 * sqrt(H) )
n11 = n * D / sqrt(H)
```

where Q discharge [m3/s], n rotational speed [rpm] used directly in rpm throughout this task without conversion to rps for consistency with hill data, H net head [m], D runner diameter [m], rho=1000 kg/m3, g=9.81 m/s2.

Power:
```
P = rho * g * H * Q * eta   [W]
```

Cavitation Thoma coefficient simplified pinned model:
```
Hb = 10.33   # barometric head sea level [m]
Hv = 0.24    # vapor pressure head 20C [m]
sigma = (Hb - Hv + Hs) / H
margin = sigma - sigma_crit
```
Hs suction head [m] negative below tailwater from limits. Safe if margin >=0. This simplified model is intentionally pinned independent of Q and n to allow deterministic grading; do not use more complex NPSH formulas.

## Functions to Implement

Create `/app/francis_hill.py` with exactly these signatures.

### interp_hill(q11: float, n11: float, hill: list) -> float

Barycentric interpolation on Delaunay triangulation.

* `hill` : list of tuples `(q11_i, n11_i, eta_i)` length 30 to 80 deterministic per test seed.
* Must use `scipy.spatial.Delaunay` only. Do not use `LinearNDInterpolator`, `griddata`, `CloughTocher`, or other interpolators.
* Pinned algorithm:
  1. `import numpy as np; from scipy.spatial import Delaunay`
  2. `pts = np.array([[q,n] for q,n,e in hill]); vals=np.array([e for q,n,e in hill])`
  3. `tri = Delaunay(pts)`
  4. `simplex = tri.find_simplex(np.array([[q11,n11]]))[0]`
  5. If simplex == -1: return 0.0
  6. `vertices = tri.simplices[simplex]; T = tri.transform[simplex]; p = np.array([q11,n11])`
  7. `b = T[:2].dot(p - T[2]); w = np.array([b[0], b[1], 1-b.sum()])`
  8. `eta = float( w[0]*vals[vertices[0]] + w[1]*vals[vertices[1]] + w[2]*vals[vertices[2]] )`
  9. Clamp eta to [0.0,1.0] and return.
* Return 0.0 if outside convex hull. Do not extrapolate.

### find_bep(H: float, P_req: float, hill: list, limits: dict) -> dict

Find operating point meeting power request at maximum efficiency using nested golden-section search pinned to exactly 40 iterations per level.

`limits` dict keys: `D`, `Qmin`, `Qmax`, `nmin`, `nmax`, `rho` default 1000, `g` default 9.81, `sigma_crit`, `Hs`.

Pinned golden-section:
* phi = (1 + 5**0.5)/2 ; resphi = 2 - phi
* For interval [a,b] 40 iterations: c = a + resphi*(b-a); d = b - resphi*(b-a); evaluate f(c), f(d); shrink interval keeping better point; repeat.

Algorithm:
1. Define inner(n_trial, Q_fixed): compute Q11 = Q_fixed / (D**2 * H**0.5); n11 = n_trial*D / H**0.5; eta = interp_hill(Q11,n11); return eta.
2. For given Q, run inner golden-section over n in [nmin,nmax] maximizing eta using 40 iterations. Return best n_star and eta_star.
3. Compute P(Q)= rho*g*H*Q*eta_star.
4. Outer golden-section over Q in [Qmin,Qmax] minimizing abs(P(Q)-P_req) using 40 iterations.
5. After convergence obtain Q_opt, n_opt, eta_opt, P_opt.
6. Compute Q11_opt, n11_opt using formulas above.
7. Compute margin via cavitation_margin. If margin < 0: set eta_opt = 0.0 and P_opt = rho*g*H*Q_opt*0 to signal unsafe, but still return dict structure; do not raise exception.
8. Return dict `{"Q": float(Q_opt), "n": float(n_opt), "eta": float(eta_opt), "P": float(P_opt), "Q11": float(Q11_opt), "n11": float(n11_opt)}`

Tolerances for grading: Q within 1% relative, n within 1% relative, eta within 0.005 absolute, P within 2% relative of P_req or of reference P_opt.

### cavitation_margin(H: float, Q: float, n: float, sigma_crit: float, Hs: float, D: float, **kwargs) -> float

Return margin = (10.33 - 0.24 + Hs)/H - sigma_crit as float. Q, n, D arguments are present for signature compatibility and ignored in this simplified pinned model.

## Deliverable

Only `/app/francis_hill.py` is graded. Do not create other files. Functions must match names and signatures exactly.

Allowed libraries: python standard library, numpy, scipy.spatial. Do not use sklearn, griddata, or other interpolators.

## Test Constraints

* H in [30,200] m
* P_req in [5e6, 80e6] W
* D in [1.5,5.0] m
* Qmin 10 Qmax 200 scaled per case, nmin 100 nmax 600 rpm
* hill points 30-80 per case generated deterministically per seed with eta in 0.7-0.94 and single smooth peak near Q11~0.6 n11~70
* Randomized seeds prevent hardcoding.

## Naive Failure Modes Tests Catch

* Nearest-neighbor instead of barycentric -> eta error >0.01 off grid
* Using scipy griddata or LinearNDInterpolator -> weight difference beyond tolerance
* Constant eta assumption -> power error >10%
* Ignoring cavitation margin check -> unsafe point not flagged in separate test
* Wrong Q11 or n11 formula missing D or sqrt(H) -> systematic bias >5%
* Golden-section fewer than 40 iterations -> insufficient 1% precision
* Extrapolating outside hull instead of returning 0 -> false efficiency

## Example Usage

```python
from francis_hill import interp_hill, find_bep, cavitation_margin
hill = [(0.4,60,0.82),(0.5,65,0.88),(0.6,70,0.92),(0.7,75,0.89)]
limits = {"D":3.2,"Qmin":20,"Qmax":120,"nmin":150,"nmax":400,"rho":1000,"g":9.81,"sigma_crit":0.08,"Hs":-2.5}
out = find_bep(H=95.0, P_req=45e6, hill=hill, limits=limits)
margin = cavitation_margin(95.0, out["Q"], out["n"], 0.08, -2.5, 3.2)
```

## Anti-Cheating Notes

* Hill chart randomized per test seed; hard-coded outputs fail.
* Barycentric weights pinned via Delaunay transform; alternative interpolators deviate beyond tolerance.
* Golden-section 40 iterations pinned; coarse search fails tolerance.
* Cavitation check enforced in separate test with varied Hs and sigma_crit.
