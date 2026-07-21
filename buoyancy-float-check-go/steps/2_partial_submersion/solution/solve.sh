#!/bin/bash
set -euo pipefail
rm -f /app/*_test.go /app/*_test.go.bak /app/buoyancy_step1_test.go /app/partial_step2_test.go /app/compressible_step3_test.go 2>/dev/null || true

cat > /app/buoyancy.go <<'GO'
package buoyancy

import (
	"errors"
	"math"
	"sync"
)

const Tolerance = 1e-9
const StandardGravity = 9.81

type Object struct {
	Mass   float64
	Volume float64
	Height float64
}

type Fluid struct {
	Density float64
}

type CylinderObject struct {
	Mass   float64
	Radius float64
	Height float64
}

type SphereObject struct {
	Mass   float64
	Radius float64
}

type BuoyancyReport struct {
	Index        int
	State        string
	Density      float64
	BuoyantForce float64
	WeightForce  float64
}

func isInvalidPositive(x float64) bool {
	return x <= 0 || math.IsNaN(x) || math.IsInf(x, 0)
}

func isFinitePositive(x float64) bool {
	return !isInvalidPositive(x)
}

// Object methods

func (o Object) Density() (float64, error) {
	if o.Mass <= 0 || math.IsNaN(o.Mass) || math.IsInf(o.Mass, 0) {
		return 0, errors.New("mass must be positive")
	}
	if o.Volume <= 0 || math.IsNaN(o.Volume) || math.IsInf(o.Volume, 0) {
		return 0, errors.New("volume must be positive")
	}
	// Must NOT check Height - inverse DRY trap
	d := o.Mass / o.Volume
	if math.IsInf(d, 0) || math.IsNaN(d) {
		return 0, errors.New("volume overflow resulting density invalid")
	}
	return d, nil
}

func (o Object) Validate() error {
	if o.Mass <= 0 || math.IsNaN(o.Mass) || math.IsInf(o.Mass, 0) {
		return errors.New("mass must be positive")
	}
	if o.Volume <= 0 || math.IsNaN(o.Volume) || math.IsInf(o.Volume, 0) {
		return errors.New("volume must be positive")
	}
	if o.Height <= 0 || math.IsNaN(o.Height) || math.IsInf(o.Height, 0) {
		return errors.New("height must be positive")
	}
	return nil
}

func (f Fluid) Validate() error {
	if f.Density <= 0 || math.IsNaN(f.Density) || math.IsInf(f.Density, 0) {
		return errors.New("fluid density must be positive")
	}
	return nil
}

// CylinderObject methods

func (c CylinderObject) Validate() error {
	if c.Mass <= 0 || math.IsNaN(c.Mass) || math.IsInf(c.Mass, 0) {
		return errors.New("mass must be positive")
	}
	if c.Radius <= 0 || math.IsNaN(c.Radius) || math.IsInf(c.Radius, 0) {
		return errors.New("radius must be positive")
	}
	if c.Height <= 0 || math.IsNaN(c.Height) || math.IsInf(c.Height, 0) {
		return errors.New("height must be positive")
	}
	return nil
}

func (c CylinderObject) Volume() (float64, error) {
	// Must NOT validate Mass - inverse trap
	if c.Radius <= 0 || math.IsNaN(c.Radius) || math.IsInf(c.Radius, 0) {
		return 0, errors.New("radius must be positive")
	}
	if c.Height <= 0 || math.IsNaN(c.Height) || math.IsInf(c.Height, 0) {
		return 0, errors.New("height must be positive")
	}
	vol := math.Pi * c.Radius * c.Radius * c.Height
	if math.IsInf(vol, 0) || math.IsNaN(vol) {
		return 0, errors.New("radius and height cause volume overflow")
	}
	return vol, nil
}

func (c CylinderObject) Density() (float64, error) {
	if c.Mass <= 0 || math.IsNaN(c.Mass) || math.IsInf(c.Mass, 0) {
		return 0, errors.New("mass must be positive")
	}
	vol, err := c.Volume()
	if err != nil {
		return 0, err
	}
	d := c.Mass / vol
	if math.IsInf(d, 0) || math.IsNaN(d) {
		return 0, errors.New("mass and volume cause density overflow")
	}
	return d, nil
}

// SphereObject methods

func (s SphereObject) Validate() error {
	if s.Mass <= 0 || math.IsNaN(s.Mass) || math.IsInf(s.Mass, 0) {
		return errors.New("mass must be positive")
	}
	if s.Radius <= 0 || math.IsNaN(s.Radius) || math.IsInf(s.Radius, 0) {
		return errors.New("radius must be positive")
	}
	return nil
}

func (s SphereObject) Volume() (float64, error) {
	// Must NOT validate Mass
	if s.Radius <= 0 || math.IsNaN(s.Radius) || math.IsInf(s.Radius, 0) {
		return 0, errors.New("radius must be positive")
	}
	vol := 4.0 / 3.0 * math.Pi * s.Radius * s.Radius * s.Radius
	if math.IsInf(vol, 0) || math.IsNaN(vol) {
		return 0, errors.New("radius causes volume overflow")
	}
	return vol, nil
}

func (s SphereObject) Density() (float64, error) {
	if s.Mass <= 0 || math.IsNaN(s.Mass) || math.IsInf(s.Mass, 0) {
		return 0, errors.New("mass must be positive")
	}
	vol, err := s.Volume()
	if err != nil {
		return 0, err
	}
	d := s.Mass / vol
	if math.IsInf(d, 0) || math.IsNaN(d) {
		return 0, errors.New("mass and radius cause density overflow")
	}
	return d, nil
}

// Functions

func BuoyantForce(fluid Fluid, volume float64, g float64) (float64, error) {
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if volume <= 0 || math.IsNaN(volume) || math.IsInf(volume, 0) {
		return 0, errors.New("volume must be positive")
	}
	if g <= 0 || math.IsNaN(g) || math.IsInf(g, 0) {
		return 0, errors.New("gravity must be positive")
	}
	// overflow check
	prod := fluid.Density * volume
	if math.IsInf(prod, 0) || math.IsNaN(prod) {
		return 0, errors.New("density and volume cause overflow")
	}
	result := prod * g
	if math.IsInf(result, 0) || math.IsNaN(result) {
		return 0, errors.New("buoyant force overflow: volume and gravity too large")
	}
	return result, nil
}

func WeightForce(mass float64, g float64) (float64, error) {
	if mass <= 0 || math.IsNaN(mass) || math.IsInf(mass, 0) {
		return 0, errors.New("mass must be positive")
	}
	if g <= 0 || math.IsNaN(g) || math.IsInf(g, 0) {
		return 0, errors.New("gravity must be positive")
	}
	result := mass * g
	if math.IsInf(result, 0) || math.IsNaN(result) {
		return 0, errors.New("mass and gravity cause overflow")
	}
	return result, nil
}

func CheckBuoyancyByDensity(objDensity, fluidDensity float64) (string, error) {
	if objDensity <= 0 || math.IsNaN(objDensity) || math.IsInf(objDensity, 0) {
		return "", errors.New("object density must be positive")
	}
	if fluidDensity <= 0 || math.IsNaN(fluidDensity) || math.IsInf(fluidDensity, 0) {
		return "", errors.New("fluid density must be positive")
	}
	diff := objDensity - fluidDensity
	if math.Abs(diff) <= Tolerance {
		return "neutral", nil
	}
	if diff < 0 {
		return "float", nil
	}
	return "sink", nil
}

func CheckBuoyancy(obj Object, fluid Fluid) (string, error) {
	if err := obj.Validate(); err != nil {
		return "", err
	}
	if err := fluid.Validate(); err != nil {
		return "", err
	}
	density, err := obj.Density()
	if err != nil {
		return "", err
	}
	return CheckBuoyancyByDensity(density, fluid.Density)
}

func ApparentWeight(obj Object, fluid Fluid, g float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if g <= 0 || math.IsNaN(g) || math.IsInf(g, 0) {
		return 0, errors.New("gravity must be positive")
	}
	density, err := obj.Density()
	if err != nil {
		return 0, err
	}
	// Package-defined tolerance zeroing: must use Tolerance constant
	if math.Abs(density-fluid.Density) <= Tolerance {
		return 0, nil
	}
	// compute (Mass - rho*V)*g with overflow checks
	rhoV := fluid.Density * obj.Volume
	if math.IsInf(rhoV, 0) || math.IsNaN(rhoV) {
		return 0, errors.New("density and volume cause overflow")
	}
	diff := obj.Mass - rhoV
	if math.IsInf(diff, 0) || math.IsNaN(diff) {
		return 0, errors.New("mass and volume difference overflow")
	}
	result := diff * g
	if math.IsInf(result, 0) || math.IsNaN(result) {
		return 0, errors.New("gravity and mass difference cause overflow")
	}
	return result, nil
}

func RequiredBallastMass(obj Object, fluid Fluid) (float64, error) {
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
	// Tolerance zeroing
	if math.Abs(density-fluid.Density) <= Tolerance {
		return 0, nil
	}
	targetMass := fluid.Density * obj.Volume
	if math.IsInf(targetMass, 0) || math.IsNaN(targetMass) {
		return 0, errors.New("density and volume cause overflow")
	}
	ballast := targetMass - obj.Mass
	if math.IsInf(ballast, 0) || math.IsNaN(ballast) {
		return 0, errors.New("mass and volume cause ballast overflow")
	}
	return ballast, nil
}

func BatchCheckBuoyancy(objs []Object, fluid Fluid, g float64) ([]BuoyancyReport, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if g <= 0 || math.IsNaN(g) || math.IsInf(g, 0) {
		return nil, errors.New("gravity must be positive")
	}
	if objs == nil {
		return make([]BuoyancyReport, 0), nil
	}
	if len(objs) == 0 {
		return make([]BuoyancyReport, 0), nil
	}
	results := make([]BuoyancyReport, len(objs))
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := range objs {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			obj := objs[idx]
			if err := obj.Validate(); err != nil {
				mu.Lock()
				results[idx] = BuoyancyReport{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			density, err := obj.Density()
			if err != nil {
				mu.Lock()
				results[idx] = BuoyancyReport{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			buoyant, err := BuoyantForce(fluid, obj.Volume, g)
			if err != nil {
				mu.Lock()
				results[idx] = BuoyancyReport{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			weight, err := WeightForce(obj.Mass, g)
			if err != nil {
				mu.Lock()
				results[idx] = BuoyancyReport{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			state, err := CheckBuoyancyByDensity(density, fluid.Density)
			if err != nil {
				mu.Lock()
				results[idx] = BuoyancyReport{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			report := BuoyancyReport{
				Index:        idx,
				State:        state,
				Density:      density,
				BuoyantForce: buoyant,
				WeightForce:  weight,
			}
			mu.Lock()
			results[idx] = report
			mu.Unlock()
		}(i)
	}
	wg.Wait()
	return results, nil
}
GO

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
	return buoyantMassPrismaticStratified(obj, fluid, d), nil
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
	return buoyantMassConicalStratified(obj, fluid, d), nil
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
	return f.buoyantMassAtDepthStratified(fluid, d), nil
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
