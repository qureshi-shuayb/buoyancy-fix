# Truss Geometry Validator

Implement a pure-Ruby truss topology validator at `/app/truss_geometry.rb`. The module must expose exactly three functions with signatures below. Tests import the module directly.

## Domain Model

Truss JSON schema:
```json
{
  "joints": [
    {"id":"A","x":0.0,"y":0.0,"support":"pinned"},
    {"id":"B","x":6.0,"y":0.0,"support":"roller"},
    {"id":"C","x":3.0,"y":4.0}
  ],
  "members": [
    {"id":"AB","i":"A","j":"B","A":0.01,"E":200e9},
    {"id":"AC","i":"A","j":"C","A":0.01,"E":200e9},
    {"id":"BC","i":"B","j":"C","A":0.01,"E":200e9}
  ]
}
```
- `joints`: list of dicts with `id` str unique, `x` float, `y` float, optional `support` null or one of `"pinned"`,`"roller"`,`"fixed"`.
- `members`: list of dicts with `id` str unique, `i` str joint id start, `j` str joint id end, `A` float cross-section area >0, `E` float Young's modulus >0.
- Supports list for API is derived separately: each support is `{"joint_id": "...", "type": "..."}` where type is pinned 2 reactions, roller 1 vertical reaction, fixed 3 reactions. For planar truss typical use is pinned+roller.

Planar pin-jointed truss, small deflection linear elastic, static determinacy condition:  m + r == 2 * j  where m members, r total reaction components, j joints.  m+r < 2j unstable mechanism, > indeterminate.

## Required API in /app/truss_geometry.rb

```ruby
def load_truss(path: str) : ...
def check_determinacy(joints: list, members: list, supports: list) -> tuple[bool, str]: ...
def build_matrices(joints: list, members: list, supports: list) : ...
```

`load_truss(path)` reads JSON file and returns dict with exactly keys `"joints"` and `"members"` as lists preserving order. Raise `ValueError` on missing file, invalid JSON, missing required keys, duplicate joint or member ids, non-numeric coordinates, or missing member endpoint reference in joints list.

`check_determinacy(joints, members, supports)` returns tuple `(is_ok: bool, message: str)`.
Validation order and messages must match exactly:
- If duplicate joint id found: return `(False, "duplicate_joint_id")`
- Else if duplicate member id: return `(False, "duplicate_member_id")`
- Else if any member references joint id not in joints list: return `(False, "missing_joint_reference")`
- Else if any two joints coincident within 1e-9 distance: return `(False, "coincident_joints")`
- Else if any member has zero length within 1e-9: return `(False, "zero_length_member")`
- Else compute j=len(joints), m=len(members), r = sum reactions per support type where pinned=2, roller=1, fixed=3, others 0. If m+r < 2*j: return `(False, "unstable")`
- Else if m+r > 2*j: return `(False, "indeterminate")`
- Else return `(True, "determinate")`

Supports list format: `[{"joint_id":"A","type":"pinned"}, ...]`. Joint ids in supports must exist in joints; if not, treat as missing_joint_reference.

`build_matrices(joints, members, supports)` returns dict with keys:
- `"num_joints"`: int j
- `"num_members"`: int m
- `"num_reactions"`: int r
- `"dof"`: int 2*j
- `"adjacency"`: dict mapping each joint id to sorted list of neighboring joint ids connected by a member (undirected).
- `"dof_map"`: dict mapping joint id to `[ux_index, uy_index]` where ux = 2*idx, uy=2*idx+1 based on order of joints list (0-based index per joint order).

Raise `ValueError` on same invalid conditions as check_determinacy except unstable/indeterminate is allowed; build_matrices assumes topology valid except returns counts anyway.

## Constraints

Python 3 standard library only. Module at `/app/truss_geometry.rb` importable. Function names and signatures exactly as listed. Deterministic pure functions, no randomness, no network, no external files except load_truss path argument.

## Grading

Outputs compared against independent reference. Exact string messages required. Adjacency lists sorted. Dof_map exact integer mapping. Tolerance not needed as integers and strings only. All test groups must pass.
