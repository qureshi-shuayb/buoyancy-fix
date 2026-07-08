# Truss Geometry Validator

Implement pure-Ruby truss topology validator at `/app/truss_geometry.rb`. Module must expose exactly three methods in module TrussGeometry.

## Domain Model

Truss JSON schema with joints array each hash with id string unique, x float, y float, optional support nil or "pinned" "roller" "fixed". Members array each hash id string unique, i string start joint id, j string end joint id, A float >0, E float >0. Supports array separate for API each hash joint_id string type string.

Planar pin-jointed truss static determinacy condition m + r == 2*j where m members, r total reaction components, j joints. m+r <2j unstable, > indeterminate.

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
- any two joints coincident within 1e-9 distance => [false, "coincident_joints"]
- any member zero length within 1e-9 => [false, "zero_length_member"]
- unsupported support type treated as 0 reactions; if after counting m+r < 2*j => [false, "unstable"]; elsif m+r > 2*j => [false, "indeterminate"]; else [true, "determinate"]

Supports format array of hashes {"joint_id"=>"A","type"=>"pinned"}. Pinned 2 reactions, roller 1, fixed 3, others 0.

build_matrices returns Hash with keys "num_joints" Integer, "num_members" Integer, "num_reactions" Integer, "dof" Integer 2*j, "adjacency" Hash mapping joint id to sorted Array of neighbor joint ids, "dof_map" Hash mapping joint id to Array [ux_index, uy_index] 0-based based on joints order. Raise RuntimeError on same invalid conditions as check_determinacy except unstable indeterminate allowed.

## Constraints

Ruby 3 stdlib only JSON required. File at /app/truss_geometry.rb. Deterministic pure functions no randomness network.

## Grading

Exact string messages required. Adjacency lists sorted. Dof_map exact integer mapping. All test groups must pass.
