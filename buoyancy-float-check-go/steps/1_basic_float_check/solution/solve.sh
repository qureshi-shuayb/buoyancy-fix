#!/bin/bash
set -euo pipefail
rm -f /app/*_test.go 2>/dev/null || true

cat > /app/buoyancy.go <<'GO'

package buoyancy

import (
	"errors"
	"math"
)

const Tolerance = 1e-9
const StandardGravity = 9.81

type Object struct {
	Mass   float64
	Volume float64
	Height float64
}

type Fluid struct {
	Density float64
}

func isInvalidPositive(x float64) bool {
	return x <= 0 || math.IsNaN(x) || math.IsInf(x, 0)
}

func (o Object) Density() (float64, error) {
	if o.Mass <= 0 || math.IsNaN(o.Mass) || math.IsInf(o.Mass, 0) {
		return 0, errors.New("mass must be positive")
	}
	if o.Volume <= 0 || math.IsNaN(o.Volume) || math.IsInf(o.Volume, 0) {
		return 0, errors.New("volume must be positive")
	}
	return o.Mass / o.Volume, nil
}

func (o Object) Validate() error {
	if o.Mass <= 0 || math.IsNaN(o.Mass) || math.IsInf(o.Mass, 0) {
		return errors.New("mass must be positive")
	}
	if o.Volume <= 0 || math.IsNaN(o.Volume) || math.IsInf(o.Volume, 0) {
		return errors.New("volume must be positive")
	}
	if o.Height <= 0 || math.IsNaN(o.Height) || math.IsInf(o.Height, 0) {
		return errors.New("height must be positive")
	}
	return nil
}

func (f Fluid) Validate() error {
	if f.Density <= 0 || math.IsNaN(f.Density) || math.IsInf(f.Density, 0) {
		return errors.New("fluid density must be positive")
	}
	return nil
}

func BuoyantForce(fluid Fluid, volume float64, g float64) (float64, error) {
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if volume <= 0 || math.IsNaN(volume) || math.IsInf(volume, 0) {
		return 0, errors.New("volume must be positive")
	}
	if g <= 0 || math.IsNaN(g) || math.IsInf(g, 0) {
		return 0, errors.New("gravity must be positive")
	}
	return fluid.Density * volume * g, nil
}

func WeightForce(mass float64, g float64) (float64, error) {
	if mass <= 0 || math.IsNaN(mass) || math.IsInf(mass, 0) {
		return 0, errors.New("mass must be positive")
	}
	if g <= 0 || math.IsNaN(g) || math.IsInf(g, 0) {
		return 0, errors.New("gravity must be positive")
	}
	return mass * g, nil
}

func CheckBuoyancyByDensity(objDensity, fluidDensity float64) (string, error) {
	if objDensity <= 0 || math.IsNaN(objDensity) || math.IsInf(objDensity, 0) {
		return "", errors.New("object density must be positive")
	}
	if fluidDensity <= 0 || math.IsNaN(fluidDensity) || math.IsInf(fluidDensity, 0) {
		return "", errors.New("fluid density must be positive")
	}

	diff := objDensity - fluidDensity
	if math.Abs(diff) <= Tolerance {
		return "neutral", nil
	}
	if diff < 0 {
		return "float", nil
	}
	return "sink", nil
}

func CheckBuoyancy(obj Object, fluid Fluid) (string, error) {
	if err := obj.Validate(); err != nil {
		return "", err
	}
	if err := fluid.Validate(); err != nil {
		return "", err
	}

	density, err := obj.Density()
	if err != nil {
		return "", err
	}
	return CheckBuoyancyByDensity(density, fluid.Density)
}

GO
