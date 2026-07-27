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
const CabbelingCoeff = 0.06
const HullThermalExpansionQuadCoeff = 1.2e-6
const SoundSpeedPressureQuadCoeff = 1.2e-5
const ThermobaricCoeff = 0.5
const ThermalCouplingCoeff = 0.15
const GammaDepthFactor = 0.0001
const TAnomQuadCoeff = 0.002
const SAnomQuadCoeff = 0.01
const SecondOrderCabbelingCoeff = 0.015
const TripleCabbelingCoeff = 0.004
const ThermostericAnomalyCoeff = 0.0008
const HalostericAnomalyCoeff = 0.0003
const AdiabaticLapseRate = 0.0002
const VorticityMixingCoeff = 0.00005
const DoubleDiffusiveMixingScale = 18.0
const PressureNonLinearCoeff = 1.5e-6

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
func integralProductOneMinusExp(scales []float64, z float64) float64 {
	n := len(scales)
	total := 0.0
	for mask := 0; mask < (1 << n); mask++ {
		bits := 0
		inv := 0.0
		for i := 0; i < n; i++ {
			if (mask>>i)&1 == 1 {
				bits++
				inv += 1.0 / scales[i]
			}
		}
		sign := 1.0
		if bits%2 == 1 {
			sign = -1.0
		}
		if inv == 0 {
			total += sign * z
		} else {
			sc := 1.0 / inv
			total += sign * sc * (1.0 - math.Exp(-z/sc))
		}
	}
	return total
}
func integralZOneMinusExp(S, z float64) float64 {
	exp := math.Exp(-z / S)
	return 0.5*z*z + S*z*exp + S*S*exp - S*S
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
	expS2 := math.Exp(-depth / DeepPycnoclineScale)
	expS3 := math.Exp(-depth / MidPycnoclineScale)
	expDm := math.Exp(-depth / DoubleDiffusiveMixingScale)
	sAnom := HaloclineDelta * (1.0 - expH)
	tAnom := 12.0 * (1.0 - expT)
	pyc1 := PycnoclineDelta * (1.0 - expS1)
	pyc2 := DeepPycnoclineDelta * (1.0 - expS2)
	pyc3 := MidPycnoclineDelta * (1.0 - expS3)
	cab1 := CabbelingCoeff * sAnom * tAnom
	cab2 := CabbelingCoeff * pyc3 * sAnom
	cab3 := CabbelingCoeff * pyc1 * sAnom
	cab4 := CabbelingCoeff * pyc2 * tAnom
	quadT := TAnomQuadCoeff * tAnom * tAnom
	quadS := SAnomQuadCoeff * sAnom * sAnom
	gammaTerm := ThermalCouplingCoeff * tAnom * (1.0 + GammaDepthFactor*depth)
	s2t := SecondOrderCabbelingCoeff * sAnom * sAnom * tAnom
	st2 := SecondOrderCabbelingCoeff * sAnom * tAnom * tAnom
	tri1 := TripleCabbelingCoeff * sAnom * tAnom * pyc1
	tri2 := TripleCabbelingCoeff * sAnom * tAnom * pyc2
	thermoDepth := ThermostericAnomalyCoeff * 0.01 * tAnom * depth
	haloDepth := HalostericAnomalyCoeff * 0.01 * sAnom * depth
	vort := VorticityMixingCoeff * depth * (1.0 - expDm)
	return sw.Density + DepthDensityGradient*depth + pyc1 + pyc2 + pyc3 + SalinityDensityCoeff*sAnom + gammaTerm + cab1 + cab2 + cab3 + cab4 + quadT + quadS + s2t + st2 + tri1 + tri2 + thermoDepth + haloDepth + vort, nil
}

func (sw Seawater) DensityGradientAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	expS1 := math.Exp(-depth / PycnoclineScale)
	expS2 := math.Exp(-depth / DeepPycnoclineScale)
	expS3 := math.Exp(-depth / MidPycnoclineScale)
	expH := math.Exp(-depth / HaloclineScale)
	expT := math.Exp(-depth / ThermoclineScale)
	expDm := math.Exp(-depth / DoubleDiffusiveMixingScale)
	sAnom := HaloclineDelta * (1 - expH)
	tAnom := 12.0 * (1 - expT)
	pyc1 := PycnoclineDelta * (1 - expS1)
	pyc2 := DeepPycnoclineDelta * (1 - expS2)
	pyc3 := MidPycnoclineDelta * (1 - expS3)
	dS := HaloclineDelta / HaloclineScale * expH
	dtAnom := 12.0 / ThermoclineScale * expT
	dp1 := PycnoclineDelta / PycnoclineScale * expS1
	dp2 := DeepPycnoclineDelta / DeepPycnoclineScale * expS2
	dp3 := MidPycnoclineDelta / MidPycnoclineScale * expS3
	df := dtAnom*(1.0+GammaDepthFactor*depth) + tAnom*GammaDepthFactor
	termCab1 := CabbelingCoeff * (dS*tAnom + sAnom*dtAnom)
	termCab2 := CabbelingCoeff * (dp3*sAnom + pyc3*dS)
	termCab3 := CabbelingCoeff * (dp1*sAnom + pyc1*dS)
	termCab4 := CabbelingCoeff * (dp2*tAnom + pyc2*dtAnom)
	termQuadT := TAnomQuadCoeff * 2.0 * tAnom * dtAnom
	termQuadS := SAnomQuadCoeff * 2.0 * sAnom * dS
	ds2t := SecondOrderCabbelingCoeff * (2*sAnom*dS*tAnom + sAnom*sAnom*dtAnom)
	dst2 := SecondOrderCabbelingCoeff * (dS*tAnom*tAnom + sAnom*2*tAnom*dtAnom)
	st := sAnom * tAnom
	dst := dS*tAnom + sAnom*dtAnom
	dTri1 := TripleCabbelingCoeff * (dst*pyc1 + st*dp1)
	dTri2 := TripleCabbelingCoeff * (dst*pyc2 + st*dp2)
	fThermo := ThermostericAnomalyCoeff * 0.01
	dThermo := fThermo * (dtAnom*depth + tAnom)
	fHalo := HalostericAnomalyCoeff * 0.01
	dHalo := fHalo * (dS*depth + sAnom)
	Cdm := 1 - expDm
	dCdm := expDm / DoubleDiffusiveMixingScale
	dVort := VorticityMixingCoeff * (Cdm + depth*dCdm)
	return DepthDensityGradient + dp1 + dp2 + dp3 + SalinityDensityCoeff*dS + ThermalCouplingCoeff*df + termCab1 + termCab2 + termCab3 + termCab4 + termQuadT + termQuadS + ds2t + dst2 + dTri1 + dTri2 + dThermo + dHalo + dVort, nil
}

func (sw Seawater) DensitySecondDerivativeAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	expS1 := math.Exp(-depth / PycnoclineScale)
	expS2 := math.Exp(-depth / DeepPycnoclineScale)
	expS3 := math.Exp(-depth / MidPycnoclineScale)
	expH := math.Exp(-depth / HaloclineScale)
	expT := math.Exp(-depth / ThermoclineScale)
	expDm := math.Exp(-depth / DoubleDiffusiveMixingScale)
	sAnom := HaloclineDelta * (1 - expH)
	tAnom := 12.0 * (1 - expT)
	pyc1 := PycnoclineDelta * (1 - expS1)
	pyc2 := DeepPycnoclineDelta * (1 - expS2)
	pyc3 := MidPycnoclineDelta * (1 - expS3)
	dS := HaloclineDelta / HaloclineScale * expH
	dtAnom := 12.0 / ThermoclineScale * expT
	d2S := -HaloclineDelta / (HaloclineScale * HaloclineScale) * expH
	d2tAnom := -12.0 / (ThermoclineScale * ThermoclineScale) * expT
	dp1 := PycnoclineDelta / PycnoclineScale * expS1
	dp2 := DeepPycnoclineDelta / DeepPycnoclineScale * expS2
	dp3 := MidPycnoclineDelta / MidPycnoclineScale * expS3
	d2p1 := -PycnoclineDelta / (PycnoclineScale * PycnoclineScale) * expS1
	d2p2 := -DeepPycnoclineDelta / (DeepPycnoclineScale * DeepPycnoclineScale) * expS2
	d2p3 := -MidPycnoclineDelta / (MidPycnoclineScale * MidPycnoclineScale) * expS3
	d2f := d2tAnom*(1.0+GammaDepthFactor*depth) + 2.0*GammaDepthFactor*dtAnom
	tCab1 := CabbelingCoeff * (d2S*tAnom + 2*dS*dtAnom + sAnom*d2tAnom)
	tCab2 := CabbelingCoeff * (d2p3*sAnom + 2*dp3*dS + pyc3*d2S)
	tCab3 := CabbelingCoeff * (d2p1*sAnom + 2*dp1*dS + pyc1*d2S)
	tCab4 := CabbelingCoeff * (d2p2*tAnom + 2*dp2*dtAnom + pyc2*d2tAnom)
	tQuadT := TAnomQuadCoeff * (2*dtAnom*dtAnom + 2*tAnom*d2tAnom)
	tQuadS := SAnomQuadCoeff * (2*dS*dS + 2*sAnom*d2S)
	s2 := sAnom * sAnom
	ds2 := 2 * sAnom * dS
	d2s2 := 2*dS*dS + 2*sAnom*d2S
	t2 := tAnom * tAnom
	dt2 := 2 * tAnom * dtAnom
	d2t2 := 2*dtAnom*dtAnom + 2*tAnom*d2tAnom
	d2s2t := SecondOrderCabbelingCoeff * (d2s2*tAnom + 2*ds2*dtAnom + s2*d2tAnom)
	d2st2 := SecondOrderCabbelingCoeff * (d2S*t2 + 2*dS*dt2 + sAnom*d2t2)
	st := sAnom * tAnom
	dst := dS*tAnom + sAnom*dtAnom
	d2st := d2S*tAnom + 2*dS*dtAnom + sAnom*d2tAnom
	d2tri1 := TripleCabbelingCoeff * (d2st*pyc1 + 2*dst*dp1 + st*d2p1)
	d2tri2 := TripleCabbelingCoeff * (d2st*pyc2 + 2*dst*dp2 + st*d2p2)
	fThermo := ThermostericAnomalyCoeff * 0.01
	d2Thermo := fThermo * (d2tAnom*depth + 2*dtAnom)
	fHalo := HalostericAnomalyCoeff * 0.01
	d2Halo := fHalo * (d2S*depth + 2*dS)
	dCdm := expDm / DoubleDiffusiveMixingScale
	d2Cdm := -expDm / (DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale)
	d2Vort := VorticityMixingCoeff * (2*dCdm + depth*d2Cdm)
	return d2p1 + d2p2 + d2p3 + SalinityDensityCoeff*d2S + ThermalCouplingCoeff*d2f + tCab1 + tCab2 + tCab3 + tCab4 + tQuadT + tQuadS + d2s2t + d2st2 + d2tri1 + d2tri2 + d2Thermo + d2Halo + d2Vort, nil
}

func (sw Seawater) DensityThirdDerivativeAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	expS1 := math.Exp(-depth / PycnoclineScale)
	expS2 := math.Exp(-depth / DeepPycnoclineScale)
	expS3 := math.Exp(-depth / MidPycnoclineScale)
	expH := math.Exp(-depth / HaloclineScale)
	expT := math.Exp(-depth / ThermoclineScale)
	expDm := math.Exp(-depth / DoubleDiffusiveMixingScale)
	sAnom := HaloclineDelta * (1 - expH)
	tAnom := 12.0 * (1 - expT)
	pyc1 := PycnoclineDelta * (1 - expS1)
	pyc2 := DeepPycnoclineDelta * (1 - expS2)
	pyc3 := MidPycnoclineDelta * (1 - expS3)
	dS := HaloclineDelta / HaloclineScale * expH
	dtAnom := 12.0 / ThermoclineScale * expT
	d2S := -HaloclineDelta / (HaloclineScale * HaloclineScale) * expH
	d2tAnom := -12.0 / (ThermoclineScale * ThermoclineScale) * expT
	d3S := HaloclineDelta / (HaloclineScale * HaloclineScale * HaloclineScale) * expH
	d3tAnom := 12.0 / (ThermoclineScale * ThermoclineScale * ThermoclineScale) * expT
	dp1 := PycnoclineDelta / PycnoclineScale * expS1
	dp2 := DeepPycnoclineDelta / DeepPycnoclineScale * expS2
	dp3 := MidPycnoclineDelta / MidPycnoclineScale * expS3
	d2p1 := -PycnoclineDelta / (PycnoclineScale * PycnoclineScale) * expS1
	d2p2 := -DeepPycnoclineDelta / (DeepPycnoclineScale * DeepPycnoclineScale) * expS2
	d2p3 := -MidPycnoclineDelta / (MidPycnoclineScale * MidPycnoclineScale) * expS3
	d3p1 := PycnoclineDelta / (PycnoclineScale * PycnoclineScale * PycnoclineScale) * expS1
	d3p2 := DeepPycnoclineDelta / (DeepPycnoclineScale * DeepPycnoclineScale * DeepPycnoclineScale) * expS2
	d3p3 := MidPycnoclineDelta / (MidPycnoclineScale * MidPycnoclineScale * MidPycnoclineScale) * expS3
	d3f := d3tAnom*(1.0+GammaDepthFactor*depth) + 3.0*GammaDepthFactor*d2tAnom
	tCab1 := CabbelingCoeff * (d3S*tAnom + 3*d2S*dtAnom + 3*dS*d2tAnom + sAnom*d3tAnom)
	tCab2 := CabbelingCoeff * (d3p3*sAnom + 3*d2p3*dS + 3*dp3*d2S + pyc3*d3S)
	tCab3 := CabbelingCoeff * (d3p1*sAnom + 3*d2p1*dS + 3*dp1*d2S + pyc1*d3S)
	tCab4 := CabbelingCoeff * (d3p2*tAnom + 3*d2p2*dtAnom + 3*dp2*d2tAnom + pyc2*d3tAnom)
	tQuadT := TAnomQuadCoeff * (6*dtAnom*d2tAnom + 2*tAnom*d3tAnom)
	tQuadS := SAnomQuadCoeff * (6*dS*d2S + 2*sAnom*d3S)

	f_s2 := sAnom * sAnom
	df_s2 := 2 * sAnom * dS
	d2f_s2 := 2*dS*dS + 2*sAnom*d2S
	d3f_s2 := 6*dS*d2S + 2*sAnom*d3S
	d3s2tRaw := d3f_s2*tAnom + 3*d2f_s2*dtAnom + 3*df_s2*d2tAnom + f_s2*d3tAnom
	d3s2t := d3s2tRaw * SecondOrderCabbelingCoeff

	f_t2 := tAnom * tAnom
	df_t2 := 2 * tAnom * dtAnom
	d2f_t2 := 2*dtAnom*dtAnom + 2*tAnom*d2tAnom
	d3f_t2 := 6*dtAnom*d2tAnom + 2*tAnom*d3tAnom
	d3st2Raw := d3S*f_t2 + 3*d2S*df_t2 + 3*dS*d2f_t2 + sAnom*d3f_t2
	d3st2 := d3st2Raw * SecondOrderCabbelingCoeff

	st := sAnom * tAnom
	dst := dS*tAnom + sAnom*dtAnom
	d2st := d2S*tAnom + 2*dS*dtAnom + sAnom*d2tAnom
	d3st := d3S*tAnom + 3*d2S*dtAnom + 3*dS*d2tAnom + sAnom*d3tAnom

	d3tri1Raw := d3st*pyc1 + 3*d2st*dp1 + 3*dst*d2p1 + st*d3p1
	d3tri1 := d3tri1Raw * TripleCabbelingCoeff
	d3tri2Raw := d3st*pyc2 + 3*d2st*dp2 + 3*dst*d2p2 + st*d3p2
	d3tri2 := d3tri2Raw * TripleCabbelingCoeff

	fThermo := ThermostericAnomalyCoeff * 0.01
	d3Thermo := fThermo * (d3tAnom*depth + 3*d2tAnom)
	fHalo := HalostericAnomalyCoeff * 0.01
	d3Halo := fHalo * (d3S*depth + 3*d2S)
	d2Cdm := -expDm / (DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale)
	d3Cdm := expDm / (DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale)
	d3Vort := VorticityMixingCoeff * (3*d2Cdm + depth*d3Cdm)

	return d3p1 + d3p2 + d3p3 + SalinityDensityCoeff*d3S + ThermalCouplingCoeff*d3f + tCab1 + tCab2 + tCab3 + tCab4 + tQuadT + tQuadS + d3s2t + d3st2 + d3tri1 + d3tri2 + d3Thermo + d3Halo + d3Vort, nil
}

func (sw Seawater) CabbelingParameterAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	expH := math.Exp(-depth / HaloclineScale)
	expT := math.Exp(-depth / ThermoclineScale)
	expS1 := math.Exp(-depth / PycnoclineScale)
	expS2 := math.Exp(-depth / DeepPycnoclineScale)
	expS3 := math.Exp(-depth / MidPycnoclineScale)
	sAnom := HaloclineDelta * (1 - expH)
	tAnom := 12 * (1 - expT)
	pyc1 := PycnoclineDelta * (1 - expS1)
	pyc2 := DeepPycnoclineDelta * (1 - expS2)
	pyc3 := MidPycnoclineDelta * (1 - expS3)
	cab := CabbelingCoeff*sAnom*tAnom + CabbelingCoeff*pyc3*sAnom + CabbelingCoeff*pyc1*sAnom + CabbelingCoeff*pyc2*tAnom + TAnomQuadCoeff*tAnom*tAnom + SAnomQuadCoeff*sAnom*sAnom
	s2t := SecondOrderCabbelingCoeff * sAnom * sAnom * tAnom
	st2 := SecondOrderCabbelingCoeff * sAnom * tAnom * tAnom
	tri1 := TripleCabbelingCoeff * sAnom * tAnom * pyc1
	tri2 := TripleCabbelingCoeff * sAnom * tAnom * pyc2
	return cab + s2t + st2 + tri1 + tri2, nil
}
func (sw Seawater) SpicinessAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	s, _ := sw.SalinityAtDepth(depth)
	t, _ := sw.TemperatureAtDepth(depth)
	return SalinityDensityCoeff*(s-35.0) + ThermalCouplingCoeff*(t-15.0), nil
}
func (sw Seawater) SpicinessCurvatureAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	expH := math.Exp(-depth / HaloclineScale)
	expT := math.Exp(-depth / ThermoclineScale)
	d2S := -HaloclineDelta / (HaloclineScale * HaloclineScale) * expH
	d2T := 12.0 / (ThermoclineScale * ThermoclineScale) * expT
	return SalinityDensityCoeff*d2S + ThermalCouplingCoeff*d2T, nil
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
	return T * (1 - x - ThermobaricCoeff*x*x - 0.2*x*x*x) * (1 - AdiabaticLapseRate*depth*0.001), nil
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
	P, err := sw.PressureAtDepth(depth, StandardGravity)
	if err != nil {
		return 0, err
	}
	c := 1449.2 + 4.6*T - 0.055*T*T + 1.34*(S-35.0) + 0.016*depth + SoundSpeedPressureQuadCoeff*depth*depth + 0.01*T*(S-35.0)
	c += PressureNonLinearCoeff * 100 * (P / BulkModulus * 1e3) * T
	return c, nil
}
func (sw Seawater) SoundSpeedGradientAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	T, _ := sw.TemperatureAtDepth(depth)
	dT, _ := sw.TemperatureGradientAtDepth(depth)
	dS, _ := sw.SalinityGradientAtDepth(depth)
	S, _ := sw.SalinityAtDepth(depth)
	rho, _ := sw.DensityAtDepth(depth)
	dPdz := rho * StandardGravity
	P, _ := sw.PressureAtDepth(depth, StandardGravity)
	base := 4.6*dT - 0.11*T*dT + 1.34*dS + 0.016 + 2.0*SoundSpeedPressureQuadCoeff*depth + 0.01*dT*(S-35.0) + 0.01*T*dS
	termP := PressureNonLinearCoeff * 100 * ((dPdz/BulkModulus*1e3)*T + (P/BulkModulus*1e3)*dT)
	return base + termP, nil
}

func (sw Seawater) FindSOFARAxis(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth <= 0 {
		return 0, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return 0, errors.New("tolerance must be positive")
	}
	N := 2000
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
	for iter := 0; iter < 100; iter++ {
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
func (sw Seawater) FindPycnoclineMaxGradient(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth <= 0 {
		return 0, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return 0, errors.New("tolerance must be positive")
	}
	N := 2000
	dz := maxDepth / float64(N)
	bestG := -1e99
	bestIdx := 0
	zs := make([]float64, N+1)
	for i := 0; i <= N; i++ {
		z := float64(i) * dz
		g, _ := sw.DensityGradientAtDepth(z)
		zs[i] = z
		if g > bestG {
			bestG = g
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
	for iter := 0; iter < 100; iter++ {
		if hi-lo < tolerance {
			break
		}
		m1 := lo + (hi-lo)/3.0
		m2 := hi - (hi-lo)/3.0
		g1, _ := sw.DensityGradientAtDepth(m1)
		g2, _ := sw.DensityGradientAtDepth(m2)
		if g1 > g2 {
			hi = m2
		} else {
			lo = m1
		}
	}
	return (lo + hi) / 2.0, nil
}
func (sw Seawater) FindSpicinessMaximum(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth <= 0 {
		return 0, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return 0, errors.New("tolerance must be positive")
	}
	N := 2000
	dz := maxDepth / float64(N)
	bestS := -1e99
	bestIdx := 0
	zs := make([]float64, N+1)
	for i := 0; i <= N; i++ {
		z := float64(i) * dz
		s, _ := sw.SpicinessAtDepth(z)
		zs[i] = z
		if s > bestS {
			bestS = s
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
	for iter := 0; iter < 100; iter++ {
		if hi-lo < tolerance {
			break
		}
		m1 := lo + (hi-lo)/3.0
		m2 := hi - (hi-lo)/3.0
		s1, _ := sw.SpicinessAtDepth(m1)
		s2, _ := sw.SpicinessAtDepth(m2)
		if s1 > s2 {
			hi = m2
		} else {
			lo = m1
		}
	}
	return (lo + hi) / 2.0, nil
}
func (sw Seawater) FindDoubleDiffusiveLayer(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth <= 0 {
		return 0, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return 0, errors.New("tolerance must be positive")
	}
	N := 2000
	dz := maxDepth / float64(N)
	zs := make([]float64, N+1)
	tas := make([]float64, N+1)
	for i := 0; i <= N; i++ {
		z := float64(i) * dz
		zs[i] = z
		ta, _ := sw.TurnerAngleAtDepth(z)
		tas[i] = ta
	}
	var brackets [][2]float64
	for i := 0; i < N; i++ {
		if (tas[i]-45)*(tas[i+1]-45) <= 0 {
			brackets = append(brackets, [2]float64{zs[i], zs[i+1]})
		}
		if (tas[i]+45)*(tas[i+1]+45) <= 0 {
			brackets = append(brackets, [2]float64{zs[i], zs[i+1]})
		}
	}
	if len(brackets) == 0 {
		return 0, errors.New("no double-diffusive layer: no sign change")
	}
	lo := brackets[0][0]
	hi := brackets[0][1]
	f := func(z float64) float64 {
		ta, _ := sw.TurnerAngleAtDepth(z)
		return math.Abs(ta) - 45
	}
	for iter := 0; iter < 100; iter++ {
		if hi-lo < tolerance {
			break
		}
		mid := (lo + hi) / 2
		fmid := f(mid)
		flo := f(lo)
		if flo*fmid <= 0 {
			hi = mid
		} else {
			lo = mid
		}
	}
	return (lo + hi) / 2, nil
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
	c, _ := sw.SoundSpeedAtDepth(depth)
	return g / rho * (grad - rho*g/(c*c)), nil
}
func (sw Seawater) TurnerAngleAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	dS, _ := sw.SalinityGradientAtDepth(depth)
	dT, _ := sw.TemperatureGradientAtDepth(depth)
	num := ThermalCouplingCoeff*dT + SalinityDensityCoeff*dS
	den := SalinityDensityCoeff*dS - ThermalCouplingCoeff*dT
	return math.Atan2(num, den) * 180.0 / math.Pi, nil
}
func (sw Seawater) DoubleDiffusiveRegimeAtDepth(depth float64) (string, error) {
	if err := sw.Validate(); err != nil {
		return "", err
	}
	if depth < 0 {
		return "", errors.New("depth must be non-negative")
	}
	ta, _ := sw.TurnerAngleAtDepth(depth)
	if ta > 45 {
		return "salt finger", nil
	}
	if ta < -45 {
		return "diffusive convection", nil
	}
	curv, _ := sw.SpicinessCurvatureAtDepth(depth)
	if math.Abs(ta) < 10 && math.Abs(curv) > VorticityMixingCoeff {
		return "thermohaline intrusion", nil
	}
	return "stable", nil
}
func (sw Seawater) PotentialVorticityAtDepth(depth float64, g float64) (float64, error) {
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	n2, _ := sw.BuoyancyFrequencySquared(depth, g)
	return 1e-4 * n2 / g, nil
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
	integralPyc2 := DeepPycnoclineDelta * integralOneMinusExp(DeepPycnoclineScale, z)
	integralPyc3 := MidPycnoclineDelta * integralOneMinusExp(MidPycnoclineScale, z)
	integralBeta := SalinityDensityCoeff * HaloclineDelta * integralOneMinusExp(HaloclineScale, z)
	integralGamma := ThermalCouplingCoeff * 12.0 * integralOneMinusExp(ThermoclineScale, z)
	integralGammaZ := ThermalCouplingCoeff * GammaDepthFactor * 12.0 * integralZOneMinusExp(ThermoclineScale, z)

	integralCabST := CabbelingCoeff * HaloclineDelta * 12.0 * integralProductOneMinusExp([]float64{HaloclineScale, ThermoclineScale}, z)
	integralCabPyc3S := CabbelingCoeff * MidPycnoclineDelta * HaloclineDelta * integralProductOneMinusExp([]float64{MidPycnoclineScale, HaloclineScale}, z)
	integralCabPyc1S := CabbelingCoeff * PycnoclineDelta * HaloclineDelta * integralProductOneMinusExp([]float64{PycnoclineScale, HaloclineScale}, z)
	integralCabPyc2T := CabbelingCoeff * DeepPycnoclineDelta * 12.0 * integralProductOneMinusExp([]float64{DeepPycnoclineScale, ThermoclineScale}, z)

	integralQuadT := TAnomQuadCoeff * 144.0 * (z + 2*ThermoclineScale*math.Exp(-z/ThermoclineScale) - 2*ThermoclineScale + ThermoclineScale/2*(1-math.Exp(-2*z/ThermoclineScale)))
	integralQuadS := SAnomQuadCoeff * HaloclineDelta * HaloclineDelta * (z + 2*HaloclineScale*math.Exp(-z/HaloclineScale) - 2*HaloclineScale + HaloclineScale/2*(1-math.Exp(-2*z/HaloclineScale)))

	integralS2T := SecondOrderCabbelingCoeff * HaloclineDelta * HaloclineDelta * 12.0 * integralProductOneMinusExp([]float64{HaloclineScale, HaloclineScale, ThermoclineScale}, z)
	integralST2 := SecondOrderCabbelingCoeff * HaloclineDelta * 144.0 * integralProductOneMinusExp([]float64{HaloclineScale, ThermoclineScale, ThermoclineScale}, z)

	integralTri1 := TripleCabbelingCoeff * 300.0 * integralProductOneMinusExp([]float64{PycnoclineScale, HaloclineScale, ThermoclineScale}, z)
	integralTri2 := TripleCabbelingCoeff * 135.0 * integralProductOneMinusExp([]float64{DeepPycnoclineScale, HaloclineScale, ThermoclineScale}, z)

	integralThermo := ThermostericAnomalyCoeff * 0.01 * 12.0 * integralZOneMinusExp(ThermoclineScale, z)
	integralHalo := HalostericAnomalyCoeff * 0.01 * HaloclineDelta * integralZOneMinusExp(HaloclineScale, z)
	integralVort := VorticityMixingCoeff * integralZOneMinusExp(DoubleDiffusiveMixingScale, z)

	total := sw.Density*z + 0.5*DepthDensityGradient*z*z + integralPyc1 + integralPyc2 + integralPyc3 + integralBeta + integralGamma + integralGammaZ + integralCabST + integralCabPyc3S + integralCabPyc1S + integralCabPyc2T + integralQuadT + integralQuadS + integralS2T + integralST2 + integralTri1 + integralTri2 + integralThermo + integralHalo + integralVort
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
	factor := 1.0 + HullThermalExpansionCoeff*dT + HullThermalExpansionQuadCoeff*dT*dT
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
func (sub Submarine) BulkModulusAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
	if err := sub.Validate(); err != nil {
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
	if sub.HullCompressibility <= 0 {
		return BulkModulus, nil
	}
	return 1.0 / sub.HullCompressibility, nil
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
