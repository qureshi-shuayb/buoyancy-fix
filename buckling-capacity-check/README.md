# Buckling Capacity Check

Pure R implementation of Euler buckling safety factor calculator for truss compression members. Computes slenderness ratio, Euler critical load, and safety factors versus envelope compression forces.

## Overview

Euler buckling describes elastic instability of slender compression members. Critical load Pcr = pi^2 * E * I / (K*L)^2 where E is Young's modulus, I is area moment of inertia, K is effective length factor, L is member length. Slenderness lambda = K*L / r where r is radius of gyration. Safety factor FS = Pcr / |P_compression|. Tension members return Inf.

This task implements three R base functions in `/app/truss_buckling.R` with no external dependencies, deterministic numeric output, and strict error handling via `stop()`.

## API

### slenderness
```r
slenderness <- function(L, r_gyration, K)
```
Parameters:
- L numeric >0 : member length in meters
- r_gyration numeric >0 : radius of gyration in meters
- K numeric >0 : effective length factor, typically 1.0

Returns numeric scalar KL / r. Raises stop error if r_gyration <=0 or KL <=0.

### critical_load
```r
critical_load <- function(E, I, K, L)
```
Parameters:
- E numeric >0 : Young's modulus in Pa
- I numeric >0 : second moment of area in m^4
- K numeric >0 : effective length factor
- L numeric >0 : length in m

Returns numeric scalar Pcr in Newtons. Formula pi^2 * E * I / (K*L)^2. Raises stop error if KL <=0.

### safety_factors
```r
safety_factors <- function(envelope, members)
```
Parameters:
- envelope named list: member_id -> list(max_tension >=0, max_compression <=0)
- members list of lists: each with id character, A numeric, E numeric, I numeric, r_gyration numeric, L numeric, K numeric optional default 1.0

Returns named list member_id -> numeric safety factor. Inf for tension or zero compression. Numeric FS = Pcr / abs(compression) otherwise. Values <2.5 flagged but returned.

## Error Handling

All functions use base R `stop()` for invalid inputs: non-positive KL, non-positive r_gyration, missing required fields. No warnings, no NA returns except Inf is valid output for safety_factors.

## Tolerance

Grading uses relative tolerance 1e-4 and absolute tolerance 1e-9 for exact slenderness checks. Numeric comparisons must be stable across R 4.3.0 base.

## Example

```r
source("/app/truss_buckling.R")
slenderness(3.0, 0.05, 1.0)  # 60
# 60

E <- 200e9; I <- 8.33e-6; K <- 1; L <- 3
critical_load(E, I, K, L)
# pi^2 * E * I / (K*L)^2 = approx 1.827e6 N

envelope <- list(M1=list(max_tension=0, max_compression=-10000),
                 M2=list(max_tension=5000, max_compression=0))
members <- list(
  list(id="M1", E=200e9, I=1e-5, L=2.0, K=1.0, A=0.01, r_gyration=0.05),
  list(id="M2", E=200e9, I=1e-5, L=2.0, K=1.0, A=0.01, r_gyration=0.05)
)
safety_factors(envelope, members)
# $M1 ~ 493.48  $M2 Inf
```

## Constraints

- R base only, no packages, no tidyverse, no data.table
- File location: `/app/truss_buckling.R`
- Deterministic, no randomness, no I/O side effects
- Compatible with r-base:4.3.0 Docker image

## Grading

Tests in `/tests/test_outputs.R` executed via `Rscript`. Reward 1 on zero exit status, 0 otherwise. Checks slenderness exact 60, critical_load relative error, safety_factors Inf handling and positive value, error throwing on KL=0.

## Project Structure

- `instruction.md` – task specification with R API
- `solution/truss_buckling.R` – reference implementation
- `tests/test_outputs.R` – verifier script
- `tests/test.sh` – shell wrapper writing reward.txt
- `environment/Dockerfile` – FROM r-base:4.3.0 WORKDIR /app
- `task.toml` – schema 1.1 metadata

## License Note

Benchmark data canary GUID r-buck-001 included to prevent training corpus contamination.
