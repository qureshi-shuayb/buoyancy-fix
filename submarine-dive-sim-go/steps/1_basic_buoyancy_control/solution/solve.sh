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
const DepthDensityGradient = 0.02
const MinimumVolumeFraction = 0.1
const PycnoclineDelta = 10.0
const PycnoclineScale = 200.0
const DeepPycnoclineDelta = 4.5
const DeepPycnoclineScale = 45.0
const SeawaterViscosity = 0.001
const ThermoclineScale = 120.0
const HullThermalExpansionCoeff = 2.0e-4

type Submarine struct {
	DryMass            float64
	Volume             float64
	Length             float64
	BallastCapacity    float64
	BallastLevel       float64
	HullCompressibility float64
	CrushDepth         float64
	DragCoefficient    float64
}

type Seawater struct {
	Density float64
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
	if s.HullCompressibility < 0 {
		return errors.New("hull compressibility must be non-negative")
	}
	if s.CrushDepth <= 0 {
		return errors.New("crush depth must be positive")
	}
	if s.DragCoefficient < 0 {
		return errors.New("drag coefficient must be non-negative")
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

func (sw Seawater) DensityAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	// rho(z)= rho0 + grad*z + D1*(1-exp(-z/S1)) + D2*(1-exp(-z/S2))
	pyc1 := PycnoclineDelta * (1.0 - math.Exp(-depth/PycnoclineScale))
	pyc2 := DeepPycnoclineDelta * (1.0 - math.Exp(-depth/DeepPycnoclineScale))
	return sw.Density + DepthDensityGradient*depth + pyc1 + pyc2, nil
}

func (sw Seawater) DensityGradientAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	// drho/dz = grad + D1/S1*exp(-z/S1) + D2/S2*exp(-z/S2)
	term1 := PycnoclineDelta / PycnoclineScale * math.Exp(-depth/PycnoclineScale)
	term2 := DeepPycnoclineDelta / DeepPycnoclineScale * math.Exp(-depth/DeepPycnoclineScale)
	return DepthDensityGradient + term1 + term2, nil
}

func (sw Seawater) TemperatureAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	// T(z)=15 -12*(1-exp(-z/ThermScale))
	return 15.0 - 12.0*(1.0-math.Exp(-depth/ThermoclineScale)), nil
}

func (sw Seawater) BuoyancyFrequencySquared(depth float64, g float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	rho, err := sw.DensityAtDepth(depth)
	if err != nil {
		return 0, err
	}
	grad, err := sw.DensityGradientAtDepth(depth)
	if err != nil {
		return 0, err
	}
	// N^2 = g/rho * drho/dz
	return g / rho * grad, nil
}

func (sw Seawater) PressureAtDepth(depth float64, g float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	// integral rho dz = rho0*z +0.5*grad*z^2 + D1*(z+S1*exp(-z/S1)-S1) + D2*(z+S2*exp(-z/S2)-S2)
	exp1 := math.Exp(-depth / PycnoclineScale)
	exp2 := math.Exp(-depth / DeepPycnoclineScale)
	integral := sw.Density*depth + 0.5*DepthDensityGradient*depth*depth + PycnoclineDelta*(depth+PycnoclineScale*exp1-PycnoclineScale) + DeepPycnoclineDelta*(depth+DeepPycnoclineScale*exp2-DeepPycnoclineScale)
	return g * integral, nil
}

func (s Submarine) VolumeAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
	if err := s.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	if depth > s.CrushDepth {
		return 0, errors.New("crush depth exceeded")
	}
	pressure, err := fluid.PressureAtDepth(depth, g)
	if err != nil {
		return 0, err
	}
	temp, err := fluid.TemperatureAtDepth(depth)
	if err != nil {
		return 0, err
	}
	factorExp := 1.0
	if s.HullCompressibility != 0 {
		factorExp = math.Exp(-s.HullCompressibility * pressure)
	}
	factorThermal := 1.0 + HullThermalExpansionCoeff*(temp-15.0)
	// factorThermal may be slightly <1 due to cooling, but >0 for our alpha
	if factorThermal < 0.1 {
		factorThermal = 0.1
	}
	vol := s.Volume * factorExp * factorThermal
	minVol := s.Volume * MinimumVolumeFraction
	if vol < minVol {
		vol = minVol
	}
	if vol <= 0 {
		vol = minVol
	}
	_ = math.Abs(vol)
	return vol, nil
}

func (s Submarine) EffectiveDensityAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
	if err := s.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	vol, err := s.VolumeAtDepth(depth, fluid, g)
	if err != nil {
		return 0, err
	}
	if vol <= 0 {
		return 0, errors.New("volume must be positive")
	}
	return s.EffectiveMass() / vol, nil
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

func BuoyantForceAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error) {
	if err := sub.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	if depth > sub.CrushDepth {
		return 0, errors.New("crush depth exceeded")
	}
	rho, err := fluid.DensityAtDepth(depth)
	if err != nil {
		return 0, err
	}
	vol, err := sub.VolumeAtDepth(depth, fluid, g)
	if err != nil {
		return 0, err
	}
	return rho * vol * g, nil
}

func RequiredBallastForNeutral(sub Submarine, fluid Seawater) (float64, error) {
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
	if sub.HullCompressibility < 0 {
		return 0, errors.New("hull compressibility must be non-negative")
	}
	if sub.CrushDepth <= 0 {
		return 0, errors.New("crush depth must be positive")
	}
	if sub.DragCoefficient < 0 {
		return 0, errors.New("drag coefficient must be non-negative")
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	required := fluid.Density*sub.Volume - sub.DryMass
	return required, nil
}

func RequiredBallastForNeutralAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error) {
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
	if sub.HullCompressibility < 0 {
		return 0, errors.New("hull compressibility must be non-negative")
	}
	if sub.CrushDepth <= 0 {
		return 0, errors.New("crush depth must be positive")
	}
	if sub.DragCoefficient < 0 {
		return 0, errors.New("drag coefficient must be non-negative")
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	if depth > sub.CrushDepth {
		return 0, errors.New("crush depth exceeded")
	}
	rho, err := fluid.DensityAtDepth(depth)
	if err != nil {
		return 0, err
	}
	vol, err := sub.VolumeAtDepth(depth, fluid, g)
	if err != nil {
		return 0, err
	}
	required := rho*vol - sub.DryMass
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

func CheckSubmarineStateAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (string, error) {
	if err := sub.Validate(); err != nil {
		return "", err
	}
	if err := fluid.Validate(); err != nil {
		return "", err
	}
	if depth < 0 {
		return "", errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return "", errors.New("gravity must be positive")
	}
	if depth > sub.CrushDepth {
		return "", errors.New("crush depth exceeded")
	}
	eff, err := sub.EffectiveDensityAtDepth(depth, fluid, g)
	if err != nil {
		return "", err
	}
	rho, err := fluid.DensityAtDepth(depth)
	if err != nil {
		return "", err
	}
	diff := eff - rho
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
	if sub.HullCompressibility < 0 {
		return false, errors.New("hull compressibility must be non-negative")
	}
	if sub.CrushDepth <= 0 {
		return false, errors.New("crush depth must be positive")
	}
	if sub.DragCoefficient < 0 {
		return false, errors.New("drag coefficient must be non-negative")
	}
	if err := fluid.Validate(); err != nil {
		return false, err
	}
	required, _ := RequiredBallastForNeutral(sub, fluid)
	return required >= 0 && required <= sub.BallastCapacity, nil
}

func IsNeutralBuoyancyPossibleAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (bool, error) {
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
	if sub.HullCompressibility < 0 {
		return false, errors.New("hull compressibility must be non-negative")
	}
	if sub.CrushDepth <= 0 {
		return false, errors.New("crush depth must be positive")
	}
	if sub.DragCoefficient < 0 {
		return false, errors.New("drag coefficient must be non-negative")
	}
	if err := fluid.Validate(); err != nil {
		return false, err
	}
	if depth < 0 {
		return false, errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return false, errors.New("gravity must be positive")
	}
	if depth > sub.CrushDepth {
		return false, errors.New("crush depth exceeded")
	}
	required, err := RequiredBallastForNeutralAtDepth(sub, fluid, depth, g)
	if err != nil {
		return false, err
	}
	return required >= 0 && required <= sub.BallastCapacity, nil
}
GO
