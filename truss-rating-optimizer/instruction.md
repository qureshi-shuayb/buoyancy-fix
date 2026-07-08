# Truss Rating Optimizer

Implement pure-Julia load rating optimizer at `/app/truss_rating.jl`. Module must expose exactly three functions.

## Domain Model

Truss Dict with keys "joints" array of Dict id x y, "members" array of Dict id i j A E capacity dead_force, "supports" array of Dict joint_id type pinned|roller. Vehicle Dict with axle_weights array Float64 and spacings array Float64 length weights-1. Bridge deck panel points are joints with minimal y sorted by x ascending. Span L = max x - min x. Front axle position is distance from leftmost panel point along bridge towards increasing x. Subsequent axles are behind front axle towards decreasing x by cumulative spacing. Impact factor I = 1 + 15/(L+38).

## Required API in `/app/truss_rating.jl`

```julia
function influence_coefficient(member_id::String, joint_id::String, truss::Dict)::Float64
function rating_factor(member_capacity::Float64, dead_load_force::Float64, live_envelope::Float64)::Float64
function optimize_rating(truss::Dict, vehicle::Dict, target_RF::Float64)::Dict
```

influence_coefficient returns axial force in member due to unit vertical load 1.0 Newton applied downward at specified joint, positive tension negative compression, computed by solving truss equilibrium via Gaussian elimination with partial pivot, no external packages.

rating_factor computes RF = (capacity - abs(dead_load_force)) / live_envelope * phi with phi = 0.9 hard-coded. If live_envelope <= 0 return Inf. capacity, dead, live are positive magnitudes except dead may be signed in input but use absolute value.

optimize_rating finds maximum scale factor s such that minimum RF across all members >= target_RF, assuming live envelope scales linearly with s. Use binary search between 0.0 and 5.0 with 40 iterations tolerance ~1e-3. Compute influence coefficients once per member per deck joint. Compute live force magnitude for each member as s * sum(axle_weights) * I * sum_abs_influence where sum_abs_influence = sum over deck joints of abs(influence_coefficient(member, joint)). Assume dead load forces provided in members as dead_force field signed, use absolute value in RF formula. Return Dict with keys "scale_factor" Float64, "achieved_RF" Float64, "critical_member" String of member with minimum RF at optimum scale.

Raise error on invalid inputs, singular matrix, non-positive KL in underlying solver if reused.

## Constraints

Julia 1.10 stdlib only, no packages beyond Base LinearAlgebra Printf etc allowed but prefer pure implementation without LinearAlgebra solve to match Gaussian elimination spec for educational transparency; you may use LinearAlgebra for reference but final implementation must be self-contained Gaussian elimination to ensure determinism across versions, or you may implement own gauss as in reference solution.

File at /app/truss_rating.jl. Deterministic.

## Grading

Outputs compared against reference within 1% relative tolerance for scale_factor, 1% for achieved_RF, exact string match for critical_member. All test groups must pass.
