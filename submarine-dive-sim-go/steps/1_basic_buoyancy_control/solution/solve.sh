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
const QuadrupleCabbelingCoeff = 0.0009
const CompensatedLayerCoeff = 0.00006
const ThermohalineIntrusionScale = 22.0
const BaroclinicShearCoeff = 0.00004
const ThermostericSecondOrderCoeff = 2.5e-7
const HalostericSecondOrderCoeff = 1.2e-7
const SoundSpeedDepthCubeCoeff = 2e-9
const PressureCubicNonLinearCoeff = 7e-16

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

func mixedScale(scales ...float64) float64 {
	inv := 0.0
	for _, v := range scales {
		inv += 1.0 / v
	}
	if inv == 0 {
		return 1e99
	}
	return 1.0 / inv
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

func integralZExp(S, z float64) float64 {
	exp := math.Exp(-z / S)
	return S * S * (1.0 - exp*(1.0+z/S))
}

func integralZOneMinusExp(S, z float64) float64 {
	exp := math.Exp(-z / S)
	return 0.5*z*z + S*z*exp + S*S*exp - S*S
}

func integralZ2Exp(S, z float64) float64 {
	exp := math.Exp(-z / S)
	return 2*S*S*S - exp*(S*z*z+2*S*S*z+2*S*S*S)
}

func integralZ2OneMinusExp(S, z float64) float64 {
	exp := math.Exp(-z / S)
	return z*z*z/3.0 + exp*(S*z*z+2*S*S*z+2*S*S*S) - 2*S*S*S
}

func integralZProductOneMinusExp(scales []float64, z float64) float64 {
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
			total += sign * 0.5 * z * z
		} else {
			sc := 1.0 / inv
			exp := math.Exp(-z / sc)
			total += sign * sc * sc * (1.0 - exp*(1.0+z/sc))
		}
	}
	return total
}

func integralZ2ProductOneMinusExp(scales []float64, z float64) float64 {
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
			total += sign * z * z * z / 3.0
		} else {
			sc := 1.0 / inv
			exp := math.Exp(-z / sc)
			total += sign * (2*sc*sc*sc - exp*(sc*z*z+2*sc*sc*z+2*sc*sc*sc))
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
	expI := math.Exp(-depth / ThermohalineIntrusionScale)
	sAnom := HaloclineDelta * (1.0 - expH)
	tAnom := 12.0 * (1.0 - expT)
	pyc1 := PycnoclineDelta * (1.0 - expS1)
	pyc2 := DeepPycnoclineDelta * (1.0 - expS2)
	pyc3 := MidPycnoclineDelta * (1.0 - expS3)
	// old
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
	// new ultra-ultra
	quad := QuadrupleCabbelingCoeff * sAnom * sAnom * tAnom * tAnom
	comp := CompensatedLayerCoeff * pyc1 * pyc2 * sAnom
	baro := BaroclinicShearCoeff * depth * sAnom * tAnom * (1.0 - expI)
	thermoSec := ThermostericSecondOrderCoeff * 0.001 * tAnom * depth * depth
	haloSec := HalostericSecondOrderCoeff * 0.001 * sAnom * depth * depth
	return sw.Density + DepthDensityGradient*depth + pyc1 + pyc2 + pyc3 + SalinityDensityCoeff*sAnom + gammaTerm + cab1 + cab2 + cab3 + cab4 + quadT + quadS + s2t + st2 + tri1 + tri2 + thermoDepth + haloDepth + vort + quad + comp + baro + thermoSec + haloSec, nil
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
	expI := math.Exp(-depth / ThermohalineIntrusionScale)
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
	// new terms gradient
	// quad s²t²
	s2 := sAnom * sAnom
	ds2 := 2 * sAnom * dS
	t2 := tAnom * tAnom
	dt2 := 2 * tAnom * dtAnom
	dQuad := QuadrupleCabbelingCoeff * (ds2*t2 + s2*dt2)
	// compensated p1 p2 s
	dp12 := dp1*pyc2 + pyc1*dp2
	p12 := pyc1 * pyc2
	dComp := CompensatedLayerCoeff * (dp12*sAnom + p12*dS)
	// baroclinic z s t I
	I := 1 - expI
	dI := expI / ThermohalineIntrusionScale
	// st*I
	stI := st * I
	dstI := dst*I + st*dI
	// z*stI
	dBaroInner := stI + depth*dstI
	dBaro := BaroclinicShearCoeff * dBaroInner
	// thermoSecond t z²
	// t*z²
	z2 := depth * depth
	dz2 := 2 * depth
	dThSecInner := dtAnom*z2 + tAnom*dz2
	dThSec := ThermostericSecondOrderCoeff * 0.001 * dThSecInner
	// haloSecond s*z²
	dHaSecInner := dS*z2 + sAnom*dz2
	dHaSec := HalostericSecondOrderCoeff * 0.001 * dHaSecInner
	return DepthDensityGradient + dp1 + dp2 + dp3 + SalinityDensityCoeff*dS + ThermalCouplingCoeff*df + termCab1 + termCab2 + termCab3 + termCab4 + termQuadT + termQuadS + ds2t + dst2 + dTri1 + dTri2 + dThermo + dHalo + dVort + dQuad + dComp + dBaro + dThSec + dHaSec, nil
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
	expI := math.Exp(-depth / ThermohalineIntrusionScale)
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
	// new terms second
	d2Quad := QuadrupleCabbelingCoeff * (d2s2*t2 + 2*ds2*dt2 + s2*d2t2)
	p12 := pyc1 * pyc2
	dp12 := dp1*pyc2 + pyc1*dp2
	d2p12 := d2p1*pyc2 + 2*dp1*dp2 + pyc1*d2p2
	d2Comp := CompensatedLayerCoeff * (d2p12*sAnom + 2*dp12*dS + p12*d2S)
	I := 1 - expI
	dI := expI / ThermohalineIntrusionScale
	d2I := -expI / (ThermohalineIntrusionScale * ThermohalineIntrusionScale)
	// st*I
	dstI := dst*I + st*dI
	d2stI := d2st*I + 2*dst*dI + st*d2I
	d2Baro := BaroclinicShearCoeff * (2*dstI + depth*d2stI)
	z2 := depth * depth
	dz2 := 2 * depth
	d2z2 := 2.0
	d2ThSecInner := d2tAnom*z2 + 2*dtAnom*dz2 + tAnom*d2z2
	d2ThSec := ThermostericSecondOrderCoeff * 0.001 * d2ThSecInner
	d2HaSecInner := d2S*z2 + 2*dS*dz2 + sAnom*d2z2
	d2HaSec := HalostericSecondOrderCoeff * 0.001 * d2HaSecInner
	return d2p1 + d2p2 + d2p3 + SalinityDensityCoeff*d2S + ThermalCouplingCoeff*d2f + tCab1 + tCab2 + tCab3 + tCab4 + tQuadT + tQuadS + d2s2t + d2st2 + d2tri1 + d2tri2 + d2Thermo + d2Halo + d2Vort + d2Quad + d2Comp + d2Baro + d2ThSec + d2HaSec, nil
}

func dstI2(dI float64, st float64, dst float64, I float64) float64 {
	return dst*I + st*dI
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
	expI := math.Exp(-depth / ThermohalineIntrusionScale)
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
	s2, ds2, d2s2, d3s2, _ := mul2(sAnom, dS, d2S, d3S, 0, sAnom, dS, d2S, d3S, 0)
	_, _, _, d3s2tRaw, _ := mul2(s2, ds2, d2s2, d3s2, 0, tAnom, dtAnom, d2tAnom, d3tAnom, 0)
	d3s2t := d3s2tRaw * SecondOrderCabbelingCoeff
	t2, dt2, d2t2, d3t2, _ := mul2(tAnom, dtAnom, d2tAnom, d3tAnom, 0, tAnom, dtAnom, d2tAnom, d3tAnom, 0)
	_, _, _, d3st2Raw, _ := mul2(sAnom, dS, d2S, d3S, 0, t2, dt2, d2t2, d3t2, 0)
	d3st2 := d3st2Raw * SecondOrderCabbelingCoeff
	st, dst, d2st, d3st, _ := mul2(sAnom, dS, d2S, d3S, 0, tAnom, dtAnom, d2tAnom, d3tAnom, 0)
	_, _, _, d3tri1Raw, _ := mul2(st, dst, d2st, d3st, 0, pyc1, dp1, d2p1, d3p1, 0)
	d3tri1 := d3tri1Raw * TripleCabbelingCoeff
	_, _, _, d3tri2Raw, _ := mul2(st, dst, d2st, d3st, 0, pyc2, dp2, d2p2, d3p2, 0)
	d3tri2 := d3tri2Raw * TripleCabbelingCoeff
	fThermo := ThermostericAnomalyCoeff * 0.01
	d3Thermo := fThermo * (d3tAnom*depth + 3*d2tAnom)
	fHalo := HalostericAnomalyCoeff * 0.01
	d3Halo := fHalo * (d3S*depth + 3*d2S)
	d2Cdm := -expDm / (DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale)
	d3Cdm := expDm / (DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale * DoubleDiffusiveMixingScale)
	d3Vort := VorticityMixingCoeff * (3*d2Cdm + depth*d3Cdm)
		// new terms third
	// quad s²t²
	s2_2, ds2_2, d2s2_2, d3s2_2, _ := mul2(sAnom, dS, d2S, d3S, 0, sAnom, dS, d2S, d3S, 0)
	t2_2, dt2_2, d2t2_2, d3t2_2, _ := mul2(tAnom, dtAnom, d2tAnom, d3tAnom, 0, tAnom, dtAnom, d2tAnom, d3tAnom, 0)
	_, _, _, d3QuadRaw, _ := mul2(s2_2, ds2_2, d2s2_2, d3s2_2, 0, t2_2, dt2_2, d2t2_2, d3t2_2, 0)
	d3Quad := d3QuadRaw * QuadrupleCabbelingCoeff
	// compensated p1 p2 s
	p12, dp12, d2p12, d3p12, _ := mul2(pyc1, dp1, d2p1, d3p1, 0, pyc2, dp2, d2p2, d3p2, 0)
	_, _, _, d3CompRaw, _ := mul2(p12, dp12, d2p12, d3p12, 0, sAnom, dS, d2S, d3S, 0)
	d3Comp := d3CompRaw * CompensatedLayerCoeff
	// baroclinic z s t I
	I := 1 - expI
	dI := expI / ThermohalineIntrusionScale
	d2I := -expI / (ThermohalineIntrusionScale * ThermohalineIntrusionScale)
	d3I := expI / (ThermohalineIntrusionScale * ThermohalineIntrusionScale * ThermohalineIntrusionScale)
	st_2, dst_2, d2st_2, d3st_2, _ := mul2(sAnom, dS, d2S, d3S, 0, tAnom, dtAnom, d2tAnom, d3tAnom, 0)
	_, _, d2stI_2, d3stI_2, _ := mul2(st_2, dst_2, d2st_2, d3st_2, 0, I, dI, d2I, d3I, 0)
	// z*stI
	d3BaroInner := 3*d2stI_2 + depth*d3stI_2
	d3Baro := BaroclinicShearCoeff * d3BaroInner
	// thermoSecond t z²
	z2 := depth * depth
	dz2 := 2 * depth
	d2z2 := 2.0
	d3ThSecInner := d3tAnom*z2 + 3*d2tAnom*dz2 + 3*dtAnom*d2z2
	d3ThSec := ThermostericSecondOrderCoeff * 0.001 * d3ThSecInner
	// haloSecond s*z²
	d3HaSecInner := d3S*z2 + 3*d2S*dz2 + 3*dS*d2z2
	d3HaSec := HalostericSecondOrderCoeff * 0.001 * d3HaSecInner
	return d3p1 + d3p2 + d3p3 + SalinityDensityCoeff*d3S + ThermalCouplingCoeff*d3f + tCab1 + tCab2 + tCab3 + tCab4 + tQuadT + tQuadS + d3s2t + d3st2 + d3tri1 + d3tri2 + d3Thermo + d3Halo + d3Vort + d3Quad + d3Comp + d3Baro + d3ThSec + d3HaSec, nil
}
func (sw Seawater) DensityFourthDerivativeAtDepth(depth float64) (float64, error) {
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	h := 0.001
	p, _ := sw.DensityThirdDerivativeAtDepth(depth + h)
	m, _ := sw.DensityThirdDerivativeAtDepth(depth - h)
	return (p - m) / (2 * h), nil
}

func (sw Seawater) DensityFifthDerivativeAtDepth(depth float64) (float64, error) {
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	h := 0.001
	p, _ := sw.DensityFourthDerivativeAtDepth(depth + h)
	m, _ := sw.DensityFourthDerivativeAtDepth(depth - h)
	return (p - m) / (2 * h), nil
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
	quad := QuadrupleCabbelingCoeff * sAnom * sAnom * tAnom * tAnom
	comp := CompensatedLayerCoeff * pyc1 * pyc2 * sAnom
	return cab + s2t + st2 + tri1 + tri2 + quad + comp, nil
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
func (sw Seawater) SpicinessTorsionAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	expH := math.Exp(-depth / HaloclineScale)
	expT := math.Exp(-depth / ThermoclineScale)
	d3S := HaloclineDelta / (HaloclineScale * HaloclineScale * HaloclineScale) * expH
	d3T := -12.0 / (ThermoclineScale * ThermoclineScale * ThermoclineScale) * expT
	return SalinityDensityCoeff*d3S + ThermalCouplingCoeff*d3T, nil
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
	// base + quad
	c := 1449.2 + 4.6*T - 0.055*T*T + 1.34*(S-35.0) + 0.016*depth + SoundSpeedPressureQuadCoeff*depth*depth + SoundSpeedDepthCubeCoeff*depth*depth*depth + 0.01*T*(S-35.0)
	c += SoundSpeedThermoQuadCoeff * T * T * (S - 35.0)
	c += SoundSpeedSalinityQuadCoeff * T * (S - 35.0) * (S - 35.0)
	// new ultra-ultra terms
	c += BaroclinicShearCoeff * 100 * T * T * T
	c += CompensatedLayerCoeff * 10 * (S - 35.0) * (S - 35.0) * (S - 35.0)
	c += QuadrupleCabbelingCoeff * 20 * T * (S - 35.0)
	c += ThermostericSecondOrderCoeff * 1e4 * T * T
	c += HalostericSecondOrderCoeff * 1e4 * (S - 35.0) * (S - 35.0)
	c += PressureNonLinearCoeff * 100 * (P / BulkModulus * 1e3) * T
	c += PressureCubicNonLinearCoeff * 1e9 * (P / BulkModulus * 1e3) * (P / BulkModulus * 1e3) * T
	c += ThermohalineIntrusionScale * 1e-5 * depth * (P / BulkModulus * 1e3)
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
	base := 4.6*dT - 0.11*T*dT + 1.34*dS + 0.016 + 2.0*SoundSpeedPressureQuadCoeff*depth + 3.0*SoundSpeedDepthCubeCoeff*depth*depth + 0.01*dT*(S-35.0) + 0.01*T*dS
	term1 := SoundSpeedThermoQuadCoeff * (2*T*dT*(S-35.0) + T*T*dS)
	term2 := SoundSpeedSalinityQuadCoeff * (dT*(S-35.0)*(S-35.0) + T*2*(S-35.0)*dS)
	termT3 := BaroclinicShearCoeff * 100 * 3 * T * T * dT
	termS3 := CompensatedLayerCoeff * 10 * 3 * (S - 35.0) * (S - 35.0) * dS
	termTS := QuadrupleCabbelingCoeff * 20 * (dT*(S-35.0) + T*dS)
	termTQuad := ThermostericSecondOrderCoeff * 1e4 * 2 * T * dT
	termSQuad := HalostericSecondOrderCoeff * 1e4 * 2 * (S - 35.0) * dS
	termP := PressureNonLinearCoeff * 100 * ((dPdz/BulkModulus*1e3)*T + (P/BulkModulus*1e3)*dT)
	// P² T derivative
	pNorm := P / BulkModulus * 1e3
	dpNorm := dPdz / BulkModulus * 1e3
	termP2 := PressureCubicNonLinearCoeff * 1e9 * (2*pNorm*dpNorm*T + pNorm*pNorm*dT)
	termZP := ThermohalineIntrusionScale * 1e-5 * (pNorm + depth*dpNorm)
	return base + term1 + term2 + termT3 + termS3 + termTS + termTQuad + termSQuad + termP + termP2 + termZP, nil
}
func (sw Seawater) SoundSpeedCurvatureAtDepth(depth float64) (float64, error) {
	if err := sw.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	h := 0.001
	gp, _ := sw.SoundSpeedGradientAtDepth(depth + h)
	gm, _ := sw.SoundSpeedGradientAtDepth(depth - h)
	return (gp - gm) / (2 * h), nil
}

func (sw Seawater) FindSOFARAxis(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth <= 0 {
		return 0, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return 0, errors.New("tolerance must be positive")
	}
	N := 3000
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
	for iter := 0; iter < 200; iter++ {
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
	N := 3000
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
	for iter := 0; iter < 200; iter++ {
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
	N := 3000
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
	for iter := 0; iter < 200; iter++ {
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
	N := 3000
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
	for iter := 0; iter < 200; iter++ {
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
func (sw Seawater) FindThermoclineDepth(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth <= 0 {
		return 0, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return 0, errors.New("tolerance must be positive")
	}
	N := 3000
	dz := maxDepth / float64(N)
	bestG := -1e99
	bestIdx := 0
	zs := make([]float64, N+1)
	for i := 0; i <= N; i++ {
		z := float64(i) * dz
		gt, _ := sw.TemperatureGradientAtDepth(z)
		ag := math.Abs(gt)
		zs[i] = z
		if ag > bestG {
			bestG = ag
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
	for iter := 0; iter < 200; iter++ {
		if hi-lo < tolerance {
			break
		}
		m1 := lo + (hi-lo)/3.0
		m2 := hi - (hi-lo)/3.0
		g1, _ := sw.TemperatureGradientAtDepth(m1)
		g2, _ := sw.TemperatureGradientAtDepth(m2)
		if math.Abs(g1) > math.Abs(g2) {
			hi = m2
		} else {
			lo = m1
		}
	}
	return (lo + hi) / 2.0, nil
}
func (sw Seawater) FindHaloclineDepth(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth <= 0 {
		return 0, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return 0, errors.New("tolerance must be positive")
	}
	N := 3000
	dz := maxDepth / float64(N)
	bestG := -1e99
	bestIdx := 0
	zs := make([]float64, N+1)
	for i := 0; i <= N; i++ {
		z := float64(i) * dz
		g, _ := sw.SalinityGradientAtDepth(z)
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
	for iter := 0; iter < 200; iter++ {
		if hi-lo < tolerance {
			break
		}
		m1 := lo + (hi-lo)/3.0
		m2 := hi - (hi-lo)/3.0
		g1, _ := sw.SalinityGradientAtDepth(m1)
		g2, _ := sw.SalinityGradientAtDepth(m2)
		if g1 > g2 {
			hi = m2
		} else {
			lo = m1
		}
	}
	return (lo + hi) / 2.0, nil
}
func (sw Seawater) FindCompensatedLayer(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth <= 0 {
		return 0, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return 0, errors.New("tolerance must be positive")
	}
	N := 3000
	dz := maxDepth / float64(N)
	zs := make([]float64, N+1)
	comps := make([]float64, N+1)
	for i := 0; i <= N; i++ {
		z := float64(i) * dz
		zs[i] = z
		dS, _ := sw.SalinityGradientAtDepth(z)
		dT, _ := sw.TemperatureGradientAtDepth(z)
		comp := SalinityDensityCoeff*dS + ThermalCouplingCoeff*dT
		comps[i] = comp
	}
	// look for sign change of comp (density compensation)
	var brackets [][2]float64
	for i := 0; i < N; i++ {
		if comps[i]*comps[i+1] <= 0 {
			brackets = append(brackets, [2]float64{zs[i], zs[i+1]})
		}
	}
	if len(brackets) > 0 {
		lo := brackets[0][0]
		hi := brackets[0][1]
		for iter := 0; iter < 200; iter++ {
			if hi-lo < tolerance {
				break
			}
			mid := (lo + hi) / 2
			dSm, _ := sw.SalinityGradientAtDepth(mid)
			dTm, _ := sw.TemperatureGradientAtDepth(mid)
			fmid := SalinityDensityCoeff*dSm + ThermalCouplingCoeff*dTm
			dSl, _ := sw.SalinityGradientAtDepth(lo)
			dTl, _ := sw.TemperatureGradientAtDepth(lo)
			flo := SalinityDensityCoeff*dSl + ThermalCouplingCoeff*dTl
			if flo*fmid <= 0 {
				hi = mid
			} else {
				lo = mid
			}
		}
		return (lo + hi) / 2.0, nil
	}
	// otherwise find minimum absolute
	bestIdx := 0
	bestAbs := math.Abs(comps[0])
	for i := 1; i <= N; i++ {
		ab := math.Abs(comps[i])
		if ab < bestAbs {
			bestAbs = ab
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
	for iter := 0; iter < 200; iter++ {
		if hi-lo < tolerance {
			break
		}
		m1 := lo + (hi-lo)/3.0
		m2 := hi - (hi-lo)/3.0
		dS1, _ := sw.SalinityGradientAtDepth(m1)
		dT1, _ := sw.TemperatureGradientAtDepth(m1)
		dS2, _ := sw.SalinityGradientAtDepth(m2)
		dT2, _ := sw.TemperatureGradientAtDepth(m2)
		f1 := math.Abs(SalinityDensityCoeff*dS1 + ThermalCouplingCoeff*dT1)
		f2 := math.Abs(SalinityDensityCoeff*dS2 + ThermalCouplingCoeff*dT2)
		if f1 < f2 {
			hi = m2
		} else {
			lo = m1
		}
	}
	return (lo + hi) / 2.0, nil
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
	theta := T * (1.0 - x - ThermobaricCoeff*x*x - 0.2*x*x*x - 0.05*x*x*x*x)
	theta = theta * (1.0 - AdiabaticLapseRate*depth*0.001 - AdiabaticLapseRate*AdiabaticLapseRate*depth*depth*1e-7)
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
	corr := rho * g / (c * c)
	return g / rho * (grad - corr), nil
}
func (sw Seawater) BuoyancyFrequencyGradientAtDepth(depth float64, g float64) (float64, error) {
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	h := 0.001
	p, _ := sw.BuoyancyFrequencySquared(depth+h, g)
	m, _ := sw.BuoyancyFrequencySquared(depth-h, g)
	return (p - m) / (2 * h), nil
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
	// integral helpers already defined as package-level, reuse them
	// Compute integral of density vs depth
	integral := sw.Density*depth + 0.5*DepthDensityGradient*depth*depth
	integral += PycnoclineDelta * integralOneMinusExp(PycnoclineScale, depth)
	integral += DeepPycnoclineDelta * integralOneMinusExp(DeepPycnoclineScale, depth)
	integral += MidPycnoclineDelta * integralOneMinusExp(MidPycnoclineScale, depth)
	integral += SalinityDensityCoeff * HaloclineDelta * integralOneMinusExp(HaloclineScale, depth)
	integral += ThermalCouplingCoeff * 12.0 * integralOneMinusExp(ThermoclineScale, depth)
	integral += ThermalCouplingCoeff * GammaDepthFactor * 12.0 * integralZOneMinusExp(ThermoclineScale, depth)
	integral += CabbelingCoeff * HaloclineDelta * 12.0 * integralProductOneMinusExp([]float64{HaloclineScale, ThermoclineScale}, depth)
	integral += CabbelingCoeff * MidPycnoclineDelta * HaloclineDelta * integralProductOneMinusExp([]float64{MidPycnoclineScale, HaloclineScale}, depth)
	integral += CabbelingCoeff * PycnoclineDelta * HaloclineDelta * integralProductOneMinusExp([]float64{PycnoclineScale, HaloclineScale}, depth)
	integral += CabbelingCoeff * DeepPycnoclineDelta * 12.0 * integralProductOneMinusExp([]float64{DeepPycnoclineScale, ThermoclineScale}, depth)
	integral += TAnomQuadCoeff * 144.0 * integralProductOneMinusExp([]float64{ThermoclineScale, ThermoclineScale}, depth)
	integral += SAnomQuadCoeff * HaloclineDelta * HaloclineDelta * integralProductOneMinusExp([]float64{HaloclineScale, HaloclineScale}, depth)
	integral += HalostericAnomalyCoeff * 0.01 * HaloclineDelta * integralZOneMinusExp(HaloclineScale, depth)
	integral += ThermostericAnomalyCoeff * 0.01 * 12.0 * integralZOneMinusExp(ThermoclineScale, depth)
	integral += VorticityMixingCoeff * integralZOneMinusExp(DoubleDiffusiveMixingScale, depth)
	integral += SecondOrderCabbelingCoeff * HaloclineDelta * HaloclineDelta * 12.0 * integralProductOneMinusExp([]float64{HaloclineScale, HaloclineScale, ThermoclineScale}, depth)
	integral += SecondOrderCabbelingCoeff * HaloclineDelta * 144.0 * integralProductOneMinusExp([]float64{HaloclineScale, ThermoclineScale, ThermoclineScale}, depth)
	integral += TripleCabbelingCoeff * 300.0 * integralProductOneMinusExp([]float64{PycnoclineScale, HaloclineScale, ThermoclineScale}, depth)
	integral += TripleCabbelingCoeff * 135.0 * integralProductOneMinusExp([]float64{DeepPycnoclineScale, HaloclineScale, ThermoclineScale}, depth)
	// new ultra-ultra 5 terms
	integral += QuadrupleCabbelingCoeff * HaloclineDelta * HaloclineDelta * 144.0 * integralProductOneMinusExp([]float64{HaloclineScale, HaloclineScale, ThermoclineScale, ThermoclineScale}, depth)
	integral += CompensatedLayerCoeff * PycnoclineDelta * DeepPycnoclineDelta * HaloclineDelta * integralProductOneMinusExp([]float64{PycnoclineScale, DeepPycnoclineScale, HaloclineScale}, depth)
	integral += BaroclinicShearCoeff * HaloclineDelta * 12.0 * integralZProductOneMinusExp([]float64{HaloclineScale, ThermoclineScale, ThermohalineIntrusionScale}, depth)
	integral += ThermostericSecondOrderCoeff * 0.001 * 12.0 * integralZ2OneMinusExp(ThermoclineScale, depth)
	integral += HalostericSecondOrderCoeff * 0.001 * HaloclineDelta * integralZ2OneMinusExp(HaloclineScale, depth)
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
	correction := PressureNonLinearCoeff*P*P*1e-9 + PressureCubicNonLinearCoeff*P*P*P*1e-13
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
	factorExp := math.Exp(-s.HullCompressibility*pressure + PressureNonLinearCoeff*pressure*pressure*1e-12 + PressureCubicNonLinearCoeff*pressure*pressure*pressure*1e-18)
	dT := temp - 15.0
	factorThermal := 1.0 + HullThermalExpansionCoeff*dT + HullThermalExpansionQuadCoeff*dT*dT + CompensatedLayerCoeff*dT*pressure*1e-9
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
	temp, _ := fluid.TemperatureAtDepth(depth)
	dT := temp - 15.0
	denom := s.HullCompressibility - 2*PressureNonLinearCoeff*P*1e-12 - 3*PressureCubicNonLinearCoeff*P*P*1e-18 - CompensatedLayerCoeff*dT*1e-9
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
