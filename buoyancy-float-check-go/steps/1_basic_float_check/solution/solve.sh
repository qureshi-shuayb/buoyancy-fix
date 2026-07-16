#!/bin/bash
set -euo pipefail

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

func (o Object) Density() (float64, error) {
	if o.Mass <= 0 {
		return 0, errors.New("mass must be positive")
	}
	if o.Volume <= 0 {
		return 0, errors.New("volume must be positive")
	}
	return o.Mass / o.Volume, nil
}

func (o Object) Validate() error {
	if o.Mass <= 0 {
		return errors.New("mass must be positive")
	}
	if o.Volume <= 0 {
		return errors.New("volume must be positive")
	}
	if o.Height <= 0 {
		return errors.New("height must be positive")
	}
	return nil
}

func (f Fluid) Validate() error {
	if f.Density <= 0 {
		return errors.New("fluid density must be positive")
	}
	return nil
}

func BuoyantForce(fluid Fluid, volume float64, g float64) (float64, error) {
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if volume <= 0 {
		return 0, errors.New("volume must be positive")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	return fluid.Density * volume * g, nil
}

func WeightForce(mass float64, g float64) (float64, error) {
	if mass <= 0 {
		return 0, errors.New("mass must be positive")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	return mass * g, nil
}

func CheckBuoyancyByDensity(objDensity, fluidDensity float64) (string, error) {
	if objDensity <= 0 {
		return "", errors.New("object density must be positive")
	}
	if fluidDensity <= 0 {
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
