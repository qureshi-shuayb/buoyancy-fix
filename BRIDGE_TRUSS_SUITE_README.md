# Bridge Truss Vehicle Load Suite — 6 Novel T-Bench Tasks

Structural mechanics domain new to ADO portfolio. No prior truss, bridge, buckling, virtual work, influence line, or vehicle envelope tasks exist in 228 instruction.md scanned across christouret, danielwen, ddakev, marinam, natemac, shuaybqureshi, high-novelty collections. Closest is spectral-mode-detector FFT SHM signal processing, unrelated.

## Tasks

1. **truss-geometry-validator-ruby** — Ruby 3.2, pure stdlib JSON. Parse truss JSON, validate duplicate IDs, coincident joints <1e-9, zero-length members, missing references, check determinacy m+r vs 2j, build adjacency sorted and dof_map. 5 test groups. Fills Ruby gap -5.12pp.

2. **truss-static-solver-go** — Go 1.22, pure stdlib. Method of joints Gaussian elimination partial pivot, no numpy equivalent. SolveReactions returns map[string]Reaction, SolveMemberForces returns map[string]float64 tension positive. 8 test groups covering triangle exact forces, duplicate, missing, zero length, unstable, indeterminate, reaction balance, sign convention. Fills Go gap -1.27pp.

3. **vehicle-load-envelope-php** — PHP 8.2 cli, pure stdlib. place_vehicle linear interpolation to panel points with AASHTO impact I=1+15/(L+38), envelope discretizes vehicle position step and solves truss each step tracking max tension >=0 and max compression <=0. 5 test groups. Fills PHP/Hack gap -1.25pp.

4. **virtual-work-deflection-rust** — Rust 1.78, pure stdlib no crates. member_elongations F*L/AE, virtual_forces unit load solve via gauss, deflection sum virtual*real*L/AE. 5 test groups in cargo test. Fills Rust gap -1.95pp.

5. **buckling-capacity-check-r** — R 4.3 base. slenderness KL/r, critical_load pi^2 EI/(KL)^2, safety_factors envelope compression vs Pcr with Inf for tension. 4 test groups. Fills R gap -2.2pp.

6. **truss-rating-optimizer-julia** — Julia 1.10 stdlib. influence_coefficient via unit load solve, rating_factor (capacity-dead)/live*0.9, optimize_rating binary search 0-5 tol 1e-3 tracking critical member. 4 test groups. Fills Julia/Fortran/MATLAB gap -1.52pp.

## Domain Model Shared

Truss JSON: joints [{id,x,y,support?}], members [{id,i,j,A,E,I?,capacity?,dead_force?}], supports [{joint_id,type pinned|roller|fixed}]. Planar pin-jointed, small deflection linear elastic, static determinacy m+r == 2j.

Vehicle: axle_weights list float, spacings list float length weights-1.

## Novelty & Beating Assessment

- Prior art grep across 228 instruction.md: zero hits for truss/pratt/warren/howe/buckling/influence/virtual work/method of joints except these 6 new files.
- Closest domain overlap spectral-mode-detector is FFT SHM, different physics.
- Contamination low: textbook formulas but specific JSON schema, function names, tolerances, test trusses original.
- Estimated initial pass rates: geometry 3-4/5, static 2-3/5, envelope 2/5, deflection 2/5, buckling 3/5, rating 1-2/5. Top 4 hardest are rating, deflection, envelope, static in that order.

## Verification Checklist per Task

- [ ] local codimango bench run -k5 oracle 5/5
- [ ] stub 0/5 fail_to_pass
- [ ] 3-4 frontier models pilot for difficulty spread
- [ ] review-task-tbench-v2 self-review passed
- [ ] README updated, canary GUID present, hidden test geometry variant added

## Files Changed

52 files added in initial commit, 17 changed in language rewrite commit, 3 fixed in task.toml commit. Total 6 task directories under shuaybqureshi-tbench/.
