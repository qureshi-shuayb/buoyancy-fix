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

type CylinderObject struct {
	Mass   float64
	Radius float64
	Height float64
}

type SphereObject struct {
	Mass   float64
	Radius float64
}

type BuoyancyReport struct {
	Index        int
	State        string
	Density      float64
	BuoyantForce float64
	WeightForce  float64
}

func isInvalidPositive(x float64) bool {
	return x <= 0 || math.IsNaN(x) || math.IsInf(x, 0)
}

func isFinitePositive(x float64) bool {
	return !isInvalidPositive(x)
}

// Object methods

func (o Object) Density() (float64, error) {
	if o.Mass <= 0 || math.IsNaN(o.Mass) || math.IsInf(o.Mass, 0) {
		return 0, errors.New("mass must be positive")
	}
	if o.Volume <= 0 || math.IsNaN(o.Volume) || math.IsInf(o.Volume, 0) {
		return 0, errors.New("volume must be positive")
	}
	// Must NOT check Height - inverse DRY trap
	d := o.Mass / o.Volume
	if math.IsInf(d, 0) || math.IsNaN(d) {
		return 0, errors.New("volume overflow resulting density invalid")
	}
	return d, nil
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

// CylinderObject methods

func (c CylinderObject) Validate() error {
	if c.Mass <= 0 || math.IsNaN(c.Mass) || math.IsInf(c.Mass, 0) {
		return errors.New("mass must be positive")
	}
	if c.Radius <= 0 || math.IsNaN(c.Radius) || math.IsInf(c.Radius, 0) {
		return errors.New("radius must be positive")
	}
	if c.Height <= 0 || math.IsNaN(c.Height) || math.IsInf(c.Height, 0) {
		return errors.New("height must be positive")
	}
	return nil
}

func (c CylinderObject) Volume() (float64, error) {
	// Must NOT validate Mass - inverse trap
	if c.Radius <= 0 || math.IsNaN(c.Radius) || math.IsInf(c.Radius, 0) {
		return 0, errors.New("radius must be positive")
	}
	if c.Height <= 0 || math.IsNaN(c.Height) || math.IsInf(c.Height, 0) {
		return 0, errors.New("height must be positive")
	}
	vol := math.Pi * c.Radius * c.Radius * c.Height
	if math.IsInf(vol, 0) || math.IsNaN(vol) {
		return 0, errors.New("radius and height cause volume overflow")
	}
	return vol, nil
}

func (c CylinderObject) Density() (float64, error) {
	if c.Mass <= 0 || math.IsNaN(c.Mass) || math.IsInf(c.Mass, 0) {
		return 0, errors.New("mass must be positive")
	}
	vol, err := c.Volume()
	if err != nil {
		return 0, err
	}
	d := c.Mass / vol
	if math.IsInf(d, 0) || math.IsNaN(d) {
		return 0, errors.New("mass and volume cause density overflow")
	}
	return d, nil
}

// SphereObject methods

func (s SphereObject) Validate() error {
	if s.Mass <= 0 || math.IsNaN(s.Mass) || math.IsInf(s.Mass, 0) {
		return errors.New("mass must be positive")
	}
	if s.Radius <= 0 || math.IsNaN(s.Radius) || math.IsInf(s.Radius, 0) {
		return errors.New("radius must be positive")
	}
	return nil
}

func (s SphereObject) Volume() (float64, error) {
	// Must NOT validate Mass
	if s.Radius <= 0 || math.IsNaN(s.Radius) || math.IsInf(s.Radius, 0) {
		return 0, errors.New("radius must be positive")
	}
	vol := 4.0 / 3.0 * math.Pi * s.Radius * s.Radius * s.Radius
	if math.IsInf(vol, 0) || math.IsNaN(vol) {
		return 0, errors.New("radius causes volume overflow")
	}
	return vol, nil
}

func (s SphereObject) Density() (float64, error) {
	if s.Mass <= 0 || math.IsNaN(s.Mass) || math.IsInf(s.Mass, 0) {
		return 0, errors.New("mass must be positive")
	}
	vol, err := s.Volume()
	if err != nil {
		return 0, err
	}
	d := s.Mass / vol
	if math.IsInf(d, 0) || math.IsNaN(d) {
		return 0, errors.New("mass and radius cause density overflow")
	}
	return d, nil
}

// Functions

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
	// overflow check
	prod := fluid.Density * volume
	if math.IsInf(prod, 0) || math.IsNaN(prod) {
		return 0, errors.New("density and volume cause overflow")
	}
	result := prod * g
	if math.IsInf(result, 0) || math.IsNaN(result) {
		return 0, errors.New("buoyant force overflow: volume and gravity too large")
	}
	return result, nil
}

func WeightForce(mass float64, g float64) (float64, error) {
	if mass <= 0 || math.IsNaN(mass) || math.IsInf(mass, 0) {
		return 0, errors.New("mass must be positive")
	}
	if g <= 0 || math.IsNaN(g) || math.IsInf(g, 0) {
		return 0, errors.New("gravity must be positive")
	}
	result := mass * g
	if math.IsInf(result, 0) || math.IsNaN(result) {
		return 0, errors.New("mass and gravity cause overflow")
	}
	return result, nil
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

func ApparentWeight(obj Object, fluid Fluid, g float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if g <= 0 || math.IsNaN(g) || math.IsInf(g, 0) {
		return 0, errors.New("gravity must be positive")
	}
	density, err := obj.Density()
	if err != nil {
		return 0, err
	}
	// Package-defined tolerance zeroing: must use Tolerance constant
	if math.Abs(density-fluid.Density) <= Tolerance {
		return 0, nil
	}
	// compute (Mass - rho*V)*g with overflow checks
	rhoV := fluid.Density * obj.Volume
	if math.IsInf(rhoV, 0) || math.IsNaN(rhoV) {
		return 0, errors.New("density and volume cause overflow")
	}
	diff := obj.Mass - rhoV
	if math.IsInf(diff, 0) || math.IsNaN(diff) {
		return 0, errors.New("mass and volume difference overflow")
	}
	result := diff * g
	if math.IsInf(result, 0) || math.IsNaN(result) {
		return 0, errors.New("gravity and mass difference cause overflow")
	}
	return result, nil
}

func RequiredBallastMass(obj Object, fluid Fluid) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	density, err := obj.Density()
	if err != nil {
		return 0, err
	}
	// Tolerance zeroing
	if math.Abs(density-fluid.Density) <= Tolerance {
		return 0, nil
	}
	targetMass := fluid.Density * obj.Volume
	if math.IsInf(targetMass, 0) || math.IsNaN(targetMass) {
		return 0, errors.New("density and volume cause overflow")
	}
	ballast := targetMass - obj.Mass
	if math.IsInf(ballast, 0) || math.IsNaN(ballast) {
		return 0, errors.New("mass and volume cause ballast overflow")
	}
	return ballast, nil
}

func BatchCheckBuoyancy(objs []Object, fluid Fluid, g float64) ([]BuoyancyReport, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if g <= 0 || math.IsNaN(g) || math.IsInf(g, 0) {
		return nil, errors.New("gravity must be positive")
	}
	if objs == nil {
		return make([]BuoyancyReport, 0), nil
	}
	if len(objs) == 0 {
		// return non-nil empty for empty slice as well
		return make([]BuoyancyReport, 0), nil
	}
	results := make([]BuoyancyReport, len(objs))
	for i, obj := range objs {
		if err := obj.Validate(); err != nil {
			results[i] = BuoyancyReport{Index: i, State: "invalid"}
			continue
		}
		density, err := obj.Density()
		if err != nil {
			results[i] = BuoyancyReport{Index: i, State: "invalid"}
			continue
		}
		buoyant, err := BuoyantForce(fluid, obj.Volume, g)
		if err != nil {
			results[i] = BuoyancyReport{Index: i, State: "invalid"}
			continue
		}
		weight, err := WeightForce(obj.Mass, g)
		if err != nil {
			results[i] = BuoyancyReport{Index: i, State: "invalid"}
			continue
		}
		state, err := CheckBuoyancyByDensity(density, fluid.Density)
		if err != nil {
			results[i] = BuoyancyReport{Index: i, State: "invalid"}
			continue
		}
		results[i] = BuoyancyReport{
			Index:        i,
			State:        state,
			Density:      density,
			BuoyantForce: buoyant,
			WeightForce:  weight,
		}
	}
	return results, nil
}
GO
