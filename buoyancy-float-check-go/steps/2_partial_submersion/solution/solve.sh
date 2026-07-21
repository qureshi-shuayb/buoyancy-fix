#!/bin/bash
set -euo pipefail
rm -f /app/*_test.go /app/*_test.go.bak /app/buoyancy_step1_test.go /app/partial_step2_test.go /app/compressible_step3_test.go 2>/dev/null || true

cat > /app/partial.go <<'GO'
package buoyancy

import (
	"errors"
	"math"
	"sync"
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

// New exported BuoyantMass functions - super hard, expose polynomial directly

func BuoyantMass(obj Object, fluid StratifiedFluid, d float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if d < 0 || math.IsNaN(d) || math.IsInf(d, 0) {
		return 0, errors.New("depth must be non-negative")
	}
	bm := buoyantMassPrismaticStratified(obj, fluid, d)
	if math.IsInf(bm, 0) || math.IsNaN(bm) {
		return 0, errors.New("buoyant mass overflow")
	}
	return bm, nil
}

func BuoyantMassConical(obj Object, fluid StratifiedFluid, d float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if d < 0 || math.IsNaN(d) || math.IsInf(d, 0) {
		return 0, errors.New("depth must be non-negative")
	}
	bm := buoyantMassConicalStratified(obj, fluid, d)
	if math.IsInf(bm, 0) || math.IsNaN(bm) {
		return 0, errors.New("buoyant mass overflow")
	}
	return bm, nil
}

func (f FrustumObject) BuoyantMass(fluid StratifiedFluid, d float64) (float64, error) {
	if err := f.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if d < 0 || math.IsNaN(d) || math.IsInf(d, 0) {
		return 0, errors.New("depth must be non-negative")
	}
	bm := f.buoyantMassAtDepthStratified(fluid, d)
	if math.IsInf(bm, 0) || math.IsNaN(bm) {
		return 0, errors.New("buoyant mass overflow")
	}
	return bm, nil
}


func SubmergedVolumeAtDepthFrustum(obj FrustumObject, d float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if d < 0 || math.IsNaN(d) || math.IsInf(d, 0) {
		return 0, errors.New("depth must be non-negative")
	}
	if d > obj.Height {
		d = obj.Height
	}
	rd := obj.BaseRadius + (obj.TopRadius-obj.BaseRadius)*d/obj.Height
	vol := math.Pi * d / 3.0 * (obj.BaseRadius*obj.BaseRadius + obj.BaseRadius*rd + rd*rd)
	if math.IsInf(vol, 0) || math.IsNaN(vol) {
		return 0, errors.New("radius and depth cause volume overflow")
	}
	return vol, nil
}

func WaterlineAreaAtDepthFrustum(obj FrustumObject, d float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if d < 0 || math.IsNaN(d) || math.IsInf(d, 0) {
		return 0, errors.New("depth must be non-negative")
	}
	if d > obj.Height {
		d = obj.Height
	}
	rd := obj.BaseRadius + (obj.TopRadius-obj.BaseRadius)*d/obj.Height
	area := math.Pi * rd * rd
	if math.IsInf(area, 0) || math.IsNaN(area) {
		return 0, errors.New("radius and depth cause area overflow")
	}
	return area, nil
}

func EquilibriumDepthStratifiedWithTol(obj Object, fluid StratifiedFluid, tol float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if tol <= 0 || math.IsNaN(tol) || math.IsInf(tol, 0) {
		return 0, errors.New("tol must be positive")
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
		if hi-lo < tol {
			break
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
	if objects == nil {
		return make([]SubmersionResult, 0), nil
	}
	results := make([]SubmersionResult, len(objects))
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := range objects {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			obj := objects[idx]
			if err := obj.Validate(); err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res, err := AnalyzeObject(obj, fluid)
			if err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res.Index = idx
			mu.Lock()
			results[idx] = res
			mu.Unlock()
		}(i)
	}
	wg.Wait()
	return results, nil
}

func BatchAnalyzeConical(objects []Object, fluid Fluid) ([]SubmersionResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if objects == nil {
		return make([]SubmersionResult, 0), nil
	}
	results := make([]SubmersionResult, len(objects))
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := range objects {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			obj := objects[idx]
			if err := obj.Validate(); err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res, err := AnalyzeConicalObject(obj, fluid)
			if err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res.Index = idx
			mu.Lock()
			results[idx] = res
			mu.Unlock()
		}(i)
	}
	wg.Wait()
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
	if objects == nil {
		return make([]SubmersionResult, 0), nil
	}
	results := make([]SubmersionResult, len(objects))
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := range objects {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			obj := objects[idx]
			if err := obj.Validate(); err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res, err := AnalyzeFrustumObject(obj, fluid)
			if err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res.Index = idx
			mu.Lock()
			results[idx] = res
			mu.Unlock()
		}(i)
	}
	wg.Wait()
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
	if objects == nil {
		return make([]SubmersionResult, 0), nil
	}
	results := make([]SubmersionResult, len(objects))
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := range objects {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			obj := objects[idx]
			if err := obj.Validate(); err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res, err := AnalyzeStratifiedObject(obj, fluid)
			if err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res.Index = idx
			mu.Lock()
			results[idx] = res
			mu.Unlock()
		}(i)
	}
	wg.Wait()
	return results, nil
}

func BatchAnalyzeConicalStratified(objects []Object, fluid StratifiedFluid) ([]SubmersionResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if objects == nil {
		return make([]SubmersionResult, 0), nil
	}
	results := make([]SubmersionResult, len(objects))
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := range objects {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			obj := objects[idx]
			if err := obj.Validate(); err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res, err := AnalyzeConicalStratifiedObject(obj, fluid)
			if err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res.Index = idx
			mu.Lock()
			results[idx] = res
			mu.Unlock()
		}(i)
	}
	wg.Wait()
	return results, nil
}

func BatchAnalyzeFrustumStratified(objects []FrustumObject, fluid StratifiedFluid) ([]SubmersionResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if objects == nil {
		return make([]SubmersionResult, 0), nil
	}
	results := make([]SubmersionResult, len(objects))
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := range objects {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			obj := objects[idx]
			if err := obj.Validate(); err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res, err := AnalyzeFrustumStratifiedObject(obj, fluid)
			if err != nil {
				mu.Lock()
				results[idx] = SubmersionResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			res.Index = idx
			mu.Lock()
			results[idx] = res
			mu.Unlock()
		}(i)
	}
	wg.Wait()
	return results, nil
}

GO
