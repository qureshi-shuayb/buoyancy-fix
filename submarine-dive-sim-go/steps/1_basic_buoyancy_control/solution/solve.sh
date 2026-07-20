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
const MidPycnoclineDelta = 7.0
const MidPycnoclineScale = 90.0
const HaloclineDelta = 2.5
const HaloclineScale = 30.0
const ThermoclineScale = 120.0
const HullThermalExpansionCoeff = 2.0e-4
const SeawaterViscosity = 0.001
const SalinityDensityCoeff = 0.8
const BulkModulus = 2.2e9

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

func (sw Seawater) SalinityAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	return 35.0 + HaloclineDelta*(1.0-math.Exp(-depth/HaloclineScale)), nil
}

func (sw Seawater) SalinityGradientAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	return HaloclineDelta / HaloclineScale * math.Exp(-depth/HaloclineScale), nil
}

func (sw Seawater) TemperatureAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	return 15.0 - 12.0*(1.0-math.Exp(-depth/ThermoclineScale)), nil
}

func (sw Seawater) TemperatureGradientAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	return -12.0 / ThermoclineScale * math.Exp(-depth/ThermoclineScale), nil
}

func (sw Seawater) DensityAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	// 5 exp terms: 3 pycnocline + halocline + thermocline
	pyc1 := PycnoclineDelta * (1.0 - math.Exp(-depth/PycnoclineScale))
	pyc2 := DeepPycnoclineDelta * (1.0 - math.Exp(-depth/DeepPycnoclineScale))
	pyc3 := MidPycnoclineDelta * (1.0 - math.Exp(-depth/MidPycnoclineScale))
	sal := HaloclineDelta * (1.0 - math.Exp(-depth/HaloclineScale))
	therm := 12.0 * (1.0 - math.Exp(-depth/ThermoclineScale)) // 15 - T
	// thermal density coeff gamma=0.15 fixed
	return sw.Density + DepthDensityGradient*depth + pyc1 + pyc2 + pyc3 + SalinityDensityCoeff*sal + 0.15*therm, nil
}

func (sw Seawater) DensityGradientAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	term1 := PycnoclineDelta / PycnoclineScale * math.Exp(-depth/PycnoclineScale)
	term2 := DeepPycnoclineDelta / DeepPycnoclineScale * math.Exp(-depth/DeepPycnoclineScale)
	term3 := MidPycnoclineDelta / MidPycnoclineScale * math.Exp(-depth/MidPycnoclineScale)
	termH := SalinityDensityCoeff * HaloclineDelta / HaloclineScale * math.Exp(-depth/HaloclineScale)
	termT := 0.15 * 12.0 / ThermoclineScale * math.Exp(-depth/ThermoclineScale)
	return DepthDensityGradient + term1 + term2 + term3 + termH + termT, nil
}

func (sw Seawater) DensitySecondDerivativeAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	t1 := -PycnoclineDelta / (PycnoclineScale * PycnoclineScale) * math.Exp(-depth/PycnoclineScale)
	t2 := -DeepPycnoclineDelta / (DeepPycnoclineScale * DeepPycnoclineScale) * math.Exp(-depth/DeepPycnoclineScale)
	t3 := -MidPycnoclineDelta / (MidPycnoclineScale * MidPycnoclineScale) * math.Exp(-depth/MidPycnoclineScale)
	tH := -SalinityDensityCoeff * HaloclineDelta / (HaloclineScale * HaloclineScale) * math.Exp(-depth/HaloclineScale)
	tT := -0.15 * 12.0 / (ThermoclineScale * ThermoclineScale) * math.Exp(-depth/ThermoclineScale)
	return t1 + t2 + t3 + tH + tT, nil
}

func (sw Seawater) SoundSpeedAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	T, _ := sw.TemperatureAtDepth(depth)
	S, _ := sw.SalinityAtDepth(depth)
	// UNESCO simplified: c=1449.2+4.6T -0.055T^2 +1.34*(S-35)+0.016z
	c := 1449.2 + 4.6*T - 0.055*T*T + 1.34*(S-35.0) + 0.016*depth
	return c, nil
}

func (sw Seawater) PotentialDensityAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	// rho_pot = rho without linear grad*z: rho0 + pycnoclines + beta*(S-35)+gamma*(15-T)
	pyc1 := PycnoclineDelta * (1.0 - math.Exp(-depth/PycnoclineScale))
	pyc2 := DeepPycnoclineDelta * (1.0 - math.Exp(-depth/DeepPycnoclineScale))
	pyc3 := MidPycnoclineDelta * (1.0 - math.Exp(-depth/MidPycnoclineScale))
	sal := HaloclineDelta * (1.0 - math.Exp(-depth/HaloclineScale))
	therm := 12.0 * (1.0 - math.Exp(-depth/ThermoclineScale))
	rhoPot := sw.Density + pyc1 + pyc2 + pyc3 + SalinityDensityCoeff*sal + 0.15*therm
	return rhoPot, nil
}

func (sw Seawater) PotentialTemperatureAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	T, _ := sw.TemperatureAtDepth(depth)
	// Authoritative: theta = T * (1 - P/BulkModulus*1e-3) using BulkModulus, P from PressureAtDepth
	P, err := sw.PressureAtDepth(depth, StandardGravity)
	if err != nil {
		return 0, err
	}
	theta := T * (1.0 - P/BulkModulus*1e-3)
	return theta, nil
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
	return g / rho * grad, nil
}

func (sw Seawater) TurnerAngleAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	dT, _ := sw.TemperatureGradientAtDepth(depth)
	dS, _ := sw.SalinityGradientAtDepth(depth)
	// gamma = 0.15, beta = SalinityDensityCoeff
	// Define Turner to stay within -90..90: Tu = atan2(gamma*dT + beta*dS, beta*dS - gamma*dT)*180/pi
	// dT negative, dS positive, so numerator small, denominator positive => -90..90
	num := 0.15*dT + SalinityDensityCoeff*dS
	den := SalinityDensityCoeff*dS - 0.15*dT
	angle := math.Atan2(num, den) * 180.0 / math.Pi
	return angle, nil
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
	exp1 := math.Exp(-depth / PycnoclineScale)
	exp2 := math.Exp(-depth / DeepPycnoclineScale)
	exp3 := math.Exp(-depth / MidPycnoclineScale)
	expH := math.Exp(-depth / HaloclineScale)
	expT := math.Exp(-depth / ThermoclineScale)
	// integral = rho0*z +0.5*grad*z^2 + D1*(z+S1*exp -S1)+...
	integral := sw.Density*depth + 0.5*DepthDensityGradient*depth*depth +
		PycnoclineDelta*(depth+PycnoclineScale*exp1-PycnoclineScale) +
		DeepPycnoclineDelta*(depth+DeepPycnoclineScale*exp2-DeepPycnoclineScale) +
		MidPycnoclineDelta*(depth+MidPycnoclineScale*exp3-MidPycnoclineScale) +
		SalinityDensityCoeff*HaloclineDelta*(depth+HaloclineScale*expH-HaloclineScale) +
		0.15*12.0*(depth+ThermoclineScale*expT-ThermoclineScale)
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
