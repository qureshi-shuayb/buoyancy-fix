# Virtual Work Deflection

Compute joint deflections in plane trusses using the principle of virtual work, implemented in pure Rust with stdlib only.

## Overview

This T-Bench task requires implementing a Rust library at `/app/src/lib.rs` that calculates member elongations, virtual member forces from a unit load, and resulting joint deflection via virtual work summation.

The virtual work method for trusses states:

```
delta = sum_over_members ( n * N * L ) / ( A * E )
```

where:
- N = real axial force in member from actual loads (N, tension positive)
- n = virtual axial force in member from unit dummy load at target joint and direction (N)
- L = member length (m)
- A = cross-sectional area (m^2)
- E = Young's modulus (Pa)
- delta = deflection at target joint in direction of unit load (m)

The method is exact for linear elastic statically determinate trusses under small deformations.

## Package Layout

* Root Cargo.toml: package `truss_deflection` version 0.1.0 edition 2021
* Library source expected at `/app/src/lib.rs` — default Cargo lib path, no custom path override
* Solution oracle at `solution/src/lib.rs` with embedded tests
* Verifier script at `tests/test.sh` runs `cargo test --quiet` and writes `/logs/verifier/reward.txt`

Docker base image: `rust:1.78-slim`, WORKDIR `/app`.

## Public API

All types and functions must be public and match signatures exactly:

```rust
pub struct Joint { pub id: String, pub x: f64, pub y: f64 }
pub struct Member { pub id: String, pub i: String, pub j: String, pub a: f64, pub e: f64 }
pub struct Support { pub joint_id: String, pub typ: String }
pub struct Load { pub joint_id: String, pub fx: f64, pub fy: f64 }
pub struct Truss { pub joints: Vec<Joint>, pub members: Vec<Member>, pub supports: Vec<Support> }

pub fn member_elongations(
    forces: &HashMap<String,f64>,
    lengths: &HashMap<String,f64>,
    areas: &HashMap<String,f64>,
    e: f64
) -> HashMap<String,f64>

pub fn virtual_forces(
    truss: &Truss,
    unit_joint: &str,
    direction: &str
) -> Result<HashMap<String,f64>, String>

pub fn deflection(
    truss: &Truss,
    real: &HashMap<String,f64>,
    virt: &HashMap<String,f64>
) -> f64
```

## Struct Details

* Joint: identifier and planar coordinates x,y in meters.
* Member: identifier, end joint ids i and j, cross-section area a in m^2, modulus e in Pa per member allowing heterogeneous material.
* Support: joint_id and typ either "pinned" (reactions rx, ry) or "roller" (ry vertical only).
* Load: point load at joint with fx, fy components in Newtons.
* Truss: container aggregating joints, members, supports. Loads are supplied separately to solver internals.

## Functions

### member_elongations
Computes delta = F*L/(A*E) per member. Input HashMaps keyed by member id. Returns HashMap of elongations in meters. Empty input produces empty output. Tension yields positive elongation.

### virtual_forces
Solves equilibrium for unit load case. Constructs 2J equilibrium equations for M member unknowns plus R reaction unknowns. Assumes statically determinate: M+R == 2J. Gaussian elimination with partial pivoting solves A x = b with b = -external loads. Returns member forces HashMap, tension positive. Err on singular matrix, unsupported support type, or indeterminacy.

Direction "x" applies 1 N in +x at unit_joint; "y" applies 1 N in +y. Other joints have zero load.

### deflection
Iterates members, computes length from joint coordinates, looks up real force and virtual force defaulting to 0, accumulates fv * fr * L / (a*e). Returns total deflection positive in unit load direction.

## Tolerance and Grading

Grading tolerance is 0.1% relative error. Tests check:

1. Elongation of 1000 N force on 2 m member area 0.01 m2 E 200 GPa equals 1e-6 m.
2. Virtual forces for triangle truss return 3 members without error.
3. Zero real forces yield zero deflection within 1e-9.
4. Loaded triangle truss yields positive downward deflection.
5. Empty force map yields empty elongation map.

`cargo test --quiet` must exit 0 for reward 1, else reward 0.

## Example Triangle Truss

Joints: A(0,0) pinned, B(6,0) roller, C(3,4)
Members: AB, AC, BC each A=0.01, E=200e9
Real load: 10 kN downward at C gives AB ~3750 N tension, AC ~ BC ~ -6250 N compression.
Unit load vertical at C yields virtual forces; deflection computed via sum is on order 0.1–1 mm downward, positive.

This example is used in oracle tests to validate sign and magnitude behavior.

## Constraints

* Rust stdlib only. No external crates. Use `std::collections::HashMap`.
* Deterministic, no I/O, no randomness, no network.
* Public API signatures must match exactly; visibility pub required.
* Error handling via Result for virtual_forces; String error message acceptable.
* Assume planar geometry, small strain linear elasticity.
* Code at `/app/src/lib.rs` compiled by `cargo test`.

## Development Notes

* Root Cargo.toml uses default lib path src/lib.rs, package name truss_deflection.
* Solution oracle implements Gaussian elimination to reduced row echelon form, reusable for real and virtual cases.
* Tests are embedded via #[cfg(test)] in the library the agent writes; tests/test.sh drives verification.
* Keep implementation numerically stable with partial pivoting and 1e-12 singularity threshold.

## Repository Structure

```
virtual-work-deflection/
  Cargo.toml              # root package, default src/lib.rs
  src/                    # agent writes lib.rs here at runtime (not in repo)
  solution/
    Cargo.toml
    src/lib.rs            # oracle implementation with 5 tests
  tests/
    test.sh               # verifier: cargo test --quiet -> reward.txt
  environment/
    Dockerfile            # rust:1.78-slim WORKDIR /app
  instruction.md
  README.md
  task.toml
```

Implement the library, run `cargo test`, ensure green for full reward.
