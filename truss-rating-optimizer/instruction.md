# Truss Rating Optimizer

Implement pure-Julia load rating optimizer at `/app/truss_rating.jl`.

## API

```julia
def influence_coefficient(member_id: str, joint_id: str, truss: dict) -> float: ...
def rating_factor(member_capacity: float, dead_load_force: float, live_envelope: float) -> float: ...
def optimize_rating(truss: dict, vehicle: dict, target_RF: float) -> dict: ...
```

`influence_coefficient` returns approximate influence of unit vertical load at joint_id on member axial force. Compute by solving truss with unit load at joint (using same solver as previous tasks) and returning member force. Truss dict has joints members supports.

`rating_factor` computes RF = (capacity - dead) / live * phi, with phi=0.9 default hardcoded. capacity positive for tension capacity, or absolute compression capacity positive. dead_load_force signed (+ tension - compression) matching live sign convention? Simplify: assume absolute values, dead positive magnitude, live positive magnitude, capacity positive. Return RF float; if live<=0 return inf.

`optimize_rating` given truss dict (with members having capacity field), vehicle dict as previous (axle_weights spacings), target_RF float, find maximum scale factor s such that min RF across members >= target_RF, where live envelope scales linearly with s. Use binary search between 0 and 5 with tolerance 1e-3. Assume dead load forces provided in truss members as dead_force field (signed). Live envelope computed via simplified method: for each member, live force magnitude = max absolute value from envelope calculation approximated as proportional to vehicle weight sum times influence coefficient magnitude summed over deck joints? To keep tractable, tests will use simplified truss where we define expected behavior via reference implementation that mirrors agent logic: compute influence coefficients once, then live = s * sum |influence| * axle_weight_sum * impact factor. Implement that simplified model.

Return dict {"scale_factor": float, "achieved_RF": float, "critical_member": str }.

## Constraints

Julia stdlib only.

## Grading

Tolerance 1% relative on scale factor.
