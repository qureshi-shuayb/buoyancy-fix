# Truss Geometry Validator

Pure-Ruby truss topology validator for planar pin-jointed trusses. Parses JSON, checks static determinacy via m+r vs 2j, detects coincident joints and zero-length members, builds adjacency and DOF mapping matrices.

Module in `/app/truss_geometry.rb`:
```ruby
module TrussGeometry
  def self.load_truss(path)
  def self.check_determinacy(joints, members, supports)
  def self.build_matrices(joints, members, supports)
end
```

Part of bridge truss vehicle load simulator task suite. Fills Ruby gap in ADO portfolio.
