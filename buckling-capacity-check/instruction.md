# Buckling Capacity Check

Implement pure-R Euler buckling safety calculator at `/app/truss_buckling.R`.

## API

```r
def slenderness(L: float, r_gyration: float, K: float) -> float: ...
def critical_load(E: float, I: float, K: float, L: float) -> float: ...
def safety_factors(envelope: dict, members: list) -> dict: ...
```

`slenderness` returns KL / r.

`critical_load` returns Pcr = pi^2 * E * I / (K*L)^2  in Newtons. Raise stop error if KL <=0.

`safety_factors` takes envelope dict mapping member_id to {"max_tension":float>=0, "max_compression":float<=0} as from task3, and members list each dict with id, A, E, I, r_gyration, K (default 1.0 if missing), L (or compute from joints? For simplicity members list includes L directly). Returns dict member_id -> safety factor float. For tension members or zero compression, FS = float('inf'). For compression, FS = Pcr / abs(P_compression). Flag FS<2.5 as fail but still return value; tests check numeric.

## Constraints

R base only. Deterministic.

## Grading

Relative tolerance 1e-4.
