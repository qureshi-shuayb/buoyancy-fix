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
const HaloclineDelta = 2.5
const HaloclineScale = 30.0
const ThermoclineScale = 120.0
const HullThermalExpansionCoeff = 2.0e-4
const SeawaterViscosity = 0.001
const SalinityDensityCoeff = 0.8
const BulkModulus = 2.2e9
const ThermalCouplingCoeff = 0.15

type Submarine struct {
	DryMass             float64
	Volume              float64
	Length              float64
	BallastCapacity     float64
	BallastLevel        float64
	HullCompressibility float64
	CrushDepth          float64
	DragCoefficient     float64
}
type Seawater struct{ Density float64 }

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
func (s Submarine) EffectiveMass() float64 { return s.DryMass + s.BallastLevel }
func (s Submarine) EffectiveDensity() (float64, error) {
	if err := s.Validate(); err != nil {
		return 0, err
	}
	if s.Volume <= 0 {
		return 0, errors.New("volume must be positive")
	}
	return s.EffectiveMass() / s.Volume, nil
}

func integralOneMinusExp(S, z float64) float64 {
	return z + S*math.Exp(-z/S) - S
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
	expH := math.Exp(-depth / HaloclineScale)
	expT := math.Exp(-depth / ThermoclineScale)
	expS1 := math.Exp(-depth / PycnoclineScale)
	sAnom := HaloclineDelta * (1.0 - expH)
	tAnom := 12.0 * (1.0 - expT)
	pyc1 := PycnoclineDelta * (1.0 - expS1)
	return sw.Density + DepthDensityGradient*depth + pyc1 + SalinityDensityCoeff*sAnom + ThermalCouplingCoeff*tAnom, nil
}

func (sw Seawater) DensityGradientAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	expS1 := math.Exp(-depth / PycnoclineScale)
	expH := math.Exp(-depth / HaloclineScale)
	expT := math.Exp(-depth / ThermoclineScale)
	dS := HaloclineDelta / HaloclineScale * expH
	dtAnom := 12.0 / ThermoclineScale * expT
	dp1 := PycnoclineDelta / PycnoclineScale * expS1
	return DepthDensityGradient + dp1 + SalinityDensityCoeff*dS + ThermalCouplingCoeff*dtAnom, nil
}

func (sw Seawater) PotentialDensityAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	rho, _ := sw.DensityAtDepth(depth)
	return rho - DepthDensityGradient*depth, nil
}
func (sw Seawater) PotentialTemperatureAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	T, _ := sw.TemperatureAtDepth(depth)
	P, err := sw.PressureAtDepth(depth, StandardGravity)
	if err != nil {
		return 0, err
	}
	x := P / BulkModulus * 1e-3
	return T * (1 - x), nil
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
	return 1449.2 + 4.6*T + 1.34*(S-35.0) + 0.016*depth, nil
}
func (sw Seawater) SoundSpeedGradientAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	dT, _ := sw.TemperatureGradientAtDepth(depth)
	dS, _ := sw.SalinityGradientAtDepth(depth)
	return 4.6*dT + 1.34*dS + 0.016, nil
}

func (sw Seawater) FindSOFARAxis(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth <= 0 {
		return 0, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return 0, errors.New("tolerance must be positive")
	}
	N := 500
	dz := maxDepth / float64(N)
	bestC := 1e99
	bestIdx := 0
	zs := make([]float64, N+1)
	for i := 0; i <= N; i++ {
		z := float64(i) * dz
		c, _ := sw.SoundSpeedAtDepth(z)
		zs[i] = z
		if c < bestC {
			bestC = c
			bestIdx = i
		}
	}
	lo := 0.0
	if bestIdx > 0 {
		lo = zs[bestIdx-1]
	}
	hi := maxDepth
	if bestIdx < N {
		hi = zs[bestIdx+1]
	}
	for iter := 0; iter < 50; iter++ {
		if hi-lo < tolerance {
			break
		}
		m1 := lo + (hi-lo)/3.0
		m2 := hi - (hi-lo)/3.0
		c1, _ := sw.SoundSpeedAtDepth(m1)
		c2, _ := sw.SoundSpeedAtDepth(m2)
		if c1 < c2 {
			hi = m2
		} else {
			lo = m1
		}
	}
	return (lo + hi) / 2.0, nil
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
	rho, _ := sw.DensityAtDepth(depth)
	grad, _ := sw.DensityGradientAtDepth(depth)
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
	z := depth
	integralPyc1 := PycnoclineDelta * integralOneMinusExp(PycnoclineScale, z)
	integralBeta := SalinityDensityCoeff * HaloclineDelta * integralOneMinusExp(HaloclineScale, z)
	integralGamma := ThermalCouplingCoeff * 12.0 * integralOneMinusExp(ThermoclineScale, z)
	total := sw.Density*z + 0.5*DepthDensityGradient*z*z + integralPyc1 + integralBeta + integralGamma
	return g * total, nil
}
func (sw Seawater) StericHeightAtDepth(depth float64, g float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	P, _ := sw.PressureAtDepth(depth, g)
	return (P/g - sw.Density*depth) / sw.Density, nil
}
func (sub Submarine) VolumeAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
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
	P, err := fluid.PressureAtDepth(depth, g)
	if err != nil {
		return 0, err
	}
	T, _ := fluid.TemperatureAtDepth(depth)
	dT := T - 15.0
	factor := 1.0 + HullThermalExpansionCoeff*dT
	if factor < 0.1 {
		factor = 0.1
	}
	vol := sub.Volume * math.Exp(-sub.HullCompressibility*P) * factor
	minV := MinimumVolumeFraction * sub.Volume
	if vol < minV {
		vol = minV
	}
	return vol, nil
}
func (sub Submarine) EffectiveDensityAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
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
	vol, err := sub.VolumeAtDepth(depth, fluid, g)
	if err != nil {
		return 0, err
	}
	if vol <= 0 {
		return 0, errors.New("volume must be positive")
	}
	return sub.EffectiveMass() / vol, nil
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
	if err := sub.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	return fluid.Density*sub.Volume - sub.DryMass, nil
}
func RequiredBallastForNeutralAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error) {
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
	rho, _ := fluid.DensityAtDepth(depth)
	vol, _ := sub.VolumeAtDepth(depth, fluid, g)
	return rho*vol - sub.DryMass, nil
}
func CheckSubmarineState(sub Submarine, fluid Seawater) (string, error) {
	if err := sub.Validate(); err != nil {
		return "", err
	}
	if err := fluid.Validate(); err != nil {
		return "", err
	}
	eff, err := sub.EffectiveDensity()
	if err != nil {
		return "", err
	}
	diff := eff - fluid.Density
	if math.Abs(diff) <= Tolerance {
		return "neutral", nil
	}
	if eff < fluid.Density {
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
	rho, _ := fluid.DensityAtDepth(depth)
	diff := eff - rho
	if math.Abs(diff) <= Tolerance {
		return "neutral", nil
	}
	if eff < rho {
		return "float", nil
	}
	return "sink", nil
}
func IsNeutralBuoyancyPossible(sub Submarine, fluid Seawater) (bool, error) {
	if err := sub.Validate(); err != nil {
		return false, err
	}
	if err := fluid.Validate(); err != nil {
		return false, err
	}
	req := fluid.Density*sub.Volume - sub.DryMass
	if req < 0 {
		req = 0
	}
	if req > sub.BallastCapacity {
		return false, nil
	}
	return true, nil
}
func IsNeutralBuoyancyPossibleAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (bool, error) {
	if err := sub.Validate(); err != nil {
		return false, err
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
	rho, _ := fluid.DensityAtDepth(depth)
	vol, _ := sub.VolumeAtDepth(depth, fluid, g)
	req := rho*vol - sub.DryMass
	if req < 0 {
		req = 0
	}
	if req > sub.BallastCapacity {
		return false, nil
	}
	return true, nil
}
GO
