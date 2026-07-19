#!/bin/bash
set -euo pipefail

cat > /app/partial.go <<'GO'
package buoyancy

import (
	"errors"
	"math"
)

type SubmersionResult struct {
	Index    int
	State    string
	Fraction float64
	Depth    float64
	Density  float64
}

type FrustumObject struct {
	Mass       float64
	BaseRadius float64
	TopRadius  float64
	Height     float64
}

type StratifiedFluid struct {
	SurfaceDensity float64
	Gradient       float64
}

func (f FrustumObject) Validate() error {
	if f.Mass <= 0 {
		return errors.New("mass must be positive")
	}
	if f.Height <= 0 {
		return errors.New("height must be positive")
	}
	if f.BaseRadius < 0 {
		return errors.New("base radius must be non-negative")
	}
	if f.TopRadius < 0 {
		return errors.New("top radius must be non-negative")
	}
	if f.BaseRadius == 0 && f.TopRadius == 0 {
		return errors.New("both radii zero degenerate")
	}
	return nil
}

func (f FrustumObject) Volume() (float64, error) {
	if err := f.Validate(); err != nil {
		return 0, err
	}
	return math.Pi * f.Height / 3.0 * (f.BaseRadius*f.BaseRadius + f.BaseRadius*f.TopRadius + f.TopRadius*f.TopRadius), nil
}

func (f FrustumObject) Density() (float64, error) {
	vol, err := f.Volume()
	if err != nil {
		return 0, err
	}
	if vol <= 0 {
		return 0, errors.New("volume must be positive")
	}
	if f.Mass <= 0 {
		return 0, errors.New("mass must be positive")
	}
	return f.Mass / vol, nil
}

func (f FrustumObject) submergedVolumeAtDepth(d float64) float64 {
	if d <= 0 {
		return 0
	}
	if d > f.Height {
		d = f.Height
	}
	rd := f.BaseRadius + (f.TopRadius-f.BaseRadius)*d/f.Height
	return math.Pi * d / 3.0 * (f.BaseRadius*f.BaseRadius + f.BaseRadius*rd + rd*rd)
}

func (s StratifiedFluid) Validate() error {
	if s.SurfaceDensity <= 0 {
		return errors.New("surface density must be positive")
	}
	if s.Gradient < 0 {
		return errors.New("gradient must be non-negative")
	}
	return nil
}

func (s StratifiedFluid) DensityAtDepth(z float64) (float64, error) {
	if err := s.Validate(); err != nil {
		return 0, err
	}
	if z < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	return s.SurfaceDensity + s.Gradient*z, nil
}

func (f FrustumObject) buoyantMassAtDepthStratified(fluid StratifiedFluid, d float64) float64 {
	if d <= 0 {
		return 0
	}
	if d > f.Height {
		d = f.Height
	}
	deltaR := f.TopRadius - f.BaseRadius
	H := f.Height
	S := fluid.SurfaceDensity
	G := fluid.Gradient
	R1 := f.BaseRadius
	term0 := S * R1 * R1 * d
	term1 := (S*2*R1*deltaR/H + G*R1*R1) * d * d / 2.0
	term2 := (S*deltaR*deltaR/(H*H) + G*2*R1*deltaR/H) * d * d * d / 3.0
	term3 := G * deltaR * deltaR / (H * H) * d * d * d * d / 4.0
	return math.Pi * (term0 + term1 + term2 + term3)
}

func buoyantMassPrismaticStratified(obj Object, fluid StratifiedFluid, d float64) float64 {
	if d <= 0 {
		return 0
	}
	if d > obj.Height {
		d = obj.Height
	}
	A := obj.Volume / obj.Height
	S := fluid.SurfaceDensity
	G := fluid.Gradient
	return A * (S*d + 0.5*G*d*d)
}

func buoyantMassConicalStratified(obj Object, fluid StratifiedFluid, d float64) float64 {
	if d <= 0 {
		return 0
	}
	if d > obj.Height {
		d = obj.Height
	}
	R2 := 3.0 * obj.Volume / (math.Pi * obj.Height)
	H := obj.Height
	S := fluid.SurfaceDensity
	G := fluid.Gradient
	return math.Pi * R2 / (H * H) * (S*d*d*d/3.0 + G*d*d*d*d/4.0)
}

func SubmergedFraction(obj Object, fluid Fluid) (float64, error) {
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
	state, err := CheckBuoyancyByDensity(density, fluid.Density)
	if err != nil {
		return 0, err
	}
	if state != "float" {
		return 1, nil
	}
	fraction := density / fluid.Density
	if fraction < 0 {
		return 0, nil
	}
	if fraction > 1 {
		return 1, nil
	}
	return fraction, nil
}

func EquilibriumDepth(obj Object, fluid Fluid) (float64, error) {
	fraction, err := SubmergedFraction(obj, fluid)
	if err != nil {
		return 0, err
	}
	if fraction >= 1 {
		return obj.Height, nil
	}
	depth := fraction * obj.Height
	if depth < 0 {
		depth = 0
	}
	if depth > obj.Height {
		depth = obj.Height
	}
	return depth, nil
}

func SubmergedFractionConical(obj Object, fluid Fluid) (float64, error) {
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
	state, err := CheckBuoyancyByDensity(density, fluid.Density)
	if err != nil {
		return 0, err
	}
	if state != "float" {
		return 1, nil
	}
	fraction := density / fluid.Density
	if fraction < 0 {
		return 0, nil
	}
	if fraction > 1 {
		return 1, nil
	}
	return fraction, nil
}

func EquilibriumDepthConical(obj Object, fluid Fluid) (float64, error) {
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
	state, err := CheckBuoyancyByDensity(density, fluid.Density)
	if err != nil {
		return 0, err
	}
	if state != "float" {
		return obj.Height, nil
	}
	fraction := density / fluid.Density
	if fraction < 0 {
		fraction = 0
	}
	if fraction > 1 {
		fraction = 1
	}
	depth := obj.Height * math.Cbrt(fraction)
	if depth < 0 {
		depth = 0
	}
	if depth > obj.Height {
		depth = obj.Height
	}
	return depth, nil
}

func AnalyzeObject(obj Object, fluid Fluid) (SubmersionResult, error) {
	if err := obj.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	if err := fluid.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	density, err := obj.Density()
	if err != nil {
		return SubmersionResult{}, err
	}
	state, err := CheckBuoyancyByDensity(density, fluid.Density)
	if err != nil {
		return SubmersionResult{}, err
	}
	fraction, err := SubmergedFraction(obj, fluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	depth, err := EquilibriumDepth(obj, fluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	return SubmersionResult{Index: 0, State: state, Fraction: fraction, Depth: depth, Density: density}, nil
}

func AnalyzeConicalObject(obj Object, fluid Fluid) (SubmersionResult, error) {
	if err := obj.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	if err := fluid.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	density, err := obj.Density()
	if err != nil {
		return SubmersionResult{}, err
	}
	state, err := CheckBuoyancyByDensity(density, fluid.Density)
	if err != nil {
		return SubmersionResult{}, err
	}
	fraction, err := SubmergedFractionConical(obj, fluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	depth, err := EquilibriumDepthConical(obj, fluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	return SubmersionResult{Index: 0, State: state, Fraction: fraction, Depth: depth, Density: density}, nil
}

func BatchAnalyze(objects []Object, fluid Fluid) ([]SubmersionResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	results := make([]SubmersionResult, len(objects))
	for i, obj := range objects {
		if err := obj.Validate(); err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res, err := AnalyzeObject(obj, fluid)
		if err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res.Index = i
		results[i] = res
	}
	return results, nil
}

func BatchAnalyzeConical(objects []Object, fluid Fluid) ([]SubmersionResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	results := make([]SubmersionResult, len(objects))
	for i, obj := range objects {
		if err := obj.Validate(); err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res, err := AnalyzeConicalObject(obj, fluid)
		if err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res.Index = i
		results[i] = res
	}
	return results, nil
}

func SubmergedFractionFrustum(obj FrustumObject, fluid Fluid) (float64, error) {
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
	state, err := CheckBuoyancyByDensity(density, fluid.Density)
	if err != nil {
		return 0, err
	}
	if state != "float" {
		return 1, nil
	}
	fraction := density / fluid.Density
	if fraction < 0 {
		return 0, nil
	}
	if fraction > 1 {
		return 1, nil
	}
	return fraction, nil
}

func EquilibriumDepthFrustum(obj FrustumObject, fluid Fluid) (float64, error) {
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
	state, err := CheckBuoyancyByDensity(density, fluid.Density)
	if err != nil {
		return 0, err
	}
	if state != "float" {
		return obj.Height, nil
	}
	fraction, err := SubmergedFractionFrustum(obj, fluid)
	if err != nil {
		return 0, err
	}
	if fraction >= 1 {
		return obj.Height, nil
	}
	volTotal, err := obj.Volume()
	if err != nil {
		return 0, err
	}
	target := fraction * volTotal
	lo := 0.0
	hi := obj.Height
	for iter := 0; iter < 80; iter++ {
		mid := (lo + hi) * 0.5
		v := obj.submergedVolumeAtDepth(mid)
		if v < target {
			lo = mid
		} else {
			hi = mid
		}
	}
	depth := (lo + hi) * 0.5
	if depth < 0 {
		depth = 0
	}
	if depth > obj.Height {
		depth = obj.Height
	}
	return depth, nil
}

func AnalyzeFrustumObject(obj FrustumObject, fluid Fluid) (SubmersionResult, error) {
	if err := obj.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	if err := fluid.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	density, err := obj.Density()
	if err != nil {
		return SubmersionResult{}, err
	}
	state, err := CheckBuoyancyByDensity(density, fluid.Density)
	if err != nil {
		return SubmersionResult{}, err
	}
	fraction, err := SubmergedFractionFrustum(obj, fluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	depth, err := EquilibriumDepthFrustum(obj, fluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	return SubmersionResult{Index: 0, State: state, Fraction: fraction, Depth: depth, Density: density}, nil
}

func BatchAnalyzeFrustum(objects []FrustumObject, fluid Fluid) ([]SubmersionResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	results := make([]SubmersionResult, len(objects))
	for i, obj := range objects {
		if err := obj.Validate(); err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res, err := AnalyzeFrustumObject(obj, fluid)
		if err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res.Index = i
		results[i] = res
	}
	return results, nil
}

func EquilibriumDepthStratified(obj Object, fluid StratifiedFluid) (float64, error) {
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
	bmFull := buoyantMassPrismaticStratified(obj, fluid, obj.Height)
	if bmFull <= 0 {
		return 0, errors.New("buoyant mass must be positive")
	}
	avgFluid := bmFull / obj.Volume
	state, err := CheckBuoyancyByDensity(density, avgFluid)
	if err != nil {
		return 0, err
	}
	if state != "float" {
		return obj.Height, nil
	}
	lo := 0.0
	hi := obj.Height
	for i := 0; i < 100; i++ {
		mid := (lo + hi) * 0.5
		bm := buoyantMassPrismaticStratified(obj, fluid, mid)
		if bm < obj.Mass {
			lo = mid
		} else {
			hi = mid
		}
	}
	depth := (lo + hi) * 0.5
	if depth < 0 {
		depth = 0
	}
	if depth > obj.Height {
		depth = obj.Height
	}
	return depth, nil
}

func EquilibriumDepthConicalStratified(obj Object, fluid StratifiedFluid) (float64, error) {
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
	bmFull := buoyantMassConicalStratified(obj, fluid, obj.Height)
	if bmFull <= 0 {
		return 0, errors.New("buoyant mass must be positive")
	}
	avgFluid := bmFull / obj.Volume
	state, err := CheckBuoyancyByDensity(density, avgFluid)
	if err != nil {
		return 0, err
	}
	if state != "float" {
		return obj.Height, nil
	}
	lo := 0.0
	hi := obj.Height
	for i := 0; i < 100; i++ {
		mid := (lo + hi) * 0.5
		bm := buoyantMassConicalStratified(obj, fluid, mid)
		if bm < obj.Mass {
			lo = mid
		} else {
			hi = mid
		}
	}
	depth := (lo + hi) * 0.5
	if depth < 0 {
		depth = 0
	}
	if depth > obj.Height {
		depth = obj.Height
	}
	return depth, nil
}

func EquilibriumDepthFrustumStratified(obj FrustumObject, fluid StratifiedFluid) (float64, error) {
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
	bmFull := obj.buoyantMassAtDepthStratified(fluid, obj.Height)
	if bmFull <= 0 {
		return 0, errors.New("buoyant mass must be positive")
	}
	vol, err := obj.Volume()
	if err != nil {
		return 0, err
	}
	avgFluid := bmFull / vol
	state, err := CheckBuoyancyByDensity(density, avgFluid)
	if err != nil {
		return 0, err
	}
	if state != "float" {
		return obj.Height, nil
	}
	lo := 0.0
	hi := obj.Height
	for i := 0; i < 100; i++ {
		mid := (lo + hi) * 0.5
		bm := obj.buoyantMassAtDepthStratified(fluid, mid)
		if bm < obj.Mass {
			lo = mid
		} else {
			hi = mid
		}
	}
	depth := (lo + hi) * 0.5
	if depth < 0 {
		depth = 0
	}
	if depth > obj.Height {
		depth = obj.Height
	}
	return depth, nil
}

func AnalyzeStratifiedObject(obj Object, fluid StratifiedFluid) (SubmersionResult, error) {
	if err := obj.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	if err := fluid.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	density, err := obj.Density()
	if err != nil {
		return SubmersionResult{}, err
	}
	bmFull := buoyantMassPrismaticStratified(obj, fluid, obj.Height)
	if bmFull <= 0 {
		return SubmersionResult{}, errors.New("buoyant mass must be positive")
	}
	avgFluid := bmFull / obj.Volume
	state, err := CheckBuoyancyByDensity(density, avgFluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	fraction := obj.Mass / bmFull
	if fraction < 0 {
		fraction = 0
	}
	if fraction > 1 {
		fraction = 1
	}
	depth, err := EquilibriumDepthStratified(obj, fluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	return SubmersionResult{Index: 0, State: state, Fraction: fraction, Depth: depth, Density: density}, nil
}

func AnalyzeConicalStratifiedObject(obj Object, fluid StratifiedFluid) (SubmersionResult, error) {
	if err := obj.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	if err := fluid.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	density, err := obj.Density()
	if err != nil {
		return SubmersionResult{}, err
	}
	bmFull := buoyantMassConicalStratified(obj, fluid, obj.Height)
	if bmFull <= 0 {
		return SubmersionResult{}, errors.New("buoyant mass must be positive")
	}
	avgFluid := bmFull / obj.Volume
	state, err := CheckBuoyancyByDensity(density, avgFluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	fraction := obj.Mass / bmFull
	if fraction < 0 {
		fraction = 0
	}
	if fraction > 1 {
		fraction = 1
	}
	depth, err := EquilibriumDepthConicalStratified(obj, fluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	return SubmersionResult{Index: 0, State: state, Fraction: fraction, Depth: depth, Density: density}, nil
}

func AnalyzeFrustumStratifiedObject(obj FrustumObject, fluid StratifiedFluid) (SubmersionResult, error) {
	if err := obj.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	if err := fluid.Validate(); err != nil {
		return SubmersionResult{}, err
	}
	density, err := obj.Density()
	if err != nil {
		return SubmersionResult{}, err
	}
	bmFull := obj.buoyantMassAtDepthStratified(fluid, obj.Height)
	if bmFull <= 0 {
		return SubmersionResult{}, errors.New("buoyant mass must be positive")
	}
	vol, err := obj.Volume()
	if err != nil {
		return SubmersionResult{}, err
	}
	avgFluid := bmFull / vol
	state, err := CheckBuoyancyByDensity(density, avgFluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	fraction := obj.Mass / bmFull
	if fraction < 0 {
		fraction = 0
	}
	if fraction > 1 {
		fraction = 1
	}
	depth, err := EquilibriumDepthFrustumStratified(obj, fluid)
	if err != nil {
		return SubmersionResult{}, err
	}
	return SubmersionResult{Index: 0, State: state, Fraction: fraction, Depth: depth, Density: density}, nil
}

func BatchAnalyzeStratified(objects []Object, fluid StratifiedFluid) ([]SubmersionResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	results := make([]SubmersionResult, len(objects))
	for i, obj := range objects {
		if err := obj.Validate(); err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res, err := AnalyzeStratifiedObject(obj, fluid)
		if err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res.Index = i
		results[i] = res
	}
	return results, nil
}

func BatchAnalyzeConicalStratified(objects []Object, fluid StratifiedFluid) ([]SubmersionResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	results := make([]SubmersionResult, len(objects))
	for i, obj := range objects {
		if err := obj.Validate(); err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res, err := AnalyzeConicalStratifiedObject(obj, fluid)
		if err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res.Index = i
		results[i] = res
	}
	return results, nil
}

func BatchAnalyzeFrustumStratified(objects []FrustumObject, fluid StratifiedFluid) ([]SubmersionResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	results := make([]SubmersionResult, len(objects))
	for i, obj := range objects {
		if err := obj.Validate(); err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res, err := AnalyzeFrustumStratifiedObject(obj, fluid)
		if err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		res.Index = i
		results[i] = res
	}
	return results, nil
}
GO
cat > /app/dive.go <<'GO'
package buoyancy

import (
	"errors"
	"math"
	"sync"
)

const MinimumVolumeFraction = 0.1

type CompressibleObject struct {
	Mass               float64
	Volume0            float64
	Height             float64
	BulkModulus        float64
	DragCoefficient    float64
	CrushDepth         float64
	MinVolumeFraction  float64
}

type DiveResult struct {
	Index            int
	State            string
	EquilibriumDepth float64
	TerminalVelocity float64
	TimeToDepth      float64
	VolumeAtDepth    float64
	MaxPressure      float64
	CrushRisk        bool
}

func (c CompressibleObject) Validate() error {
	if c.Mass <= 0 {
		return errors.New("mass must be positive")
	}
	if c.Volume0 <= 0 {
		return errors.New("volume0 must be positive")
	}
	if c.Height <= 0 {
		return errors.New("height must be positive")
	}
	if c.BulkModulus <= 0 {
		return errors.New("bulk modulus must be positive")
	}
	if c.DragCoefficient < 0 {
		return errors.New("drag coefficient must be non-negative")
	}
	if c.CrushDepth <= 0 {
		return errors.New("crush depth must be positive")
	}
	if c.MinVolumeFraction <= 0 || c.MinVolumeFraction >= 1 {
		return errors.New("min volume fraction must be in (0,1)")
	}
	return nil
}

func PressureAtDepth(fluid StratifiedFluid, depth, g float64) (float64, error) {
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	return g * (fluid.SurfaceDensity*depth + 0.5*fluid.Gradient*depth*depth), nil
}

func VolumeAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, g float64) (float64, error) {
	if err := obj.Validate(); err != nil {
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
	if depth > obj.CrushDepth {
		return 0, errors.New("crush depth exceeded")
	}
	pressure, err := PressureAtDepth(fluid, depth, g)
	if err != nil {
		return 0, err
	}
	fMin := obj.MinVolumeFraction
	if fMin <= 0 {
		fMin = MinimumVolumeFraction
	}
	vol := obj.Volume0 * (1 - pressure/obj.BulkModulus)
	minVol := obj.Volume0 * fMin
	if vol < minVol {
		vol = minVol
	}
	if vol <= 0 {
		vol = minVol
	}
	return vol, nil
}

func BuoyantForceAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, g float64) (float64, error) {
	if err := obj.Validate(); err != nil {
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
	rho, err := fluid.DensityAtDepth(depth)
	if err != nil {
		return 0, err
	}
	vol, err := VolumeAtDepth(obj, fluid, depth, g)
	if err != nil {
		return 0, err
	}
	return rho * vol * g, nil
}

func NetForceAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, vel, g float64) (float64, error) {
	if err := obj.Validate(); err != nil {
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
	fw := obj.Mass * g
	fb, err := BuoyantForceAtDepth(obj, fluid, depth, g)
	if err != nil {
		return 0, err
	}
	rho, err := fluid.DensityAtDepth(depth)
	if err != nil {
		return 0, err
	}
	vol, err := VolumeAtDepth(obj, fluid, depth, g)
	if err != nil {
		return 0, err
	}
	Ad := vol / obj.Height
	if Ad <= 0 {
		Ad = 0.01
	}
	fd := 0.5 * rho * obj.DragCoefficient * Ad * vel * math.Abs(vel)
	return fw - fb - fd, nil
}

func TerminalVelocityAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, g float64) (float64, error) {
	if err := obj.Validate(); err != nil {
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
	if obj.DragCoefficient <= 0 {
		return 0, errors.New("drag coefficient must be positive for terminal velocity")
	}
	rho, err := fluid.DensityAtDepth(depth)
	if err != nil {
		return 0, err
	}
	vol, err := VolumeAtDepth(obj, fluid, depth, g)
	if err != nil {
		return 0, err
	}
	Ad := vol / obj.Height
	if Ad <= 0 {
		return 0, errors.New("reference area must be positive")
	}
	fw := obj.Mass * g
	fb := rho * vol * g
	fnet := fw - fb
	if math.Abs(fnet) < 1e-12 {
		return 0, nil
	}
	v := math.Sqrt(2*math.Abs(fnet)/(rho*obj.DragCoefficient*Ad))
	if fnet < 0 {
		v = -v
	}
	return v, nil
}

func FindEquilibriumDepth(obj CompressibleObject, fluid StratifiedFluid, g, maxDepth, tol float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	if maxDepth <= 0 {
		return 0, errors.New("max depth must be positive")
	}
	if tol <= 0 {
		return 0, errors.New("tol must be positive")
	}
	if maxDepth > obj.CrushDepth {
		maxDepth = obj.CrushDepth
	}
	f := func(z float64) float64 {
		rho, _ := fluid.DensityAtDepth(z)
		vol, _ := VolumeAtDepth(obj, fluid, z, g)
		return obj.Mass - rho*vol
	}
	f0 := f(0)
	fMax := f(maxDepth)
	if f0 <= 0 {
		return 0, nil
	}
	if fMax > 0 {
		return maxDepth, nil
	}
	lo := 0.0
	hi := maxDepth
	for i := 0; i < 100; i++ {
		mid := (lo + hi) * 0.5
		fm := f(mid)
		if math.Abs(fm) < tol {
			return mid, nil
		}
		if fm > 0 {
			lo = mid
		} else {
			hi = mid
		}
	}
	return (lo + hi) * 0.5, nil
}

func TimeToDepthRK4(obj CompressibleObject, fluid StratifiedFluid, targetDepth, g, dt, maxTime float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if targetDepth <= 0 {
		return 0, errors.New("target depth must be positive")
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	if dt <= 0 {
		return 0, errors.New("dt must be positive")
	}
	if maxTime <= 0 {
		return 0, errors.New("maxTime must be positive")
	}
	if targetDepth > obj.CrushDepth {
		return 0, errors.New("crush depth exceeded: target beyond crush")
	}
	t := 0.0
	z := 0.0
	v := 0.0
	prevT := t
	prevZ := z
	for t < maxTime {
		if z >= targetDepth {
			if z == prevZ {
				return t, nil
			}
			frac := (targetDepth - prevZ) / (z - prevZ)
			return prevT + frac*dt, nil
		}
		if z > obj.CrushDepth {
			return 0, errors.New("crush depth exceeded during integration")
		}
		fb, err := BuoyantForceAtDepth(obj, fluid, z, g)
		if err != nil {
			return 0, err
		}
		_ = fb
		rho, err := fluid.DensityAtDepth(z)
		if err != nil {
			return 0, err
		}
		vol, err := VolumeAtDepth(obj, fluid, z, g)
		if err != nil {
			return 0, err
		}
		Ad := vol / obj.Height
		if Ad <= 0 {
			Ad = 0.01
		}
		// RK4
		net1, err := NetForceAtDepth(obj, fluid, z, v, g)
		if err != nil {
			return 0, err
		}
		k1z := v
		k1v := net1 / obj.Mass

		z2 := z + 0.5*dt*k1z
		v2 := v + 0.5*dt*k1v
		net2, err := NetForceAtDepth(obj, fluid, z2, v2, g)
		if err != nil {
			return 0, err
		}
		k2z := v + 0.5*dt*k1v
		k2v := net2 / obj.Mass

		z3 := z + 0.5*dt*k2z
		v3 := v + 0.5*dt*k2v
		net3, err := NetForceAtDepth(obj, fluid, z3, v3, g)
		if err != nil {
			return 0, err
		}
		k3z := v + 0.5*dt*k2v
		k3v := net3 / obj.Mass

		z4 := z + dt*k3z
		v4 := v + dt*k3v
		net4, err := NetForceAtDepth(obj, fluid, z4, v4, g)
		if err != nil {
			return 0, err
		}
		k4z := v + dt*k3v
		k4v := net4 / obj.Mass

		prevT = t
		prevZ = z

		z += dt / 6.0 * (k1z + 2*k2z + 2*k3z + k4z)
		v += dt / 6.0 * (k1v + 2*k2v + 2*k3v + k4v)
		t += dt

		if z < 0 {
			z = 0
			v = 0
		}

		// If velocity becomes significantly negative and we're still far from target and moving upward, unreachable
		if v < -0.01 && z < targetDepth*0.5 && t > 1.0 {
			// Check if net force upward at current depth
			nf, _ := NetForceAtDepth(obj, fluid, z, v, g)
			if nf < 0 {
				// floating up, won't reach deeper target
				// but continue a bit in case it was initial transient
				if z < prevZ && prevZ < targetDepth {
					// if already past max depth before and now going up, unreachable
				}
			}
		}

		_ = rho
		_ = Ad
	}
	if z >= targetDepth {
		frac := (targetDepth - prevZ) / (z - prevZ)
		if z != prevZ {
			return prevT + frac*dt, nil
		}
		return t, nil
	}
	return 0, errors.New("target depth not reached within maxTime")
}

func BatchFindEquilibrium(objs []CompressibleObject, fluid StratifiedFluid, g, maxDepth, tol float64) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if g <= 0 {
		return nil, errors.New("gravity must be positive")
	}
	if maxDepth <= 0 {
		return nil, errors.New("max depth must be positive")
	}
	if tol <= 0 {
		return nil, errors.New("tol must be positive")
	}
	results := make([]DiveResult, len(objs))
	for i, obj := range objs {
		if err := obj.Validate(); err != nil {
			results[i] = DiveResult{Index: i, State: "invalid"}
			continue
		}
		depth, err := FindEquilibriumDepth(obj, fluid, g, maxDepth, tol)
		if err != nil {
			if errors.Is(err, errors.New("crush")) || containsIgnoreCase(err.Error(), "crush") {
				results[i] = DiveResult{Index: i, State: "crush", EquilibriumDepth: depth, CrushRisk: true}
			} else {
				results[i] = DiveResult{Index: i, State: "invalid"}
			}
			continue
		}
		vol, _ := VolumeAtDepth(obj, fluid, depth, g)
		press, _ := PressureAtDepth(fluid, depth, g)
		term, _ := TerminalVelocityAtDepth(obj, fluid, depth, g)
		crush := depth >= obj.CrushDepth*0.9
		state := "sink"
		// Determine float/neutral/sink based on mass vs buoyant at depth 0 and maxDepth
		rho0, _ := fluid.DensityAtDepth(0)
		if obj.Mass < rho0*obj.Volume0 {
			// check if it would float at surface, but equilibrium may be 0
			if depth <= tol {
				state = "float"
			} else {
				state = "float"
			}
		} else {
			// if depth == maxDepth and still heavy, sink, else neutral if close
			if math.Abs(depth-maxDepth) < 1e-6 {
				// check if close to neutral
				state = "sink"
			} else {
				state = "neutral"
			}
		}
		if crush {
			state = "crush"
		}
		results[i] = DiveResult{Index: i, State: state, EquilibriumDepth: depth, TerminalVelocity: term, VolumeAtDepth: vol, MaxPressure: press, CrushRisk: crush}
	}
	return results, nil
}

func containsIgnoreCase(s, substr string) bool {
	// simple case-insensitive contains
	ls := ""
	for _, c := range s {
		if c >= 'A' && c <= 'Z' {
			ls += string(c + 32)
		} else {
			ls += string(c)
		}
	}
	lsub := ""
	for _, c := range substr {
		if c >= 'A' && c <= 'Z' {
			lsub += string(c + 32)
		} else {
			lsub += string(c)
		}
	}
	return len(ls) >= len(lsub) && (func() bool {
		for i := 0; i <= len(ls)-len(lsub); i++ {
			if ls[i:i+len(lsub)] == lsub {
				return true
			}
		}
		return false
	})()
}

func BatchTimeToDepthConcurrent(objs []CompressibleObject, fluid StratifiedFluid, targets []float64, g, dt, maxTime float64) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if g <= 0 {
		return nil, errors.New("gravity must be positive")
	}
	if dt <= 0 {
		return nil, errors.New("dt must be positive")
	}
	if maxTime <= 0 {
		return nil, errors.New("maxTime must be positive")
	}
	if len(objs) != len(targets) {
		return nil, errors.New("objects and targets length mismatch")
	}
	results := make([]DiveResult, len(objs))
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := range objs {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			obj := objs[idx]
			target := targets[idx]
			if err := obj.Validate(); err != nil {
				mu.Lock()
				results[idx] = DiveResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			if target <= 0 {
				mu.Lock()
				results[idx] = DiveResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			if target > obj.CrushDepth {
				mu.Lock()
				results[idx] = DiveResult{Index: idx, State: "crush", CrushRisk: true}
				mu.Unlock()
				return
			}
			tm, err := TimeToDepthRK4(obj, fluid, target, g, dt, maxTime)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				if containsIgnoreCase(err.Error(), "crush") {
					results[idx] = DiveResult{Index: idx, State: "crush", CrushRisk: true}
				} else {
					results[idx] = DiveResult{Index: idx, State: "invalid"}
				}
				return
			}
			vol, _ := VolumeAtDepth(obj, fluid, target, g)
			press, _ := PressureAtDepth(fluid, target, g)
			term, _ := TerminalVelocityAtDepth(obj, fluid, target, g)
			results[idx] = DiveResult{Index: idx, State: "sink", TimeToDepth: tm, VolumeAtDepth: vol, MaxPressure: press, TerminalVelocity: term, EquilibriumDepth: target, CrushRisk: target >= obj.CrushDepth*0.9}
		}(i)
	}
	wg.Wait()
	return results, nil
}
GO
