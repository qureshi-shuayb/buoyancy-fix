# Truss Geometry Validator

Pure-Python truss topology validator for planar pin-jointed trusses. Parses JSON, checks static determinacy, builds adjacency and DOF maps.

Functions in `/app/truss_geometry.py`:
- `load_truss(path)`
- `check_determinacy(joints, members, supports)`
- `build_matrices(joints, members, supports)`

Part of bridge truss vehicle load simulator task suite.
