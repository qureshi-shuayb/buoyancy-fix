# Truss Static Solver

Pure-Go method of joints solver for planar pin trusses. Returns support reactions and member axial forces via static equilibrium.

Package main at `/app/truss_solver.go`.

## Description

Implements a statically determinate planar truss analyzer in pure Go without external dependencies. The solver assembles joint equilibrium equations ΣFx=0 ΣFy=0 for each joint, forming a linear system Ax=b where unknowns are member axial forces and support reactions. Solution uses Gaussian elimination with partial pivoting from Go standard library only. Suitable for educational statics, verification of simple trusses, and benchmark tasks requiring deterministic linear algebra.

## API

Go signatures matching instruction.md, package main at `/app/truss_solver.go`:

```go
type Joint struct { ID string; X float64; Y float64 }
type Member struct { ID string; I string; J string; A float64; E float64 }
type Support struct { JointID string; Type string } // "pinned" or "roller"
type Load struct { JointID string; Fx float64; Fy float64 }
type Reaction struct { Rx float64; Ry float64 }

func SolveReactions(joints []Joint, supports []Support, loads []Load) (map[string]Reaction, error)
func SolveMemberForces(joints []Joint, members []Member, supports []Support, loads []Load) (map[string]float64, error)
```

- `SolveReactions` returns map from support joint ID to Reaction. Roller Rx is 0. Sum of reactions balances applied loads within 1e-3 N.
- `SolveMemberForces` returns map from member ID to axial force in Newtons, positive tension negative compression. Solves full 2*j equilibrium system including reactions via Gaussian elimination with partial pivot, stdlib only.

## Error Cases

Return error on:
- duplicate joint id
- duplicate member id
- duplicate support at same joint
- missing joint reference in member, support, or load
- zero-length member where I==J or distance <1e-9
- unsupported support type not "pinned" or "roller"
- unstable topology where m + r < 2*j
- indeterminate topology where m + r > 2*j
- singular matrix during Gaussian elimination
- vertical alignment of pinned and roller causing zero moment arm
- missing pinned or roller support count not exactly 1 each for SolveReactions simplified path

## Tolerance

- Reactions absolute tolerance 1e-3 N.
- Member forces relative tolerance 0.1% or absolute 1e-3 N whichever larger.
- Deterministic output, no randomness, pure floating point math.

## Method Explanation

Gaussian elimination with partial pivot:

1. Map joints to indices 0..j-1, build unknown vector [F0..Fm-1, Rx0,Ry0,...].
2. For each joint i write two rows: Fx equilibrium then Fy.
3. For member k connecting I to J compute length L = hypot(xj-xi, yj-yi), direction cos cx=(xj-xi)/L cy=(yj-yi)/L. Add +cx,+cy at I row, -cx,-cy at J row assuming tensile positive pulling away.
4. For each support add columns: pinned contributes 1 in Rx row and 1 in Ry row, roller contributes 1 in Ry only.
5. Right hand side b = -applied Fx, -applied Fy at each joint.
6. Assemble A as 2j x (m+r). Require m+r == 2j for determinate.
7. Solve via Gaussian elimination: partial pivot select max abs in column, row swap, normalize pivot to 1, eliminate other rows fully to reduced row echelon, back substitute. No external packages.
8. Extract first m entries as member forces, remaining as reactions.

SolveReactions uses simplified global equilibrium for pinned+roller case: sum Fx sum Fy sum M about pinned to solve roller Ry then pinned components, faster path without full matrix.

## Example Usage Triangle Truss

```go
joints := []Joint{{"A",0,0},{"B",6,0},{"C",3,4}}
members := []Member{
    {"AB","A","B",0.01,200e9},
    {"AC","A","C",0.01,200e9},
    {"BC","B","C",0.01,200e9},
}
supports := []Support{{"A","pinned"},{"B","roller"}}
loads := []Load{{"C",0,-10000}}

r, _ := SolveReactions(joints, supports, loads)
// r["A"] ~ {Rx:0, Ry:5000}, r["B"] ~ {Rx:0, Ry:5000}

f, _ := SolveMemberForces(joints, members, supports, loads)
// f["AB"] ~ +3750 N tension
// f["AC"] ~ -6250 N compression
// f["BC"] ~ -6250 N compression
```

Equilibrium check: sum Ry = 10000 balances -10000 load, sum Rx =0, moment about A zero.

## Constraints

- Go stdlib only, no external imports beyond math and errors.
- Module at /app/truss_solver.go package main.
- Deterministic execution.
- No numpy, no cgo, no third-party linear algebra.
- Input structs include A,E fields for schema consistency but unused in statics.
- Supports only planar pin-jointed trusses, statically determinate.

## Existing Content Preserved

Pure-Go method of joints solver for planar pin trusses. Returns support reactions and member axial forces via static equilibrium.

- Errors on duplicate joint ID, duplicate member ID, missing joint reference, zero-length member, unsupported support type, duplicate support, unstable or indeterminate topology where m+r != 2*j, or singular matrix.
- Tolerance: reactions absolute 1e-3 N, member forces relative 0.1% or absolute 1e-3.
- Deterministic, no external packages, Go stdlib only.
