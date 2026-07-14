# Truss Geometry Validator

Pure-Ruby space truss finite element solver for 3D pin-jointed space trusses. Parses JSON, checks static determinacy via m+r vs 3j, detects kinematic mechanisms via equilibrium matrix rank deficiency with Gaussian elimination, assembles sparse global stiffness matrix, performs LDLT Cholesky solve for nodal displacements under loads, recovers reactions strain energy condition estimate, and detects unstable_singular.

Functions in `/app/truss_geometry.rb`:
- `load_truss(path)`
- `check_determinacy(joints, members, supports, loads=[])`
- `build_matrices(joints, members, supports, loads=[])`

Part of bridge truss vehicle load simulator task suite.
