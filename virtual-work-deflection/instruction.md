# Virtual Work Deflection

Implement pure-Rust virtual work deflection calculator at `/app/src/lib.rs`.

The task computes joint deflections in statically determinate plane trusses using the principle of virtual work: δ = Σ ( n · N · L ) / ( A · E ), where N are real member forces, n are virtual member forces from a unit load, L length, A cross-section area, E Young's modulus.

## API

Implement the following public Rust API in `src/lib.rs`:

```rust
use std::collections::HashMap;

#[derive(Clone, Debug)]
pub struct Joint {
    pub id: String,
    pub x: f64,
    pub y: f64,
}

#[derive(Clone, Debug)]
pub struct Member {
    pub id: String,
    pub i: String,
    pub j: String,
    pub a: f64,
    pub e: f64,
}

#[derive(Clone, Debug)]
pub struct Support {
    pub joint_id: String,
    pub typ: String, // "pinned" or "roller"
}

#[derive(Clone, Debug)]
pub struct Load {
    pub joint_id: String,
    pub fx: f64,
    pub fy: f64,
}

#[derive(Debug)]
pub struct Truss {
    pub joints: Vec<Joint>,
    pub members: Vec<Member>,
    pub supports: Vec<Support>,
}

pub fn member_elongations(
    forces: &HashMap<String, f64>,
    lengths: &HashMap<String, f64>,
    areas: &HashMap<String, f64>,
    e: f64,
) -> HashMap<String, f64>

pub fn virtual_forces(
    truss: &Truss,
    unit_joint: &str,
    direction: &str,
) -> Result<HashMap<String, f64>, String>

pub fn deflection(
    truss: &Truss,
    real: &HashMap<String, f64>,
    virt: &HashMap<String, f64>,
) -> f64
```

## Function Semantics

`member_elongations` takes forces dict member_id -> force N (+ tension positive, - compression), lengths dict member_id -> L in meters, areas dict member_id -> A in m², E float Pa uniform modulus. Returns HashMap member_id -> elongation delta = F * L / (A * E). Empty input yields empty output. Deterministic.

`virtual_forces` computes member forces due to unit load 1 N applied at specified joint in direction "x" or "y". Truss struct contains joints, members, supports as defined above. Use method of joints equilibrium to assemble 2*J equations for M+R unknowns. Assume statically determinate: M + R == 2*J where R is 2 per pinned, 1 per roller. Supports: typ "pinned" provides rx and ry reactions, "roller" provides ry only vertical. Other loads zero except unit load. Solve linear system via Gaussian elimination with partial pivoting. Return Err string on singular or indeterminate. Returns HashMap member_id -> virtual force N positive tension.

`deflection` computes virtual work sum over members: sum_v = Σ virtual_force * real_force * L / (A * E). Truss must contain member geometry to compute L from joint coordinates and A,E per member from Member struct fields a and e. Real HashMap is member_id -> real force from actual loads. Virt HashMap is member_id -> virtual force from unit load case. Returns f64 deflection in meters positive in direction of unit load. Tolerance for grading 0.1% relative.

## Algorithm Notes

1. Map joint ids to indices 0..J-1. Build load vector per joint from Load list or unit load.
2. For each member k connecting i-j compute length L_k = hypot(xj-xi, yj-yi), direction cosines cx = (xj-xi)/L, cy = (yj-yi)/L.
3. Equilibrium equations: at each joint sum Fx = 0, sum Fy = 0. Member force contributes +cx,+cy at i end and -cx,-cy at j end assuming tension positive pulling away from joint.
4. Reaction columns: pinned adds rx column with 1 at Fx equation of that joint and ry column with 1 at Fy equation; roller adds ry only.
5. Solve A x = b where b = - external loads. Use Gaussian elimination to reduced row echelon; return first M components as member forces.
6. For deflection, iterate members, lookup real and virtual forces defaulting 0, compute L, accumulate fv*fr*L/(a*e).

## Constraints

* Rust stdlib only, no external crates. Use std::collections::HashMap.
* Deterministic output, no randomness, no I/O, no unsafe unless necessary.
* Public API must match signatures exactly for tests to link.
* Handle errors via Result Err String for virtual_forces; other functions panic only on invalid internal logic not on valid inputs.
* Assume planar truss, small deformations, linear elastic material.
* Tolerance 0.1% relative for grading; use f64 arithmetic.

## Grading

Tests embedded via `#[cfg(test)]` in solution verify: elongation calculation, virtual forces size 3 for triangle, zero deflection for zero real forces, positive deflection for loaded triangle, empty elongation map. Your implementation in `/app/src/lib.rs` must pass `cargo test --quiet` producing exit 0 to earn reward 1.

## Example

Triangle truss A(0,0) pinned, B(6,0) roller, C(3,4). Members AB, AC, BC each A=0.01 m² E=200 GPa. Real forces under 10 kN downward at C: AB ≈ 3750 N tension, AC ≈ BC ≈ -6250 N compression. Unit vertical load at C yields virtual forces; deflection ≈ Σ n N L / AE >0 downward on order 1e-4 to 1e-3 m.

Implement at `/app/src/lib.rs`.
