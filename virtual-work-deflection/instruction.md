# Virtual Work Deflection

Implement pure-Rust virtual work deflection calculator at `/app/src/lib.rs`.

## API

```rust
def member_elongations(forces: dict, lengths: dict, areas: dict, E: float) -> dict: ...
def virtual_forces(truss: dict, unit_load_joint: str, direction: str) -> dict: ...
def deflection(truss: dict, real_forces: dict, virtual_forces_dict: dict) -> float: ...
```

`member_elongations` takes forces dict member_id->force N (+ tension), lengths dict member_id->L m, areas dict member_id->A m2, E float Pa (uniform or override per member if areas dict contains E? Use uniform E). Returns dict member_id -> elongation delta = F*L/(A*E).

`virtual_forces` computes member forces due to unit load (1 N) applied at specified joint in direction "x" or "y". Truss dict contains joints members supports as previous tasks. Use same Gaussian elimination solver as task2 to solve virtual case with single unit load at target joint, other loads zero. Returns dict member_id -> virtual force.

`deflection` computes virtual work sum over members: sum ( virtual_force * real_force * L ) / (A*E). Truss dict must contain member geometry to compute L and A,E per member (assume each member dict has A,E). Returns float deflection in meters positive in direction of unit load. Check against L/800 serviceability outside scope; just return value.

## Constraints

Rust stdlib only. Deterministic.

## Grading

Tolerance 0.1% relative.
