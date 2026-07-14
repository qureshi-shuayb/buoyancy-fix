# Truss Geometry Validator

Implement pure-Ruby space truss finite element solver at `/app/truss_geometry.rb`. Module must expose exactly three methods in module TrussGeometry.

## Domain Model

Truss JSON schema with joints array each hash with id string unique, x float, y float, z float, optional support nil or "pinned" "roller" "fixed". Members array each hash id string unique, i string start joint id, j string end joint id, A float >0, E float >0. Supports array separate for API each hash joint_id string type string optional direction X Y Z default Z. Loads array optional each hash joint_id string fx float fy float fz float default 0.

Space pin-jointed truss static determinacy condition m + r == 3*j where m members, r total reaction components, j joints. m+r <3j unstable, > indeterminate. Each joint has three translational degrees of freedom in 3D. Kinematic mechanism is detected via equilibrium matrix rank deficiency even when counts match: build equilibrium matrix B size 3j rows by m+r columns, compute rank with Gaussian elimination tolerance 1e-9, if rank < 3j then mechanism. Even if counts pass and rank passes, global stiffness matrix K may be singular indicating unstable_singular mechanism under load.

## Required API in /app/truss_geometry.rb

```ruby
module TrussGeometry
  def self.load_truss(path) # returns Hash with "joints" and "members" arrays, raises RuntimeError on invalid
  def self.check_determinacy(joints, members, supports, loads=[]) # returns [bool, String]
  def self.build_matrices(joints, members, supports, loads=[]) # returns Hash
end
```

load_truss reads JSON file returns Hash with exactly keys "joints" and "members" preserving order. Raise RuntimeError on missing file invalid JSON missing required keys duplicate joint or member ids non-numeric coordinates or missing member endpoint reference or A<=0 or E<=0.

check_determinacy returns two-element Array [is_ok Boolean, message String]. Validation order messages must match exactly:
- duplicate joint id => [false, "duplicate_joint_id"]
- duplicate member id => [false, "duplicate_member_id"]
- member references joint id not in joints list => [false, "missing_joint_reference"]
- supports reference joint not in joints => [false, "missing_joint_reference"]
- loads reference joint not in joints => [false, "missing_joint_reference"]
- any two joints coincident within 1e-9 Euclidean distance in 3D => [false, "coincident_joints"]
- any member zero length within 1e-9 in 3D => [false, "zero_length_member"]
- unsupported support type treated as 0 reactions; if after counting m+r < 3*j => [false, "unstable"]; elsif m+r > 3*j => [false, "indeterminate"]; elsif rank deficiency mechanism => [false, "mechanism"]; elsif stiffness singular => [false, "unstable_singular"]; else [true, "determinate"]

Supports format array of hashes {"joint_id"=>"A","type"=>"pinned"} or {"joint_id"=>"B","type"=>"roller","direction"=>"X"}. Pinned 3 reactions along global X Y Z ignoring direction field, roller 1 reaction along specified axis default Z if direction missing or invalid, fixed 6 reactions along X Y Z X Y Z in that order repeating unit vectors to preserve count ignoring direction, others 0. Reaction directions define equilibrium matrix columns and stiffness boundary conditions. Direction must be one of "X","Y","Z" case-insensitive, default Z.

Loads format array of hashes {"joint_id"=>"A","fx"=>0.0,"fy"=>0.0,"fz"=>-1000.0}. Missing fx fy fz default 0. Loads are applied at joints in global coordinates.

Equilibrium matrix B algorithm: rows = 3*j ordered by joints input order each joint contributes ux uy uz rows at 3*idx,3*idx+1,3*idx+2. Columns 0..m-1 are members, then r support reaction columns in supports input order expanding per type. For member k connecting i to j compute dx = xj-xi, dy = yj-yi, dz = zj-zi, L = sqrt(dx*dx+dy*dy+dz*dz), cx=dx/L cy=dy/L cz=dz/L. Set B[3*idx_i][k]=+cx, B[3*idx_i+1][k]=+cy, B[3*idx_i+2][k]=+cz, B[3*idx_j][k]=-cx, B[3*idx_j+1][k]=-cy, B[3*idx_j+2][k]=-cz. For support reaction column s at joint jid with direction vector v in { [1,0,0],[0,1,0],[0,0,1] } per type order above, set B[3*idx][s]=v0, B[3*idx+1][s]=v1, B[3*idx+2][s]=v2, all other rows 0. Compute rank via Gaussian elimination with partial pivot and tolerance 1e-9 absolute pivot threshold. If rank < 3*j return mechanism.

Stiffness matrix K algorithm: size 3j x 3j initialize zeros. For each member compute EA/L, direction cosines cx cy cz as above, form 6x6 element stiffness Ke = EA/L * [[c*c^T, -c*c^T],[-c*c^T, c*c^T]] where c*c^T is 3x3 outer product. Assemble into global K at dof indices from dof_map: for joint i triplet [3*ii,3*ii+1,3*ii+2] and joint j triplet similarly, add Ke blocks to K at corresponding rows cols. After assembly K is symmetric.

Boundary condensation: determine restrained DOF indices from supports expanding per type and direction as for B (pinned 0,1,2 at joint; roller single axis per direction default Z => 2 for Z, 0 for X,1 for Y; fixed 0,1,2). Free DOFs are sorted ascending complement. Extract Kff submatrix size nf x nf. If nf==0 return unstable_singular.

LDLT Cholesky algorithm with partial pivoting for symmetric Kff: for k 0..nf-1 find pivot row p >=k maximizing abs(A[p][k]), swap rows and cols symmetrically maintaining permutation vector, record pivot. Compute D_k = A_kk - sum_{s<k} L_ks^2 * D_s. If abs(D_k) < 1e-12 return unstable_singular. For i>k compute L_ik = (A_ik - sum_{s<k} L_is*D_s*L_ks)/D_k. After factorization compute condition estimate as max abs D / min abs D, if >1e12 return unstable_singular, else proceed. Solve Ly = Pf via forward substitution, Dz=y via diagonal solve, L^T u = z via backward substitution to get u_free. Expand to full u size 3j with zeros at restrained DOFs preserving original order.

Reactions: compute R_full = K * u - P where P is load vector assembled from loads array at free and restrained DOFs (fx fy fz per joint). For restrained DOFs extract reaction values; for free DOFs reaction should be near zero. Return per joint [rx,ry,rz] summing contributions from restrained DOFs only, zero otherwise, rounded to 6 decimals.

Strain energy: U = 0.5 * u^T * K * u rounded to 6 decimals.

CSR output: K_csr row_ptr length 3j+1 where row_ptr[0]=0 and row_ptr[i+1]=row_ptr[i]+ count of non-zero entries in row i of full K with absolute value >1e-12. col_ind array of column indices sorted ascending per row where K[i][j] abs>1e-12. values array corresponding K[i][j] rounded to 6 decimals. K_nnz = length of values.

build_matrices returns Hash with keys "num_joints" Integer, "num_members" Integer, "num_reactions" Integer, "dof" Integer 3*j, "adjacency" Hash mapping joint id to sorted Array of neighbor joint ids, "dof_map" Hash mapping joint id to Array [ux_index, uy_index, uz_index] 0-based based on joints order, "equilibrium_rows" Integer 3*j, "equilibrium_cols" Integer m+r, "rank" Integer, "is_mechanism" Boolean rank<3*j, "K_rows" Integer 3*j, "K_cols" Integer 3*j, "K_nnz" Integer, "K_csr" Hash with row_ptr col_ind values, "u" Array length 3j float rounded 6 decimals, "reactions" Hash mapping joint_id to Array [rx,ry,rz] rounded 6 decimals, "strain_energy" Float rounded 6 decimals, "condition_estimate" Float rounded 3 decimals or "inf". Raise RuntimeError on same invalid conditions as check_determinacy except unstable indeterminate mechanism unstable_singular allowed as return values not exceptions.

## Constraints

Ruby 3 stdlib only JSON required. File at /app/truss_geometry.rb. Deterministic pure functions no randomness network.

## Granting

Exact string messages required. Adjacency lists sorted. Dof_map exact integer mapping. CSR row_ptr col_ind sorted row-major. Values rounded to 6 decimals, strain_energy 6 decimals, condition_estimate 3 decimals or "inf", reactions 6 decimals, u 6 decimals. All test groups must pass.
