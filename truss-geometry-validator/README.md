# Truss Geometry Validator

Pure-Ruby space truss topology validator for 3D pin-jointed space trusses. Parses JSON, checks static determinacy via m+r vs 3j, detects kinematic mechanisms via equilibrium matrix rank deficiency with Gaussian elimination, builds adjacency and 3-DOF per joint maps with equilibrium rank output.

Functions in `/app/truss_geometry.rb`:
- `load_truss(path)`
- `check_determinacy(joints, members, supports)`
- `build_matrices(joints, members, supports)`

Part of bridge truss vehicle load simulator task suite.
