# Vehicle Load Envelope

Implement pure-PHP moving vehicle load envelope calculator at `/app/vehicle_envelope.php`.

## Domain

Truss dict with joints members supports as previous tasks. Vehicle dict with axle_weights array float and spacings array float length weights-1. Bridge deck panel points are joints with minimal y sorted by x.

## API in /app/vehicle_envelope.php

```php
function place_vehicle(float $position, array $axle_weights, array $spacings, float $panel_length, array $panel_x_positions): array
function envelope(array $truss, array $vehicle, float $step): array
```

place_vehicle returns associative array mapping "P0","P1"... to vertical load negative downward Newtons after applying impact factor I = 1 + 15/(L+38) where L is span length max-min panel x. Distribute each axle load to nearest two panel points by linear interpolation. Ignore axles outside panel range.

envelope takes truss associative array with keys joints members supports, vehicle associative array, step float meters. Discretize vehicle front axle position from 0 to span inclusive step. At each position compute joint loads via place_vehicle mapped to actual deck joint IDs, solve truss member forces via Gaussian elimination same method as static solver task, track per member max tension >=0 and max compression <=0. Return associative array member_id => ['max_tension'=>float,'max_compression'=>float].

Raise Exception on invalid inputs.

## Constraints

PHP 8 stdlib only. File at /app/vehicle_envelope.php. Deterministic.

## Grading

Outputs compared against reference within 0.5% relative tolerance.
