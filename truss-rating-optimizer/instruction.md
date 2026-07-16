# Truss Rating Optimizer (Julia)

Implement pure-Julia load rating optimizer at `/app/truss_rating.jl`. Use only Julia stdlib (no external packages). File must define three functions exactly as named.

## Domain Model

Truss is `Dict` with keys:
- `"joints"`: Vector of Dicts `{"id"=>String, "x"=>Float64, "y"=>Float64}`. `x` horizontal, `y` vertical (positive up). Deck is bottom chord (minimum y).
- `"members"`: Vector of Dicts `{"id"=>String, "i"=>String, "j"=>String, "A"=>Float64, "E"=>Float64, "capacity"=>Float64, "dead_force"=>Float64}`. `i`/`j` are joint ids. `A`/`E` unused for statics but present. `capacity` >0 positive magnitude (tension or absolute compression capacity). `dead_force` signed or magnitude - use `abs()` for rating; may be missing (default 0). For influence tests, capacity/dead_force may be absent.
- `"supports"`: Vector of Dicts `{"joint_id"=>String, "type"=>String}` where type is `"pinned"` (provides rx, ry) or `"roller"` (provides ry only, vertical).

Loads for internal solver: Dict `{"joint_id"=>String, "fx"=>Float64, "fy"=>Float64}`.

## Required API

```julia
function influence_coefficient(member_id::String, joint_id::String, truss::Dict)::Float64
function rating_factor(member_capacity::Float64, dead_load_force::Float64, live_envelope::Float64)::Float64
function optimize_rating(truss::Dict, vehicle::Dict, target_RF::Float64)::Dict
```

All three must be defined at top-level in `/app/truss_rating.jl`.

### 1. `influence_coefficient`

Returns influence of a unit vertical load at `joint_id` on axial force of member `member_id`.

Algorithm:
- Assemble equilibrium from method of joints: for each joint, sum Fx=0, sum Fy=0. Unknowns = member axial forces (tension positive, pulls away from joint) + reaction components. Order unknowns = members in input order, then reactions expanded as pinned=>rx,ry and roller=>ry in support input order.
- For each member `i-j`: L=hypot(xj-xi, yj-yi), cx=(xj-xi)/L, cy=(yj-yi)/L. Add +cx,+cy to joint i row, -cx,-cy to joint j row.
- Reactions: 1.0 at corresponding equilibrium row.
- Loads: single unit load `fx=0.0, fy=1.0` upward at `joint_id`. RHS `b = -applied_forces`.
- Check determinacy: `m + r == 2*j`. If not, `error("indeterminate or unstable")` (throw `ErrorException`).
- Zero-length member (`L<1e-9`) -> `error(...)`.
- Duplicate joint id or missing joint reference -> `error(...)`.
- Solve linear system `A x = b` via Gaussian elimination with partial pivoting (no external linear algebra packages). Singular (pivot <1e-12) -> `error("singular")`.
- Return `solve_result[member_id]` if exists else 0.0.
- Error cases: unknown `member_id` or `joint_id` -> `error(...)` must throw `ErrorException` (tests use `@test_throws ErrorException`).

Reference analytic for triangle truss `A(0,0), B(6,0), C(3,4)`, members AB,AC,BC, pinned A, roller B, unit at C: `IC(AC)≈0.625, IC(AB)≈-0.375` within 0.05.

### 2. `rating_factor`

Computes AASHTO-style rating factor simplified:

```
phi = 0.9  (hardcoded resistance factor)
if live_envelope <= 0.0: return Inf
else: return (member_capacity - abs(dead_load_force)) / live_envelope * phi
```

- `member_capacity` >0 positive magnitude.
- `dead_load_force` may be signed - take `abs()`.
- `live_envelope` positive magnitude; <=0 returns `Inf`.
- Can be negative if `capacity < abs(dead)`.
- Must return `Float64` (or `Inf`).

### 3. `optimize_rating`

Finds maximum vehicle scale factor `s` such that minimum rating factor across all members >= `target_RF`.

Simplified live envelope model (intentionally simplified for tractability, non-canonical):

1. Deck detection: `min_y = minimum(j["y"] for j in joints)`. Deck joints = `filter(abs(y-min_y)<1e-6)`, sorted by `x` ascending. `deck_ids` = ids in that order.
2. Span: `xs = [x for deck joints]; span = maximum(xs)-minimum(xs)`. If `span<=0` then `I=1.0` else `I = 1.0 + 15.0/(span+38.0)` (custom impact factor).
3. Influence sums: for each member `mid`: `infl_sum[mid] = sum_{jid in deck_ids} abs(influence_coefficient(mid,jid,truss))`
4. Vehicle: `Dict("axle_weights"=>Vector{Float64}, "spacings"=>Vector{Float64})`. `axle_sum = sum(vehicle["axle_weights"])`. Note: `spacings` field is present for API compatibility with moving-load version but intentionally ignored in this v1 simplified envelope. Live envelope scales linearly with `s`.
5. For a given scale `s`: `live(mid,s) = s * axle_sum * I * infl_sum[mid]`. `rf(mid,s) = rating_factor(capacity, dead_force, live)`. `min_rf(s) = minimum_m rf(mid,s)` and critical member is argmin.
6. Binary search: `lo=0.0, hi=5.0`, 40 iterations: `mid=(lo+hi)/2; if min_rf(mid)>=target_RF lo=mid else hi=mid`.
7. Return `Dict("scale_factor"=>lo, "achieved_RF"=>min_rf(lo), "critical_member"=>crit)` where crit is member id with minimum RF at final lo.

Constraints:
- `truss["members"][i]["capacity"]` required, `dead_force` may be missing default 0.
- Must handle missing `spacings` gracefully but tests provide it.
- Return types: `scale_factor` Float64 between 0 and 5, `achieved_RF` Float64, `critical_member` String.

## Grading

- `rating_factor` exact formula within 1e-9, Inf cases exact.
- `influence_coefficient` analytic check 0.05 absolute tolerance for triangle truss, throw checks.
- `optimize_rating`: scale_factor within 1% relative tolerance of reference, achieved_RF ≈ target_RF within 0.02 absolute, critical_member exact string match (e.g., `"m4"`), monotonic property: higher target -> lower scale.
- Tolerance 1% relative on scale factor as stated.

## What NOT to do

- Do not implement full moving-load axle positioning using spacings; this version sums influence over deck joints and scales by `sum(axle_weights)`. This is intentional simplification.
- Do not use external Julia packages, only stdlib and your own Gaussian elimination.
