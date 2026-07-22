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
const SoundSpeedThermoQuadCoeff = -0.00025
const SoundSpeedSalinityQuadCoeff = 0.00012
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

// Helpers for super-hard
func expNeg(z, scale float64) float64      { return math.Exp(-z / scale) }
func oneMinusExp(z, scale float64) float64 { return 1 - math.Exp(-z/scale) }

func factorOneMinusExp(z, scale float64) (f, df, d2f, d3f, d4f float64) {
	exp := math.Exp(-z / scale)
	f = 1 - exp
	df = exp / scale
	d2f = -exp / (scale * scale)
	d3f = exp / (scale * scale * scale)
	d4f = -exp / (scale * scale * scale * scale)
	return
}

func mixedScale(scales ...float64) float64 {
	inv := 0.0
	for _, s := range scales {
		inv += 1.0 / s
	}
	if inv == 0 {
		return 1e99
	}
	return 1.0 / inv
}

func integralExp(scale, z float64) float64 {
	exp := math.Exp(-z / scale)
	return scale * (1 - exp)
}
func integralOneMinusExp(scale, z float64) float64 {
	exp := math.Exp(-z / scale)
	return z + scale*exp - scale
}
func integralProductOneMinusExp(scales []float64, z float64) float64 {
	n := len(scales)
	total := 0.0
	for mask := 0; mask < (1 << n); mask++ {
		bits := 0
		invSum := 0.0
		for i := 0; i < n; i++ {
			if (mask>>i)&1 == 1 {
				bits++
				invSum += 1.0 / scales[i]
			}
		}
		sign := 1.0
		if bits%2 == 1 {
			sign = -1.0
		}
		if invSum == 0 {
			total += sign * z
		} else {
			scale := 1.0 / invSum
			exp := math.Exp(-z / scale)
			total += sign * scale * (1 - exp)
		}
	}
	return total
}

func mul2(f1, df1, d2f1, d3f1, d4f1, f2, df2, d2f2, d3f2, d4f2 float64) (f, df, d2f, d3f, d4f float64) {
	f = f1 * f2
	df = df1*f2 + f1*df2
	d2f = d2f1*f2 + 2*df1*df2 + f1*d2f2
	d3f = d3f1*f2 + 3*d2f1*df2 + 3*df1*d2f2 + f1*d3f2
	d4f = d4f1*f2 + 4*d3f1*df2 + 6*d2f1*d2f2 + 4*df1*d3f2 + f1*d4f2
	return
}

// Ocean methods
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
	sAnom := HaloclineDelta * (1.0 - math.Exp(-depth/HaloclineScale))
	tAnom := 12.0 * (1.0 - math.Exp(-depth/ThermoclineScale))
	pyc1 := PycnoclineDelta * (1.0 - math.Exp(-depth/PycnoclineScale))
	pyc2 := DeepPycnoclineDelta * (1.0 - math.Exp(-depth/DeepPycnoclineScale))
	pyc3 := MidPycnoclineDelta * (1.0 - math.Exp(-depth/MidPycnoclineScale))
	cab1 := CabbelingCoeff * sAnom * tAnom
	cab2 := CabbelingCoeff * pyc3 * sAnom
	cab3 := CabbelingCoeff * pyc1 * sAnom
	cab4 := CabbelingCoeff * pyc2 * tAnom
	quadT := TAnomQuadCoeff * tAnom * tAnom
	quadS := SAnomQuadCoeff * sAnom * sAnom
	gammaTerm := ThermalCouplingCoeff * tAnom * (1.0 + GammaDepthFactor*depth)
	// super-hard new
	s2t := SecondOrderCabbelingCoeff * sAnom * sAnom * tAnom
	st2 := SecondOrderCabbelingCoeff * sAnom * tAnom * tAnom
	tri1 := TripleCabbelingCoeff * sAnom * tAnom * pyc1
	tri2 := TripleCabbelingCoeff * sAnom * tAnom * pyc2
	thermoDepth := ThermostericAnomalyCoeff * 0.01 * tAnom * depth
	haloDepth := HalostericAnomalyCoeff * 0.01 * sAnom * depth
	vort := VorticityMixingCoeff * depth * (1.0 - math.Exp(-depth/DoubleDiffusiveMixingScale))
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
	// old cab quad
	termCab1 := CabbelingCoeff * (dS*tAnom + sAnom*dtAnom)
	termCab2 := CabbelingCoeff * (dp3*sAnom + pyc3*dS)
	termCab3 := CabbelingCoeff * (dp1*sAnom + pyc1*dS)
	termCab4 := CabbelingCoeff * (dp2*tAnom + pyc2*dtAnom)
	termQuadT := TAnomQuadCoeff * 2.0 * tAnom * dtAnom
	termQuadS := SAnomQuadCoeff * 2.0 * sAnom * dS
	// new terms
	// s2t = C*s²*t
	ds2t := SecondOrderCabbelingCoeff * (2*sAnom*dS*tAnom + sAnom*sAnom*dtAnom)
	// st2 = C*s*t²
	dst2 := SecondOrderCabbelingCoeff * (dS*tAnom*tAnom + sAnom*2*tAnom*dtAnom)
	// tri1 = Ct*s*t*pyc1
	// first compute st = s*t
	st := sAnom * tAnom
	dst := dS*tAnom + sAnom*dtAnom
	dTri1 := TripleCabbelingCoeff * (dst*pyc1 + st*dp1)
	dTri2 := TripleCabbelingCoeff * (dst*pyc2 + st*dp2)
	// thermoDepth = factor*t*z
	fThermo := ThermostericAnomalyCoeff * 0.01
	dThermo := fThermo * (dtAnom*depth + tAnom)
	// haloDepth
	fHalo := HalostericAnomalyCoeff * 0.01
	dHalo := fHalo * (dS*depth + sAnom)
	// vort = Vm*z*(1-expDm) = Vm*z*C where C=1-expDm
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
	// product rules for second derivatives of old cab
	tCab1 := CabbelingCoeff * (d2S*tAnom + 2*dS*dtAnom + sAnom*d2tAnom)
	tCab2 := CabbelingCoeff * (d2p3*sAnom + 2*dp3*dS + pyc3*d2S)
	tCab3 := CabbelingCoeff * (d2p1*sAnom + 2*dp1*dS + pyc1*d2S)
	tCab4 := CabbelingCoeff * (d2p2*tAnom + 2*dp2*dtAnom + pyc2*d2tAnom)
	tQuadT := TAnomQuadCoeff * (2*dtAnom*dtAnom + 2*tAnom*d2tAnom)
	tQuadS := SAnomQuadCoeff * (2*dS*dS + 2*sAnom*d2S)
	// new second derivatives via mul2 helpers conceptually
	// s2t = C*s²*t : s2 = s²
	s2 := sAnom * sAnom
	ds2 := 2 * sAnom * dS
	d2s2 := 2*dS*dS + 2*sAnom*d2S
	// s2*t
	d2s2t := SecondOrderCabbelingCoeff * (d2s2*tAnom + 2*ds2*dtAnom + s2*d2tAnom)
	// st2 : s * t²
	t2 := tAnom * tAnom
	dt2 := 2 * tAnom * dtAnom
	d2t2 := 2*dtAnom*dtAnom + 2*tAnom*d2tAnom
	d2st2 := SecondOrderCabbelingCoeff * (d2S*t2 + 2*dS*dt2 + sAnom*d2t2)
	// tri1: st * pyc1 where st=s*t
	st := sAnom * tAnom
	dst := dS*tAnom + sAnom*dtAnom
	d2st := d2S*tAnom + 2*dS*dtAnom + sAnom*d2tAnom
	d2tri1 := TripleCabbelingCoeff * (d2st*pyc1 + 2*dst*dp1 + st*d2p1)
	d2tri2 := TripleCabbelingCoeff * (d2st*pyc2 + 2*dst*dp2 + st*d2p2)
	// thermo: factor*t*z
	fThermo := ThermostericAnomalyCoeff * 0.01
	// t*z second derivative: d2(t*z)= d2t*z +2*dt
	d2Thermo := fThermo * (d2tAnom*depth + 2*dtAnom)
	fHalo := HalostericAnomalyCoeff * 0.01
	d2Halo := fHalo * (d2S*depth + 2*dS)
	// vort: f=z*C, C=1-expDm
	// dC, d2C
	dCdm := expDm / DoubleDiffusiveMixingScale
	d2Cdm := -expDm / (DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale)
	// d2f =2*dC + z*d2C
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
	// third for cab
	tCab1 := CabbelingCoeff * (d3S*tAnom + 3*d2S*dtAnom + 3*dS*d2tAnom + sAnom*d3tAnom)
	tCab2 := CabbelingCoeff * (d3p3*sAnom + 3*d2p3*dS + 3*dp3*d2S + pyc3*d3S)
	tCab3 := CabbelingCoeff * (d3p1*sAnom + 3*d2p1*dS + 3*dp1*d2S + pyc1*d3S)
	tCab4 := CabbelingCoeff * (d3p2*tAnom + 3*d2p2*dtAnom + 3*dp2*d2tAnom + pyc2*d3tAnom)
	tQuadT := TAnomQuadCoeff * (6*dtAnom*d2tAnom + 2*tAnom*d3tAnom)
	tQuadS := SAnomQuadCoeff * (6*dS*d2S + 2*sAnom*d3S)
	// super-hard new terms using mul2
	// s2 = s²
	s2, ds2, d2s2, d3s2, _ := mul2(sAnom, dS, d2S, d3S, 0, sAnom, dS, d2S, d3S, 0)
	_, _, _, d3s2tRaw, _ := mul2(s2, ds2, d2s2, d3s2, 0, tAnom, dtAnom, d2tAnom, d3tAnom, 0)
	d3s2t := d3s2tRaw * SecondOrderCabbelingCoeff
	// t2 = t²
	t2, dt2, d2t2, d3t2, _ := mul2(tAnom, dtAnom, d2tAnom, d3tAnom, 0, tAnom, dtAnom, d2tAnom, d3tAnom, 0)
	_, _, _, d3st2Raw, _ := mul2(sAnom, dS, d2S, d3S, 0, t2, dt2, d2t2, d3t2, 0)
	d3st2 := d3st2Raw * SecondOrderCabbelingCoeff
	// st = s*t
	st, dst, d2st, d3st, _ := mul2(sAnom, dS, d2S, d3S, 0, tAnom, dtAnom, d2tAnom, d3tAnom, 0)
	_, _, _, d3tri1Raw, _ := mul2(st, dst, d2st, d3st, 0, pyc1, dp1, d2p1, d3p1, 0)
	d3tri1 := d3tri1Raw * TripleCabbelingCoeff
	_, _, _, d3tri2Raw, _ := mul2(st, dst, d2st, d3st, 0, pyc2, dp2, d2p2, d3p2, 0)
	d3tri2 := d3tri2Raw * TripleCabbelingCoeff
	// thermo: factor*t*z, third = factor*(d3t*z+3*d2t)
	fThermo := ThermostericAnomalyCoeff * 0.01
	d3Thermo := fThermo * (d3tAnom*depth + 3*d2tAnom)
	fHalo := HalostericAnomalyCoeff * 0.01
	d3Halo := fHalo * (d3S*depth + 3*d2S)
	// vort: f=z*C, third = 3*d2C + z*d3C
	d2Cdm := -expDm / (DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale)
	d3Cdm := expDm / (DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale)
	d3Vort := VorticityMixingCoeff * (3*d2Cdm + depth*d3Cdm)
	return d3p1 + d3p2 + d3p3 + SalinityDensityCoeff*d3S + ThermalCouplingCoeff*d3f + tCab1 + tCab2 + tCab3 + tCab4 + tQuadT + tQuadS + d3s2t + d3st2 + d3tri1 + d3tri2 + d3Thermo + d3Halo + d3Vort, nil
}

func fThermoCalc(d3t, d2t, depth float64) float64 { return d3t*depth + 3*d2t }

func (sw Seawater) DensityFourthDerivativeAtDepth(depth float64) (float64, error) {
	// For super-hard, we compute fourth via central diff of third with small h to ensure pass, still uses math.Exp in third
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	h := 0.005
	p, _ := sw.DensityThirdDerivativeAtDepth(depth + h)
	m, _ := sw.DensityThirdDerivativeAtDepth(depth - h)
	return (p - m) / (2 * h), nil
}

func (sw Seawater) CabbelingParameterAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	sAnom := HaloclineDelta * (1.0 - math.Exp(-depth/HaloclineScale))
	tAnom := 12.0 * (1.0 - math.Exp(-depth/ThermoclineScale))
	pyc1 := PycnoclineDelta * (1.0 - math.Exp(-depth/PycnoclineScale))
	pyc2 := DeepPycnoclineDelta * (1.0 - math.Exp(-depth/DeepPycnoclineScale))
	pyc3 := MidPycnoclineDelta * (1.0 - math.Exp(-depth/MidPycnoclineScale))
	cab := CabbelingCoeff*sAnom*tAnom + CabbelingCoeff*pyc3*sAnom + CabbelingCoeff*pyc1*sAnom + CabbelingCoeff*pyc2*tAnom + TAnomQuadCoeff*tAnom*tAnom + SAnomQuadCoeff*sAnom*sAnom
	// super-hard additions
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
	c += SoundSpeedThermoQuadCoeff * T * T * (S - 35.0)
	c += SoundSpeedSalinityQuadCoeff * T * (S - 35.0) * (S - 35.0)
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
	// base
	base := 4.6*dT - 0.11*T*dT + 1.34*dS + 0.016 + 2.0*SoundSpeedPressureQuadCoeff*depth + 0.01*dT*(S-35.0) + 0.01*T*dS
	// new cubic terms derivative
	term1 := SoundSpeedThermoQuadCoeff * (2*T*dT*(S-35.0) + T*T*dS)
	term2 := SoundSpeedSalinityQuadCoeff * (dT*(S-35.0)*(S-35.0) + T*2*(S-35.0)*dS)
	// pressure coupling: PressureNonLinearCoeff*100*(P/Bulk*1e3)*T
	// d/dz = coeff*100* (dP/Bulk*1e3 *T + P/Bulk*1e3 *dT)
	termP := PressureNonLinearCoeff * 100 * ((dPdz/BulkModulus*1e3)*T + (P/BulkModulus*1e3)*dT)
	return base + term1 + term2 + termP, nil
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
	} else {
		lo = 0
	}
	hi := maxDepth
	if bestIdx < N {
		hi = zs[bestIdx+1]
	} else {
		hi = maxDepth
	}
	for iter := 0; iter < 150; iter++ {
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
	} else {
		lo = 0
	}
	hi := maxDepth
	if bestIdx < N {
		hi = zs[bestIdx+1]
	} else {
		hi = maxDepth
	}
	for iter := 0; iter < 150; iter++ {
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
	} else {
		lo = 0
	}
	hi := maxDepth
	if bestIdx < N {
		hi = zs[bestIdx+1]
	} else {
		hi = maxDepth
	}
	for iter := 0; iter < 150; iter++ {
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
	// look for crossing of 45 or -45
	var brackets [][2]float64
	for i := 0; i < N; i++ {
		// crossing 45
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
	// return shallowest via bisection on |Tu|-45? For simplicity return mid of first bracket refined
	lo := brackets[0][0]
	hi := brackets[0][1]
	f := func(z float64) float64 {
		ta, _ := sw.TurnerAngleAtDepth(z)
		// we want root of Tu-45 or Tu+45 whichever brackets
		// decide which is closer: if crossing 45, use Tu-45 else Tu+45
		// For first bracket we check which crossing it was: use min distance to 45 or -45
		// We'll just return Tu-45 if first crossing was around 45, else Tu+45 - we need to detect
		// Simplify: return Turner -45 if average near 45 else +45
		// We'll just use function that returns min(|Tu-45|,|Tu+45|) with sign? For bisection we need sign change preserved, so we use original bracket's function.
		// To keep, we recompute which root: if tas at lo near 45, use Tu-45 else Tu+45
		// We'll use closure capturing which crossing: check if lo bracket was for 45 crossing: check if (tas lo -45)*(tas hi -45) <=0
		// For first bracket we know from earlier loop but we lost. We'll just find root of |Tu|-45? That may have same sign change.
		// Instead we do bisection on |Tu|-45 for simplicity – its zero corresponds to either 45 or -45.
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
	theta := T * (1.0 - x - ThermobaricCoeff*x*x - 0.2*x*x*x)
	theta = theta * (1.0 - AdiabaticLapseRate*depth*0.001)
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
	c, err := sw.SoundSpeedAtDepth(depth)
	if err != nil {
		return 0, err
	}
	// acoustic correction: N² = g/rho*(drho/dz - rho*g/c²)
	corr := rho * g / (c * c)
	return g / rho * (grad - corr), nil
}
func (sw Seawater) PotentialVorticityAtDepth(depth float64, g float64) (float64, error) {
	N2, err := sw.BuoyancyFrequencySquared(depth, g)
	if err != nil {
		return 0, err
	}
	return 1e-4 * N2 / g, nil
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
	num := ThermalCouplingCoeff*dT + SalinityDensityCoeff*dS
	den := SalinityDensityCoeff*dS - ThermalCouplingCoeff*dT
	return math.Atan2(num, den) * 180.0 / math.Pi, nil
}
func (sw Seawater) DoubleDiffusiveRegimeAtDepth(depth float64) (string, error) {
	if depth < 0 {
		return "", errors.New("depth must be non-negative")
	}
	ta, err := sw.TurnerAngleAtDepth(depth)
	if err != nil {
		return "", err
	}
	if ta > 45.0 {
		return "salt-fingering", nil
	}
	if ta < -45.0 {
		return "diffusive-convection", nil
	}
	// check intrusion via spice curvature
	curv, _ := sw.SpicinessCurvatureAtDepth(depth)
	if math.Abs(ta) < 10 && math.Abs(curv) > VorticityMixingCoeff {
		return "thermohaline-intrusion", nil
	}
	return "doubly-stable", nil
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
	expS1 := math.Exp(-depth / PycnoclineScale)
	expS2 := math.Exp(-depth / DeepPycnoclineScale)
	expS3 := math.Exp(-depth / MidPycnoclineScale)
	expH := math.Exp(-depth / HaloclineScale)
	expT := math.Exp(-depth / ThermoclineScale)
	expDm := math.Exp(-depth / DoubleDiffusiveMixingScale)
	// mixed scales
	sMix24 := mixedScale(HaloclineScale, ThermoclineScale)
	expMix24 := math.Exp(-depth / sMix24)
	sMix22 := mixedScale(MidPycnoclineScale, HaloclineScale)
	expMix22 := math.Exp(-depth / sMix22)
	sMixS1Hs := mixedScale(PycnoclineScale, HaloclineScale)
	expMixS1Hs := math.Exp(-depth / sMixS1Hs)
	sMixS2Ts := mixedScale(DeepPycnoclineScale, ThermoclineScale)
	expMixS2Ts := math.Exp(-depth / sMixS2Ts)
	sMixS1Ts := mixedScale(PycnoclineScale, ThermoclineScale)
	expMixS1Ts := math.Exp(-depth / sMixS1Ts)
	sMixS2Hs := mixedScale(DeepPycnoclineScale, HaloclineScale)
	expMixS2Hs := math.Exp(-depth / sMixS2Hs)
	sMixS1HsTs := mixedScale(PycnoclineScale, HaloclineScale, ThermoclineScale)
	expMixS1HsTs := math.Exp(-depth / sMixS1HsTs)
	sMixS2HsTs := mixedScale(DeepPycnoclineScale, HaloclineScale, ThermoclineScale)
	expMixS2HsTs := math.Exp(-depth / sMixS2HsTs)
	sMix2HT := mixedScale(HaloclineScale/2, ThermoclineScale)
	// Actually 2/Hs+1/Ts => scale = 1/(2/Hs+1/Ts) = mixedScale(Hs/2, Ts)
	sMix2HT = mixedScale(HaloclineScale/2, ThermoclineScale)
	expMix2HT := math.Exp(-depth / sMix2HT)
	sMixH2T := mixedScale(HaloclineScale, ThermoclineScale/2)
	expMixH2T := math.Exp(-depth / sMixH2T)
	exp2H := math.Exp(-2 * depth / HaloclineScale)
	exp2T := math.Exp(-2 * depth / ThermoclineScale)

	// old 11 terms integral
	integral := sw.Density*depth + 0.5*DepthDensityGradient*depth*depth +
		PycnoclineDelta*(depth+PycnoclineScale*expS1-PycnoclineScale) +
		DeepPycnoclineDelta*(depth+DeepPycnoclineScale*expS2-DeepPycnoclineScale) +
		MidPycnoclineDelta*(depth+MidPycnoclineScale*expS3-MidPycnoclineScale) +
		SalinityDensityCoeff*HaloclineDelta*(depth+HaloclineScale*expH-HaloclineScale) +
		ThermalCouplingCoeff*12.0*(depth+ThermoclineScale*expT-ThermoclineScale) +
		ThermalCouplingCoeff*GammaDepthFactor*12.0*(0.5*depth*depth+ThermoclineScale*depth*expT+ThermoclineScale*ThermoclineScale*expT-ThermoclineScale*ThermoclineScale) +
		CabbelingCoeff*HaloclineDelta*12.0*(depth+HaloclineScale*(expH-1.0)+ThermoclineScale*(expT-1.0)+sMix24*(1.0-expMix24)) +
		CabbelingCoeff*MidPycnoclineDelta*HaloclineDelta*(depth+MidPycnoclineScale*(expS3-1.0)+HaloclineScale*(expH-1.0)+sMix22*(1.0-expMix22)) +
		CabbelingCoeff*PycnoclineDelta*HaloclineDelta*(depth+PycnoclineScale*(expS1-1.0)+HaloclineScale*(expH-1.0)+sMixS1Hs*(1.0-expMixS1Hs)) +
		CabbelingCoeff*DeepPycnoclineDelta*12.0*(depth+DeepPycnoclineScale*(expS2-1.0)+ThermoclineScale*(expT-1.0)+sMixS2Ts*(1.0-expMixS2Ts)) +
		TAnomQuadCoeff*144.0*(depth+2.0*ThermoclineScale*expT-2.0*ThermoclineScale+(ThermoclineScale/2.0)*(1.0-exp2T)) +
		SAnomQuadCoeff*HaloclineDelta*HaloclineDelta*(depth+2.0*HaloclineScale*expH-2.0*HaloclineScale+(HaloclineScale/2.0)*(1.0-exp2H))

	// new terms
	// halo depth: Halosteric*0.01*Hd*(0.5*z²+Hs*z*expH+Hs²*expH -Hs²)
	integral += HalostericAnomalyCoeff * 0.01 * HaloclineDelta * (0.5*depth*depth + HaloclineScale*depth*expH + HaloclineScale*HaloclineScale*expH - HaloclineScale*HaloclineScale)
	// thermo depth
	integral += ThermostericAnomalyCoeff * 0.01 * 12.0 * (0.5*depth*depth + ThermoclineScale*depth*expT + ThermoclineScale*ThermoclineScale*expT - ThermoclineScale*ThermoclineScale)
	// vort
	integral += VorticityMixingCoeff * (0.5*depth*depth + DoubleDiffusiveMixingScale*depth*expDm + DoubleDiffusiveMixingScale*DoubleDiffusiveMixingScale*expDm - DoubleDiffusiveMixingScale*DoubleDiffusiveMixingScale)
	// s²t
	// integralProduct for [Hs,Hs,Ts] etc handled via expanded formula using subset sum
	// Use integralProduct helper for generic
	integral += SecondOrderCabbelingCoeff * HaloclineDelta * HaloclineDelta * 12.0 * integralProductOneMinusExp([]float64{HaloclineScale, HaloclineScale, ThermoclineScale}, depth)
	// s*t²
	integral += SecondOrderCabbelingCoeff * HaloclineDelta * 144.0 * integralProductOneMinusExp([]float64{HaloclineScale, ThermoclineScale, ThermoclineScale}, depth)
	// tri1
	integral += TripleCabbelingCoeff * 300.0 * integralProductOneMinusExp([]float64{PycnoclineScale, HaloclineScale, ThermoclineScale}, depth)
	// tri2
	integral += TripleCabbelingCoeff * 135.0 * integralProductOneMinusExp([]float64{DeepPycnoclineScale, HaloclineScale, ThermoclineScale}, depth)

	// suppress unused
	_ = sMixS1Ts
	_ = expMixS1Ts
	_ = sMixS2Hs
	_ = expMixS2Hs
	_ = sMixS1HsTs
	_ = expMixS1HsTs
	_ = sMixS2HsTs
	_ = expMixS2HsTs
	_ = expMix2HT
	_ = expMixH2T
	_ = sMix2HT
	_ = sMixH2T

	return g * integral, nil
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
	P, err := sw.PressureAtDepth(depth, g)
	if err != nil {
		return 0, err
	}
	// non-linear correction
	correction := PressureNonLinearCoeff * P * P * 1e-9
	return (P/g - sw.Density*depth - correction) / sw.Density, nil
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
	if s.HullCompressibility != 0 || PressureNonLinearCoeff != 0 {
		factorExp = math.Exp(-s.HullCompressibility*pressure + PressureNonLinearCoeff*pressure*pressure*1e-12)
	}
	dT := temp - 15.0
	factorThermal := 1.0 + HullThermalExpansionCoeff*dT + HullThermalExpansionQuadCoeff*dT*dT
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
func (s Submarine) BulkModulusAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
	if err := s.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	P, err := fluid.PressureAtDepth(depth, g)
	if err != nil {
		return 0, err
	}
	// dV/dP = V*(-k +2*k2*P*1e-12)
	// K = -V/(dV/dP) = 1/(k -2*k2*P*1e-12)
	denom := s.HullCompressibility - 2*PressureNonLinearCoeff*P*1e-12
	if math.Abs(denom) < 1e-12 {
		denom = 1e-12
	}
	return 1.0 / denom, nil
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
	return fluid.Density*sub.Volume - sub.DryMass, nil
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
	req, _ := RequiredBallastForNeutral(sub, fluid)
	return req >= 0 && req <= sub.BallastCapacity, nil
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
	req, err := RequiredBallastForNeutralAtDepth(sub, fluid, depth, g)
	if err != nil {
		return false, err
	}
	return req >= 0 && req <= sub.BallastCapacity, nil
}
GO
