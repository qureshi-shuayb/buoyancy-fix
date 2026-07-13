# Truss Static Solver

Pure-Go method of joints solver for planar pin trusses. Returns support reactions and member axial forces via static equilibrium.

Package main at `/app/truss_solver.go`:

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
- Errors on duplicate joint ID, duplicate member ID, missing joint reference, zero-length member, unsupported support type, duplicate support, unstable or indeterminate topology where m+r != 2*j, or singular matrix.
- Tolerance: reactions absolute 1e-3 N, member forces relative 0.1% or absolute 1e-3.
- Deterministic, no external packages, Go stdlib only.
