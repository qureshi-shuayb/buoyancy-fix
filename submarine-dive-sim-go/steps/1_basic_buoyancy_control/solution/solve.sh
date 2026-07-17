#!/bin/bash
set -euo pipefail

cat > /app/submarine.go <<'GO'
package submarine

import (
	"errors"
	"math"
)

const Tolerance = 1e-9
const StandardGravity = 9.81
const StandardSeawaterDensity = 1025.0

type Submarine struct {
	DryMass         float64 // kg, >0 dry mass without ballast water
	Volume          float64 // m^3, >0 total hull displacement volume
	Length          float64 // m, >0 overall length
	BallastCapacity float64 // kg, >0 max ballast water mass
	BallastLevel    float64 // kg, >=0 <=Capacity current ballast water
}

type Seawater struct {
	Density float64 // kg/m^3, >0 e.g. 1025 for seawater
}

func (s Submarine) Validate() error {
	if s.DryMass <= 0 {
		return errors.New("dry mass must be positive")
	}
	if s.Volume <= 0 {
		return errors.New("volume must be positive")
	}
	if s.Length <= 0 {
		return errors.New("length must be positive")
	}
	if s.BallastCapacity <= 0 {
		return errors.New("ballast capacity must be positive")
	}
	if s.BallastLevel < 0 {
		return errors.New("ballast level must be non-negative")
	}
	if s.BallastLevel > s.BallastCapacity+1e-12 {
		return errors.New("ballast level exceeds capacity")
	}
	return nil
}

func (sw Seawater) Validate() error {
	if sw.Density <= 0 {
		return errors.New("seawater density must be positive")
	}
	return nil
}

func (s Submarine) EffectiveMass() float64 {
	return s.DryMass + s.BallastLevel
}

func (s Submarine) EffectiveDensity() (float64, error) {
	if err := s.Validate(); err != nil {
		return 0, err
	}
	if s.Volume <= 0 {
		return 0, errors.New("volume must be positive")
	}
	return s.EffectiveMass() / s.Volume, nil
}

func BuoyantForce(fluid Seawater, sub Submarine, g float64) (float64, error) {
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if err := sub.Validate(); err != nil {
		return 0, err
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	return fluid.Density * sub.Volume * g, nil
}

func WeightForce(sub Submarine, g float64) (float64, error) {
	if err := sub.Validate(); err != nil {
		return 0, err
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	return sub.EffectiveMass() * g, nil
}

func RequiredBallastForNeutral(sub Submarine, fluid Seawater) (float64, error) {
	// Validate only dry aspects and fluid, not ballast level itself
	if sub.DryMass <= 0 {
		return 0, errors.New("dry mass must be positive")
	}
	if sub.Volume <= 0 {
		return 0, errors.New("volume must be positive")
	}
	if sub.Length <= 0 {
		return 0, errors.New("length must be positive")
	}
	if sub.BallastCapacity <= 0 {
		return 0, errors.New("ballast capacity must be positive")
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	required := fluid.Density*sub.Volume - sub.DryMass
	return required, nil
}

func CheckSubmarineState(sub Submarine, fluid Seawater) (string, error) {
	if err := sub.Validate(); err != nil {
		return "", err
	}
	if err := fluid.Validate(); err != nil {
		return "", err
	}
	effDensity, err := sub.EffectiveDensity()
	if err != nil {
		return "", err
	}
	diff := effDensity - fluid.Density
	if math.Abs(diff) <= Tolerance {
		return "neutral", nil
	}
	if diff < 0 {
		return "float", nil
	}
	return "sink", nil
}

func IsNeutralBuoyancyPossible(sub Submarine, fluid Seawater) (bool, error) {
	if sub.DryMass <= 0 {
		return false, errors.New("dry mass must be positive")
	}
	if sub.Volume <= 0 {
		return false, errors.New("volume must be positive")
	}
	if sub.Length <= 0 {
		return false, errors.New("length must be positive")
	}
	if sub.BallastCapacity <= 0 {
		return false, errors.New("ballast capacity must be positive")
	}
	if err := fluid.Validate(); err != nil {
		return false, err
	}
	required, _ := RequiredBallastForNeutral(sub, fluid)
	return required >= 0 && required <= sub.BallastCapacity, nil
}
GO
