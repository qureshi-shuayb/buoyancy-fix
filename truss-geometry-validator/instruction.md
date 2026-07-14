# Truss Geometry Validator

Implement pure-Ruby space truss topology validator at `/app/truss_geometry.rb`. Module must expose exactly three methods in module TrussGeometry.

## Domain Model

Truss JSON schema with joints array each hash with id string unique, x float, y float, z float, optional support nil or "pinned" "roller" "fixed". Members array each hash id string unique, i string start joint id, j string end joint id, A float >0, E float >0. Supports array separate for API each hash joint_id string type string.

Space pin-jointed truss static determinacy condition m + r == 3*j where m members, r total reaction components, j joints. m+r <3j unstable, > indeterminate. Each joint has three translational degrees of freedom in 3D. Kinematic mechanism is detected via equilibrium matrix rank deficiency even when counts match: build equilibrium matrix B size 3j rows by m+r columns, compute rank with Gaussian elimination tolerance 1e-9, if rank < 3j then mechanism.

## Required API in /app/truss_geometry.rb

```ruby
module TrussGeometry
  def self.load_truss(path) # returns Hash with "joints" and "members" arrays, raises RuntimeError on invalid
  def self.check_determinacy(joints, members, supports) # returns [bool, String]
  def self.build_matrices(joints, members, supports) # returns Hash
end
```

load_truss reads JSON file returns Hash with exactly keys "joints" and "members" preserving order. Raise RuntimeError on missing file invalid JSON missing required keys duplicate joint or member ids non-numeric coordinates or missing member endpoint reference.

check_determinacy returns two-element Array [is_ok Boolean, message String]. Validation order messages must match exactly:
- duplicate joint id => [false, "duplicate_joint_id"]
- duplicate member id => [false, "duplicate_member_id"]
- member references joint id not in joints list => [false, "missing_joint_reference"]
- supports reference joint not in joints => [false, "missing_joint_reference"]
- any two joints coincident within 1e-9 Euclidean distance in 3D => [false, "coincident_joints"]
- any member zero length within 1e-9 in 3D => [false, "zero_length_member"]
- unsupported support type treated as 0 reactions; if after counting m+r < 3*j => [false, "unstable"]; elsif m+r > 3*j => [false, "indeterminate"]; elsif rank deficiency mechanism => [false, "mechanism"]; else [true, "determinate"]

Supports format array of hashes {"joint_id"=>"A","type"=>"pinned"} or {"joint_id"=>"B","type"=>"roller","direction"=>"X"}. Pinned 3 reactions along global X Y Z ignoring direction field, roller 1 reaction along specified axis default Z if direction missing or invalid, fixed 6 reactions along X Y Z X Y Z in that order repeating unit vectors to preserve count ignoring direction, others 0. Reaction directions define equilibrium matrix columns. Direction must be one of "X","Y","Z" case-insensitive, default Z.

Equilibrium matrix B algorithm: rows = 3*j ordered by joints input order each joint contributes ux uy uz rows at 3*idx,3*idx+1,3*idx+2. Columns 0..m-1 are members, then r support reaction columns in supports input order expanding per type. For member k connecting i to j compute dx = xj-xi, dy = yj-yi, dz = zj-zi, L = sqrt(dx*dx+dy*dy+dz*dz), cx=dx/L cy=dy/L cz=dz/L. Set B[3*idx_i][k]=+cx, B[3*idx_i+1][k]=+cy, B[3*idx_i+2][k]=+cz, B[3*idx_j][k]=-cx, B[3*idx_j+1][k]=-cy, B[3*idx_j+2][k]=-cz. For support reaction column s at joint jid with direction vector v in { [1,0,0],[0,1,0],[0,0,1] } per type order above, set B[3*idx][s]=v0, B[3*idx+1][s]=v1, B[3*idx+2][s]=v2, all other rows 0. Compute rank via Gaussian elimination with partial pivot and tolerance 1e-9 absolute pivot threshold. If rank < 3*j return mechanism.

build_matrices returns Hash with keys "num_joints" Integer, "num_members" Integer, "num_reactions" Integer, "dof" Integer 3*j, "adjacency" Hash mapping joint id to sorted Array of neighbor joint ids, "dof_map" Hash mapping joint id to Array [ux_index, uy_index, uz_index] 0-based based on joints order, "equilibrium_rows" Integer 3*j, "equilibrium_cols" Integer m+r, "rank" Integer, "is_mechanism" Boolean rank<3*j. Raise RuntimeError on same invalid conditions as check_determinacy except unstable indeterminate mechanism allowed.

## Constraints

Ruby 3 stdlib only JSON required. File at /app/truss_geometry.rb. Deterministic pure functions no randomness network.

## Grading

Exact string messages required. Adjacency lists sorted. Dof_map exact integer mapping. All test groups must pass.
