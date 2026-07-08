# Truss Static Solver

Implement a pure-Go planar truss static equilibrium solver at `/app/truss_solver.go`. Module must expose exactly two functions.

## Domain Model

Joints: list of structs with ID string X float64 Y float64
Members: list of structs with ID string I string J string A float64 E float64  A,E unused for statics but present for schema consistency.
Supports: list of structs with JointID string Type string "pinned" or "roller"  pinned provides rx and ry reactions, roller provides ry vertical only upward positive.
Loads: list of structs with JointID string Fx float64 Fy float64  forces in Newtons applied at joint, positive x right, y up.

Truss assumed statically determinate pin-jointed. Solve via equilibrium equations at each joint: sum Fx=0 sum Fy=0.

## Required API in `/app/truss_solver.go` package main

```go
type Joint struct { ID string; X float64; Y float64 }
type Member struct { ID string; I string; J string; A float64; E float64 }
type Support struct { JointID string; Type string }
type Load struct { JointID string; Fx float64; Fy float64 }
type Reaction struct { Rx float64; Ry float64 }

func SolveReactions(joints []Joint, supports []Support, loads []Load) (map[string]Reaction, error)
func SolveMemberForces(joints []Joint, members []Member, supports []Support, loads []Load) (map[string]float64, error)
```

SolveReactions returns map from support joint ID to Reaction. For roller Rx must be 0. Sum of reactions balances applied loads.

SolveMemberForces returns map from member ID to axial force Newtons positive tension negative compression. Must solve full system including reactions internally.

Return error on duplicate joint id, missing joint reference, zero-length member, unsupported support type, unstable or indeterminate topology where m+r != 2*j, singular matrix.

## Method

Assemble 2*j equilibrium equations for unknown member forces m plus reaction components r. Unknown vector order members then reactions expanding pinned to rx ry roller to ry. For each joint write Fx then Fy: sum incident members F*cos + reaction + applied fx =0. Cos = (xj-xi)/L sign positive tensile pulls away from joint. At j opposite sign.

Solve linear system Ax=b via Gaussian elimination partial pivot no external packages.

Tolerance reactions absolute 1e-3 N member forces relative 0.1pct or absolute 1e-3.

## Constraints

Go stdlib only. Module at /app/truss_solver.go package main. Deterministic.

## Grading

Independent reference compares outputs. All test groups must pass.
