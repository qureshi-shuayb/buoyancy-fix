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
* Must use `scipy.spatial.Delaunay` for triangulation. Do not use `LinearNDInterpolator`, `griddata`, `CloughTocher`, `NearestNDInterpolator`, `RBFInterpolator`, `interp2d`, `RegularGridInterpolator`, sklearn, or other interpolators. Only Delaunay-based barycentric weights are accepted within 1e-6 tolerance.
* Algorithm requirements:
  - Construct Delaunay triangulation from hill points interpreted as 2D coordinates (q11, n11) with associated eta values.
  - Locate the simplex containing query point (q11, n11) using the triangulation's point-location method. If outside convex hull, return 0.0 without extrapolation.
  - Compute barycentric weights for the three vertices of containing triangle using the triangulation's affine transform. Interpolate eta as weighted sum of vertex eta values.
  - Clamp result to [0.0, 1.0] range.
* Return 0.0 if outside convex hull. Do not extrapolate.
* Tests enforce 1e-6 absolute accuracy against independent reference using same Delaunay barycentric method, so alternative interpolators will deviate beyond tolerance.

### find_bep(H: float, P_req: float, hill: list, limits: dict) -> dict

Find operating point meeting power request at maximum efficiency using nested golden-section search.

`limits` dict keys: `D`, `Qmin`, `Qmax`, `nmin`, `nmax`, `rho` default 1000, `g` default 9.81, `sigma_crit`, `Hs`.

Golden-section requirements:
* Use golden ratio phi = (1+sqrt(5))/2 and resphi = 2-phi for interval shrinkage.
* Perform exactly 40 iterations per search level to achieve required 1% precision on Q and n.
* Inner level maximizes eta over n for fixed Q. Outer level minimizes absolute power error |P(Q)-P_req| over Q.

Algorithm outline:
1. For a given discharge Q, compute unit discharge Q11. Define inner objective over speed n that computes unit speed n11, calls interp_hill to get eta, and returns eta for maximization.
2. Run golden-section search over n in [nmin, nmax] for 40 iterations to find n maximizing eta. Return best n and corresponding eta.
3. Compute power P = rho * g * H * Q * eta for that Q.
4. Define outer objective as absolute difference between P(Q) and P_req. Run golden-section search over Q in [Qmin, Qmax] for 40 iterations minimizing this error.
5. After convergence obtain Q_opt, then recompute n_opt and eta_opt via inner search, compute P_opt.
6. Compute Q11_opt and n11_opt using unit formulas.
7. Compute cavitation margin via cavitation_margin function. If margin < 0, set eta_opt to 0.0 and recompute P_opt as zero to signal unsafe condition, but still return full dict structure without raising exception.
8. Return dict with float values for keys Q, n, eta, P, Q11, n11 in that exact set.

Tolerances for grading: Q within 1% relative, n within 1% relative, eta within 0.005 absolute, P within 2% relative.

### cavitation_margin(H: float, Q: float, n: float, sigma_crit: float, Hs: float, D: float, **kwargs) -> float

Return margin = (10.33 - 0.24 + Hs)/H - sigma_crit as float. Q, n, D arguments are present for signature compatibility and ignored in this simplified pinned model.

## Deliverable

Only `/app/francis_hill.py` is graded. Do not create other files. Functions must match names and signatures exactly.

Allowed libraries: python standard library, numpy, scipy.spatial only. Do not import scipy.interpolate, sklearn, or other interpolation modules.

## Test Constraints

* H in [30,200] m
* P_req in [5e6, 80e6] W
* D in [1.5,5.0] m
* Qmin 10 Qmax 200 scaled per case, nmin 100 nmax 600 rpm
* hill points 30-80 per case generated deterministically per seed with eta in 0.7-0.94 and single smooth peak near Q11~0.6 n11~70
* Randomized seeds prevent hardcoding.

## Naive Failure Modes Tests Catch

* Nearest-neighbor instead of barycentric -> eta error >0.01 off grid
* Using scipy griddata or LinearNDInterpolator -> weight difference beyond tolerance and banned import check fails
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
* Barycentric weights via Delaunay transform required for 1e-6 accuracy; alternative interpolators deviate beyond tolerance and are banned via import check.
* Golden-section 40 iterations required for 1% precision; coarse search fails tolerance.
* Cavitation check enforced in separate test with varied Hs and sigma_crit including unsafe margin case.
