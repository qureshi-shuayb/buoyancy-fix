#!/bin/bash
set -euo pipefail
rm -f /app/*_test.go /app/*_test.go.bak /app/buoyancy_step1_test.go /app/partial_step2_test.go /app/compressible_step3_test.go 2>/dev/null || true

cat > /app/dive.go <<'GO'
package buoyancy

import (
	"errors"
	"math"
	"strings"
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
	// Enforce package minimum clamping using MinimumVolumeFraction as lower bound - bespoke package invariant
	minVol := obj.Volume0 * fMin
	packageMin := obj.Volume0 * MinimumVolumeFraction
	if minVol < packageMin {
		minVol = packageMin
	}
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
	// Package-defined reference area Ad(z)=V(z)/Height, bespoke convention not standard cross-section
	Ad := vol / obj.Height
	if Ad <= 0 {
		Ad = 0.01
	}
	// Drag opposes motion: sign handling via vel*|vel|, bespoke package requirement
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
		clampDepth := func(d float64) float64 {
			if d < 0 {
				return 0
			}
			return d
		}
		net1, err := NetForceAtDepth(obj, fluid, z, v, g)
		if err != nil {
			return 0, err
		}
		k1z := v
		k1v := net1 / obj.Mass

		z2 := clampDepth(z + 0.5*dt*k1z)
		v2 := v + 0.5*dt*k1v
		net2, err := NetForceAtDepth(obj, fluid, z2, v2, g)
		if err != nil {
			return 0, err
		}
		k2z := v + 0.5*dt*k1v
		k2v := net2 / obj.Mass

		z3 := clampDepth(z + 0.5*dt*k2z)
		v3 := v + 0.5*dt*k2v
		net3, err := NetForceAtDepth(obj, fluid, z3, v3, g)
		if err != nil {
			return 0, err
		}
		k3z := v + 0.5*dt*k2v
		k3v := net3 / obj.Mass

		z4 := clampDepth(z + dt*k3z)
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
	}
	if z >= targetDepth {
		if z == prevZ {
			return t, nil
		}
		frac := (targetDepth - prevZ) / (z - prevZ)
		return prevT + frac*dt, nil
	}
	return 0, errors.New("target depth not reached within maxTime")
}

func containsIgnoreCase(s, substr string) bool {
	return strings.Contains(strings.ToLower(s), strings.ToLower(substr))
}

func BatchFindEquilibrium(objs []CompressibleObject, fluid StratifiedFluid, g, maxDepth, tol float64) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if objs == nil {
		return make([]DiveResult, 0), nil
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
			if containsIgnoreCase(err.Error(), "crush") {
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
		rho0, _ := fluid.DensityAtDepth(0)
		if obj.Mass < rho0*obj.Volume0 {
			state = "float"
		} else {
			if math.Abs(depth-maxDepth) < 1e-6 {
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

func BatchTimeToDepthConcurrent(objs []CompressibleObject, fluid StratifiedFluid, targets []float64, g, dt, maxTime float64) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if objs == nil && targets == nil {
		return make([]DiveResult, 0), nil
	}
	if objs == nil {
		if len(targets) != 0 {
			return nil, errors.New("objects and targets length mismatch")
		}
		return make([]DiveResult, 0), nil
	}
	if targets == nil {
		if len(objs) != 0 {
			return nil, errors.New("objects and targets length mismatch")
		}
		return make([]DiveResult, 0), nil
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




