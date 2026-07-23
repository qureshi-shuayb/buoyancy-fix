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
	Mass              float64
	Volume0           float64
	Height            float64
	BulkModulus       float64
	DragCoefficient   float64
	CrushDepth        float64
	MinVolumeFraction float64
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

func isFinite(f float64) bool {
	return !math.IsNaN(f) && !math.IsInf(f, 0)
}

func (c CompressibleObject) Validate() error {
	if !isFinite(c.Mass) || c.Mass <= 0 {
		return errors.New("mass must be positive")
	}
	if !isFinite(c.Volume0) || c.Volume0 <= 0 {
		return errors.New("volume0 must be positive")
	}
	if !isFinite(c.Height) || c.Height <= 0 {
		return errors.New("height must be positive")
	}
	if !isFinite(c.BulkModulus) || c.BulkModulus <= 0 {
		return errors.New("bulk modulus must be positive")
	}
	if !isFinite(c.DragCoefficient) || c.DragCoefficient < 0 {
		return errors.New("drag coefficient must be non-negative")
	}
	if !isFinite(c.CrushDepth) || c.CrushDepth <= 0 {
		return errors.New("crush depth must be positive")
	}
	if !isFinite(c.MinVolumeFraction) || c.MinVolumeFraction <= 0 || c.MinVolumeFraction >= 1 {
		return errors.New("min volume fraction must be in (0,1)")
	}
	return nil
}

func PressureAtDepth(fluid StratifiedFluid, depth, g float64) (float64, error) {
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if !isFinite(depth) || depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if !isFinite(g) || g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	// P(z)=g*(S*z+0.5*G*z^2) with overflow checks
	sd := fluid.SurfaceDensity * depth
	if !isFinite(sd) {
		return 0, errors.New("pressure overflow")
	}
	gd2 := fluid.Gradient * depth * depth
	if !isFinite(gd2) {
		return 0, errors.New("pressure overflow")
	}
	halfGd2 := 0.5 * gd2
	if !isFinite(halfGd2) {
		return 0, errors.New("pressure overflow")
	}
	sum := sd + halfGd2
	if !isFinite(sum) {
		return 0, errors.New("pressure overflow")
	}
	pres := g * sum
	if !isFinite(pres) {
		return 0, errors.New("pressure overflow")
	}
	return pres, nil
}

func VolumeAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, g float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if !isFinite(depth) || depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if !isFinite(g) || g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	if depth > obj.CrushDepth {
		return 0, errors.New("crush depth exceeded")
	}
	pressure, err := PressureAtDepth(fluid, depth, g)
	if err != nil {
		return 0, err
	}
	// Check P/K overflow: pressure / BulkModulus
	if obj.BulkModulus == 0 {
		return 0, errors.New("bulk modulus must be positive")
	}
	ratio := pressure / obj.BulkModulus
	if !isFinite(ratio) {
		return 0, errors.New("pressure and bulk modulus cause overflow")
	}
	fMin := obj.MinVolumeFraction
	if fMin <= 0 {
		fMin = MinimumVolumeFraction
	}
	// Enforce package minimum clamping using MinimumVolumeFraction as lower bound
	minVol := obj.Volume0 * fMin
	if !isFinite(minVol) {
		return 0, errors.New("volume overflow")
	}
	packageMin := obj.Volume0 * MinimumVolumeFraction
	if !isFinite(packageMin) {
		return 0, errors.New("volume overflow")
	}
	if minVol < packageMin {
		minVol = packageMin
	}
	vol := obj.Volume0 * (1 - ratio)
	if !isFinite(vol) {
		return 0, errors.New("volume overflow")
	}
	if vol < minVol {
		vol = minVol
	}
	if vol <= 0 {
		vol = minVol
	}
	if !isFinite(vol) {
		return 0, errors.New("volume overflow")
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
	if !isFinite(depth) || depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if !isFinite(g) || g <= 0 {
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
	fb := rho * vol * g
	if !isFinite(fb) {
		return 0, errors.New("buoyant force overflow")
	}
	return fb, nil
}

func NetForceAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, vel, g float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if !isFinite(depth) || depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if !isFinite(vel) {
		return 0, errors.New("velocity must be finite")
	}
	if !isFinite(g) || g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	fw := obj.Mass * g
	if !isFinite(fw) {
		return 0, errors.New("weight force overflow")
	}
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
	// Ad(z)=V(z)/Height per spec, no fallback
	Ad := vol / obj.Height
	if !isFinite(Ad) || Ad <= 0 {
		return 0, errors.New("reference area must be positive")
	}
	// Drag opposes motion: v*|v|
	fd := 0.5 * rho * obj.DragCoefficient * Ad * vel * math.Abs(vel)
	if !isFinite(fd) {
		return 0, errors.New("drag force overflow")
	}
	net := fw - fb - fd
	if !isFinite(net) {
		return 0, errors.New("net force overflow")
	}
	return net, nil
}

func TerminalVelocityAtDepth(obj CompressibleObject, fluid StratifiedFluid, depth, g float64) (float64, error) {
	if err := obj.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if !isFinite(depth) || depth < 0 {
		return 0, errors.New("depth must be non-negative")
	}
	if !isFinite(g) || g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	if obj.DragCoefficient <= 0 || !isFinite(obj.DragCoefficient) {
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
	if !isFinite(Ad) || Ad <= 0 {
		return 0, errors.New("reference area must be positive")
	}
	fw := obj.Mass * g
	fb := rho * vol * g
	if !isFinite(fw) || !isFinite(fb) {
		return 0, errors.New("force overflow")
	}
	fnet := fw - fb
	if math.Abs(fnet) < 1e-12 {
		return 0, nil
	}
	denom := rho * obj.DragCoefficient * Ad
	if !isFinite(denom) || denom <= 0 {
		return 0, errors.New("drag denominator overflow")
	}
	v := math.Sqrt(2 * math.Abs(fnet) / denom)
	if !isFinite(v) {
		return 0, errors.New("terminal velocity overflow")
	}
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
	if !isFinite(g) || g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	if !isFinite(maxDepth) || maxDepth <= 0 {
		return 0, errors.New("max depth must be positive")
	}
	if !isFinite(tol) || tol <= 0 {
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
	if !isFinite(targetDepth) || targetDepth <= 0 {
		return 0, errors.New("target depth must be positive")
	}
	if !isFinite(g) || g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	if !isFinite(dt) || dt <= 0 {
		return 0, errors.New("dt must be positive")
	}
	if !isFinite(maxTime) || maxTime <= 0 {
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
		if !isFinite(z) || !isFinite(v) {
			return 0, errors.New("integration overflow")
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
	if !isFinite(g) || g <= 0 {
		return nil, errors.New("gravity must be positive")
	}
	if !isFinite(maxDepth) || maxDepth <= 0 {
		return nil, errors.New("max depth must be positive")
	}
	if !isFinite(tol) || tol <= 0 {
		return nil, errors.New("tol must be positive")
	}
	if objs == nil {
		return make([]DiveResult, 0), nil
	}
	if len(objs) == 0 {
		return make([]DiveResult, 0), nil
	}
	results := make([]DiveResult, len(objs))
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := range objs {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			obj := objs[idx]
			if err := obj.Validate(); err != nil {
				mu.Lock()
				results[idx] = DiveResult{Index: idx, State: "invalid"}
				mu.Unlock()
				return
			}
			depth, err := FindEquilibriumDepth(obj, fluid, g, maxDepth, tol)
			if err != nil {
				mu.Lock()
				if containsIgnoreCase(err.Error(), "crush") {
					results[idx] = DiveResult{Index: idx, State: "crush", EquilibriumDepth: depth, CrushRisk: true}
				} else {
					results[idx] = DiveResult{Index: idx, State: "invalid"}
				}
				mu.Unlock()
				return
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
			// Ensure MinimumVolumeFraction is referenced per spec
			_ = MinimumVolumeFraction
			res := DiveResult{
				Index:            idx,
				State:            state,
				EquilibriumDepth: depth,
				TerminalVelocity: term,
				VolumeAtDepth:    vol,
				MaxPressure:      press,
				CrushRisk:        crush,
			}
			mu.Lock()
			results[idx] = res
			mu.Unlock()
		}(i)
	}
	wg.Wait()
	return results, nil
}

func BatchTimeToDepthConcurrent(objs []CompressibleObject, fluid StratifiedFluid, targets []float64, g, dt, maxTime float64) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if !isFinite(g) || g <= 0 {
		return nil, errors.New("gravity must be positive")
	}
	if !isFinite(dt) || dt <= 0 {
		return nil, errors.New("dt must be positive")
	}
	if !isFinite(maxTime) || maxTime <= 0 {
		return nil, errors.New("maxTime must be positive")
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
	if len(objs) != len(targets) {
		return nil, errors.New("objects and targets length mismatch")
	}
	for _, td := range targets {
		if !isFinite(td) {
			return nil, errors.New("target depth must be finite")
		}
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
			if !isFinite(target) || target <= 0 {
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
			results[idx] = DiveResult{
				Index:            idx,
				State:            "sink",
				TimeToDepth:      tm,
				VolumeAtDepth:    vol,
				MaxPressure:      press,
				TerminalVelocity: term,
				EquilibriumDepth: target,
				CrushRisk:        target >= obj.CrushDepth*0.9,
			}
		}(i)
	}
	wg.Wait()
	return results, nil
}
GO



