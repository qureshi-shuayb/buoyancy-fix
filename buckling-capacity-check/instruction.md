# Buckling Capacity Check

Implement pure-R Euler buckling safety calculator at `/app/truss_buckling.R`.

## API

```r
slenderness <- function(L, r_gyration, K) ...
critical_load <- function(E, I, K, L) ...
safety_factors <- function(envelope, members) ...
```

`slenderness` returns KL / r as numeric scalar. Raise stop error if r_gyration <= 0.

`critical_load` returns Pcr = pi^2 * E * I / (K*L)^2 in Newtons as numeric scalar. Raise stop error with stop() if KL <= 0.

`safety_factors` takes envelope as named R list mapping member_id to list(max_tension=numeric>=0, max_compression=numeric<=0), and members as list of lists each with fields id character, A numeric, E numeric, I numeric, r_gyration numeric, K numeric default 1.0 if missing or NULL, L numeric. Returns named list member_id -> safety factor numeric. For tension members or zero compression, FS = Inf. For compression, FS = Pcr / abs(P_compression). Flag FS < 2.5 as fail but still return value; tests check numeric within tolerance.

Example envelope structure in R:
```r
envelope <- list(
  M1 = list(max_tension = 0, max_compression = -10000),
  M2 = list(max_tension = 5000, max_compression = 0)
)
```

Example members structure in R:
```r
members <- list(
  list(id="M1", E=200e9, I=1e-5, L=2.0, K=1.0, A=0.01, r_gyration=0.05),
  list(id="M2", E=200e9, I=1e-5, L=2.0, K=1.0, A=0.01, r_gyration=0.05)
)
```

## Constraints

R base only. No external packages. Deterministic output. Use stop() for errors. Return Inf for infinite safety factor, not NA or NULL.

## Grading

Relative tolerance 1e-4 absolute tolerance 1e-9 for slenderness exact checks. Tests verify slenderness, critical_load, safety_factors, and error handling.
