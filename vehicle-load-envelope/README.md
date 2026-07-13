# Vehicle Load Envelope

Implement moving vehicle load envelope calculator for planar truss bridge in pure PHP.

## Description

Pure-PHP moving vehicle load envelope calculator for planar truss bridge at `/app/vehicle_envelope.php`. Distributes axle loads to panel points by linear interpolation with AASHTO impact factor I=1+15/(L+38), discretizes vehicle position across span, solves truss member forces via Gaussian elimination each step, tracks max tension and compression envelope per member. No external dependencies, PHP 8 stdlib only.

## Completion Rates

| Model | Pass Rate | Notes |
|-------|-----------|-------|
| avocado | TBD | target 1-4/5 after hardening |
| opus | TBD | target 1-4/5 |
| codex | TBD | target 1-4/5 |

Oracle validation: 3/3 expected after test sync to Pratt fixture and instruction expansion.

## Model Analysis

Current codimango signals show balanced pass rates 1/5 avocado 0/5 opus 4/5 codex after oracle fix, indicating task is solvable but not trivial. AI assessment flagged High cheat vector due to single-fixture hardcoded expected outputs in test harness. Hardening applied in this commit adds second independent truss topology fixture with distinct expected envelope values and adds invalid-input exception tests to satisfy spec requirement, reducing hardcode risk while maintaining oracle pass on reference solution.

## Anti-Cheating Analysis

Tests now run two independent envelope fixtures: 2-panel Pratt truss with single axle and 3-panel Pratt truss with two moving axles and distinct member topology requiring 11 members vs 5. Hardcoded return literals for first fixture will fail second fixture with 5% tolerance checks on B0 B1 B2 V1 V2 D0 D3. Invalid input tests verify exception raising on empty truss, invalid support type, and zero-length member, preventing silent failure acceptance. Test harness remains in-process via require for simplicity but dual fixture substantially raises cheat cost. Canary GUID updated to valid UUID v4 format to prevent training data leakage detection bypass. No external network access in Docker container built from php:8.2-cli.

## API

PHP functions matching instruction.md at `/app/vehicle_envelope.php`:

```php
function place_vehicle(float $position, array $axle_weights, array $spacings, float $panel_length, array $panel_x_positions): array
function envelope(array $truss, array $vehicle, float $step): array
```

- `place_vehicle` returns associative array mapping "P0","P1"... to vertical load negative downward Newtons after applying impact factor. Distribute each axle load to nearest two panel points by linear interpolation based on proximity along x. Front axle position measured from leftmost panel point, subsequent axles behind towards decreasing x by cumulative spacing. If axle outside panel range ignore.
- `envelope` discretizes vehicle front axle position from 0 to span inclusive step, computes joint loads via place_vehicle mapped to deck joint IDs in sorted order, solves truss member forces via Gaussian elimination, tracks per member max tension >=0 and max compression <=0. Returns associative array member_id => ['max_tension'=>float,'max_compression'=>float].

## Error Cases

Raise Exception on invalid inputs:
- empty truss or missing required keys
- duplicate joint id, duplicate member id, duplicate support at same joint
- missing joint reference in member support or load
- zero-length member
- unsupported support type not pinned or roller
- unstable or indeterminate topology
- singular matrix during solve
- vertical alignment causing zero moment arm

## Constraints

- PHP 8 stdlib only, no composer dependencies
- File at /app/vehicle_envelope.php
- Deterministic output, no randomness
- Outputs compared against reference within 1% relative tolerance
