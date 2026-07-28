#!/bin/bash
set -euo pipefail
cat >> /app/submarine.go <<'GO'

func (sw Seawater) PotentialDensityAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	return sw.Density, nil
}
func (sw Seawater) PotentialTemperatureAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	return 15.0, nil
}
func (sw Seawater) SoundSpeedAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	return 1500, nil
}
func (sw Seawater) SoundSpeedGradientAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	return 0, nil
}
func (sw Seawater) FindSOFARAxis(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth <= 0 { return 0, errors.New("maxDepth must be positive") }
	if tolerance <= 0 { return 0, errors.New("tolerance must be positive") }
	return 0, nil
}
func (sw Seawater) BuoyancyFrequencySquared(depth float64, g float64) (float64, error) {
	if err := sw.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	return 0, nil
}
func (sw Seawater) PressureAtDepth(depth float64, g float64) (float64, error) {
	if err := sw.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	return g * sw.Density * depth, nil
}
func (sw Seawater) StericHeightAtDepth(depth float64, g float64) (float64, error) {
	if err := sw.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	return 0, nil
}
func (sub Submarine) VolumeAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
	if err := sub.Validate(); err != nil { return 0, err }
	if err := fluid.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	if depth > sub.CrushDepth { return 0, errors.New("crush depth exceeded") }
	P, _ := fluid.PressureAtDepth(depth, g)
	vol := sub.Volume * math.Exp(-sub.HullCompressibility*P)
	minV := MinimumVolumeFraction * sub.Volume
	if vol < minV { vol = minV }
	return vol, nil
}
func (sub Submarine) EffectiveDensityAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
	if err := sub.Validate(); err != nil { return 0, err }
	if err := fluid.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	vol, _ := sub.VolumeAtDepth(depth, fluid, g)
	return sub.EffectiveMass() / vol, nil
}
func BuoyantForceAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error) {
	if err := sub.Validate(); err != nil { return 0, err }
	if err := fluid.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	if depth > sub.CrushDepth { return 0, errors.New("crush depth exceeded") }
	rho, _ := fluid.DensityAtDepth(depth)
	vol, _ := sub.VolumeAtDepth(depth, fluid, g)
	return rho * vol * g, nil
}
func RequiredBallastForNeutralAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error) {
	if err := sub.Validate(); err != nil { return 0, err }
	if err := fluid.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	if depth > sub.CrushDepth { return 0, errors.New("crush depth exceeded") }
	rho, _ := fluid.DensityAtDepth(depth)
	vol, _ := sub.VolumeAtDepth(depth, fluid, g)
	return rho*vol - sub.DryMass, nil
}
func CheckSubmarineStateAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (string, error) {
	if err := sub.Validate(); err != nil { return "", err }
	if err := fluid.Validate(); err != nil { return "", err }
	if depth < 0 { return "", errors.New("depth must be non-negative") }
	if g <= 0 { return "", errors.New("gravity must be positive") }
	if depth > sub.CrushDepth { return "", errors.New("crush depth exceeded") }
	eff, _ := sub.EffectiveDensityAtDepth(depth, fluid, g)
	rho, _ := fluid.DensityAtDepth(depth)
	if math.Abs(eff-rho) <= Tolerance { return "neutral", nil }
	if eff < rho { return "float", nil }
	return "sink", nil
}
func IsNeutralBuoyancyPossibleAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (bool, error) {
	if err := sub.Validate(); err != nil { return false, err }
	if err := fluid.Validate(); err != nil { return false, err }
	if depth < 0 { return false, errors.New("depth must be non-negative") }
	if g <= 0 { return false, errors.New("gravity must be positive") }
	if depth > sub.CrushDepth { return false, errors.New("crush depth exceeded") }
	rho, _ := fluid.DensityAtDepth(depth)
	vol, _ := sub.VolumeAtDepth(depth, fluid, g)
	req := rho*vol - sub.DryMass
	if req < 0 { req = 0 }
	return req <= sub.BallastCapacity, nil
}
GO
