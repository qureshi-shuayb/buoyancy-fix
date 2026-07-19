#!/bin/bash
set -euo pipefail

cat > /app/dive.go <<'GO'
package submarine

import (
	"errors"
	"math"
	"sync"
)

type DiveResult struct {
	Index                   int
	State                   string
	StateAtDepth            string
	Fraction                float64
	RequiredBallast         float64
	RequiredBallastAtDepth  float64
	IsPossible              bool
	IsPossibleAtDepth       bool
	EffectiveDensity        float64
	EffectiveDensityAtDepth float64
	NetForce                float64
	NetForceAtDepth         float64
	Acceleration            float64
	EquilibriumDepth        float64
	TerminalVelocity        float64
	TimeToDepth             float64
	MaxPressure             float64
	VolumeAtDepth           float64
	CrushRisk               bool
}

func SubmergedFraction(sub Submarine, fluid Seawater) (float64, error) {
	if err := sub.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	eff, err := sub.EffectiveDensity()
	if err != nil {
		return 0, err
	}
	frac := eff / fluid.Density
	if frac < 0 {
		return 0, nil
	}
	if frac > 1 {
		return 1, nil
	}
	return frac, nil
}

func NetVerticalForce(sub Submarine, fluid Seawater, g float64) (float64, error) {
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if err := sub.Validate(); err != nil {
		return 0, err
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	fb, err := BuoyantForce(fluid, sub, g)
	if err != nil {
		return 0, err
	}
	fw, err := WeightForce(sub, g)
	if err != nil {
		return 0, err
	}
	return fb - fw, nil
}

func VerticalAcceleration(sub Submarine, fluid Seawater, g float64) (float64, error) {
	fnet, err := NetVerticalForce(sub, fluid, g)
	if err != nil {
		return 0, err
	}
	effMass := sub.EffectiveMass()
	if effMass <= 0 {
		return 0, errors.New("mass must be positive")
	}
	return fnet / effMass, nil
}

func NetVerticalForceAtDepth(sub Submarine, fluid Seawater, depth float64, velocity float64, g float64) (float64, error) {
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
	if sub.Length <= 0 {
		return 0, errors.New("length must be positive")
	}
	area := vol / sub.Length
	if area <= 0 {
		area = sub.Volume / sub.Length
	}
	fb := rho * vol * g
	fw := sub.EffectiveMass() * g
	// drag: 0.5 * rho * Cd * A * v*|v|, upward positive convention: drag opposes velocity
	// Fnet_up = Fb - Fw - 0.5*rho*Cd*A*v*|v|
	drag := 0.0
	if sub.DragCoefficient != 0 {
		drag = 0.5 * rho * sub.DragCoefficient * area * velocity * math.Abs(velocity)
	}
	return fb - fw - drag, nil
}

func TerminalVelocity(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error) {
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
	if sub.DragCoefficient <= 0 {
		return 0, errors.New("drag coefficient must be positive for terminal velocity")
	}
	if sub.Length <= 0 {
		return 0, errors.New("length must be positive")
	}
	rho, err := fluid.DensityAtDepth(depth)
	if err != nil {
		return 0, err
	}
	vol, err := sub.VolumeAtDepth(depth, fluid, g)
	if err != nil {
		return 0, err
	}
	area := vol / sub.Length
	if area <= 0 {
		return 0, errors.New("cross-sectional area must be positive")
	}
	fb := rho * vol * g
	fw := sub.EffectiveMass() * g
	delta := fb - fw // upward positive
	if math.Abs(delta) <= 1e-12 {
		return 0, nil
	}
	denom := rho * sub.DragCoefficient * area
	if denom <= 0 {
		return 0, errors.New("drag denominator must be positive")
	}
	// |v| = sqrt(2*|delta| / (rho*Cd*A))
	mag := math.Sqrt(2 * math.Abs(delta) / denom)
	if delta > 0 {
		return mag, nil
	}
	return -mag, nil
}

func FindEquilibriumDepth(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) (float64, error) {
	if err := sub.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if g <= 0 {
		return 0, errors.New("gravity must be positive")
	}
	if maxDepth <= 0 {
		return 0, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return 0, errors.New("tolerance must be positive")
	}
	if maxDepth > sub.CrushDepth {
		return 0, errors.New("crush depth exceeded: maxDepth beyond crush depth")
	}
	// function f(z) = net force at zero velocity
	f := func(z float64) (float64, error) {
		return NetVerticalForceAtDepth(sub, fluid, z, 0, g)
	}
	f0, err := f(0)
	if err != nil {
		return 0, err
	}
	if math.Abs(f0) <= Tolerance || math.Abs(f0) <= 1e-9 {
		return 0, nil
	}
	fMax, err := f(maxDepth)
	if err != nil {
		return 0, err
	}
	// If same sign, no root
	if f0*fMax > 0 {
		return 0, errors.New("no equilibrium depth: no sign change in interval (no root)")
	}
	lo := 0.0
	hi := maxDepth
	for i := 0; i < 200; i++ {
		mid := (lo + hi) / 2
		fmid, err := f(mid)
		if err != nil {
			return 0, err
		}
		if math.Abs(fmid) <= 1e-9 || (hi-lo) < tolerance {
			return mid, nil
		}
		// determine which side contains root
		flo, _ := f(lo)
		if flo*fmid <= 0 {
			hi = mid
		} else {
			lo = mid
		}
	}
	return (lo + hi) / 2, nil
}

func TimeToDepth(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) (float64, error) {
	if err := sub.Validate(); err != nil {
		return 0, err
	}
	if err := fluid.Validate(); err != nil {
		return 0, err
	}
	if targetDepth <= 0 {
		return 0, errors.New("targetDepth must be positive")
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
	if targetDepth > sub.CrushDepth {
		return 0, errors.New("crush depth exceeded: target beyond crush")
	}
	mass := sub.EffectiveMass()
	if mass <= 0 {
		return 0, errors.New("mass must be positive")
	}
	// RK4 integration with depth positive downward, velocity positive downward
	// But our force function NetVerticalForceAtDepth returns upward positive.
	// We'll compute Fnet_down = -Fnet_up for down-positive integration.
	// For down-positive: Fnet_down = Fw - Fb - 0.5*rho*Cd*A*v*|v| where v down positive
	// Let's compute directly to avoid sign confusion.

	// helper to compute Fnet_down at given z,v_down
	fnetDown := func(z float64, vDown float64) (float64, error) {
		// vDown positive down; for up-positive force function, vUp = -vDown
		vUp := -vDown
		fUp, err := NetVerticalForceAtDepth(sub, fluid, z, vUp, g)
		if err != nil {
			return 0, err
		}
		// fUp = Fb - Fw - 0.5*rho*Cd*A*vUp|vUp|
		// Fnet_down = -fUp
		return -fUp, nil
	}

	time := 0.0
	z := 0.0
	v := 0.0 // down positive

	for time < maxTime {
		if z >= targetDepth {
			return time, nil
		}
		// RK4
		// k1
		f1, err := fnetDown(z, v)
		if err != nil {
			return 0, err
		}
		k1_z := v
		k1_v := f1 / mass

		f2, err := fnetDown(z+0.5*dt*k1_z, v+0.5*dt*k1_v)
		if err != nil {
			return 0, err
		}
		k2_z := v + 0.5*dt*k1_v
		k2_v := f2 / mass

		f3, err := fnetDown(z+0.5*dt*k2_z, v+0.5*dt*k2_v)
		if err != nil {
			return 0, err
		}
		k3_z := v + 0.5*dt*k2_v
		k3_v := f3 / mass

		f4, err := fnetDown(z+dt*k3_z, v+dt*k3_v)
		if err != nil {
			return 0, err
		}
		k4_z := v + dt*k3_v
		k4_v := f4 / mass

		zNext := z + dt/6*(k1_z+2*k2_z+2*k3_z+k4_z)
		vNext := v + dt/6*(k1_v+2*k2_v+2*k3_v+k4_v)

		// check if crossed target
		if zNext >= targetDepth {
			// linear interpolation for more accurate time
			if zNext != z {
				frac := (targetDepth - z) / (zNext - z)
				if frac < 0 {
					frac = 0
				}
				if frac > 1 {
					frac = 1
				}
				return time + frac*dt, nil
			}
			return time + dt, nil
		}
		// if sinking then floating back? Might oscillate around equilibrium
		// continue
		z = zNext
		v = vNext
		time += dt

		// safety: if depth goes negative (floats up) and never sinks, break early after some time?
		// Let it continue, will exceed maxTime
		if z < -1 && v < 0 {
			// floating up away from target
			// continue but will timeout
		}
		if z > sub.CrushDepth {
			return 0, errors.New("crush depth exceeded during dive")
		}
	}
	return 0, errors.New("target depth not reached within maxTime")
}

func AnalyzeDive(sub Submarine, fluid Seawater) (DiveResult, error) {
	if err := sub.Validate(); err != nil {
		return DiveResult{}, err
	}
	if err := fluid.Validate(); err != nil {
		return DiveResult{}, err
	}
	g := StandardGravity
	eff, err := sub.EffectiveDensity()
	if err != nil {
		return DiveResult{}, err
	}
	state, err := CheckSubmarineState(sub, fluid)
	if err != nil {
		return DiveResult{}, err
	}
	req, err := RequiredBallastForNeutral(sub, fluid)
	if err != nil {
		return DiveResult{}, err
	}
	possible, err := IsNeutralBuoyancyPossible(sub, fluid)
	if err != nil {
		return DiveResult{}, err
	}
	frac, err := SubmergedFraction(sub, fluid)
	if err != nil {
		return DiveResult{}, err
	}
	fnet, err := NetVerticalForce(sub, fluid, g)
	if err != nil {
		return DiveResult{}, err
	}
	acc, err := VerticalAcceleration(sub, fluid, g)
	if err != nil {
		return DiveResult{}, err
	}
	// depth-aware for 100m reference
	refDepth := 100.0
	if refDepth > sub.CrushDepth {
		refDepth = sub.CrushDepth * 0.9
	}
	effAtDepth, _ := sub.EffectiveDensityAtDepth(refDepth, fluid, g)
	reqAtDepth, _ := RequiredBallastForNeutralAtDepth(sub, fluid, refDepth, g)
	possAtDepth, _ := IsNeutralBuoyancyPossibleAtDepth(sub, fluid, refDepth, g)
	fnetAtDepth, _ := NetVerticalForceAtDepth(sub, fluid, refDepth, 0, g)
	stateAtDepth, _ := CheckSubmarineStateAtDepth(sub, fluid, refDepth, g)
	volAtDepth, _ := sub.VolumeAtDepth(refDepth, fluid, g)
	// equilibrium
	eqDepth := -1.0
	maxSearch := sub.CrushDepth
	if maxSearch > 2000 {
		maxSearch = 2000
	}
	if ed, err := FindEquilibriumDepth(sub, fluid, g, maxSearch, 1e-6); err == nil {
		eqDepth = ed
	}
	// terminal velocity at surface
	termVel, _ := TerminalVelocity(sub, fluid, 0, g)
	// time to 100m
	t2d := 0.0
	if timeVal, err := TimeToDepth(sub, fluid, 100, g, 0.1, 10000); err == nil {
		t2d = timeVal
	}
	// max pressure at equilibrium or 100m
	maxPress := 0.0
	if eqDepth >= 0 {
		if p, err := fluid.PressureAtDepth(eqDepth, g); err == nil {
			maxPress = p
		}
	} else {
		if p, err := fluid.PressureAtDepth(refDepth, g); err == nil {
			maxPress = p
		}
	}
	crushRisk := false
	if 100 > sub.CrushDepth {
		crushRisk = true
	}
	if eqDepth > sub.CrushDepth && eqDepth >= 0 {
		crushRisk = true
	}

	return DiveResult{
		Index:                   0,
		State:                   state,
		StateAtDepth:            stateAtDepth,
		Fraction:                frac,
		RequiredBallast:         req,
		RequiredBallastAtDepth:  reqAtDepth,
		IsPossible:              possible,
		IsPossibleAtDepth:       possAtDepth,
		EffectiveDensity:        eff,
		EffectiveDensityAtDepth: effAtDepth,
		NetForce:                fnet,
		NetForceAtDepth:         fnetAtDepth,
		Acceleration:            acc,
		EquilibriumDepth:        eqDepth,
		TerminalVelocity:        termVel,
		TimeToDepth:             t2d,
		MaxPressure:             maxPress,
		VolumeAtDepth:           volAtDepth,
		CrushRisk:               crushRisk,
	}, nil
}

func BatchAnalyzeFleet(subs []Submarine, fluid Seawater) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if subs == nil {
		return []DiveResult{}, nil
	}
	if len(subs) == 0 {
		return []DiveResult{}, nil
	}
	results := make([]DiveResult, len(subs))
	// worker pool semaphore limited to 4
	semCap := 4
	if len(subs) < semCap {
		semCap = len(subs)
	}
	sem := make(chan struct{}, semCap)
	var wg sync.WaitGroup
	for i, sub := range subs {
		wg.Add(1)
		iLocal := i
		subLocal := sub
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if err := subLocal.Validate(); err != nil {
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			}
			res, err := AnalyzeDive(subLocal, fluid)
			if err != nil {
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			}
			res.Index = iLocal
			results[iLocal] = res
		}()
	}
	wg.Wait()
	return results, nil
}

func BatchAnalyzeFleetWithTargets(subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if g <= 0 {
		return nil, errors.New("gravity must be positive")
	}
	if len(subs) != len(targetDepths) {
		return nil, errors.New("subs and targetDepths length mismatch")
	}
	if subs == nil {
		return []DiveResult{}, nil
	}
	if len(subs) == 0 {
		return []DiveResult{}, nil
	}
	results := make([]DiveResult, len(subs))
	semCap := 4
	if len(subs) < semCap {
		semCap = len(subs)
	}
	sem := make(chan struct{}, semCap)
	var wg sync.WaitGroup
	for i := range subs {
		wg.Add(1)
		iLocal := i
		subLocal := subs[iLocal]
		target := targetDepths[iLocal]
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if err := subLocal.Validate(); err != nil {
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid", CrushRisk: target > subLocal.CrushDepth}
				return
			}
			if target < 0 {
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			}
			if target > subLocal.CrushDepth {
				// still compute but mark crush risk
				res, _ := AnalyzeDive(subLocal, fluid)
				res.Index = iLocal
				res.CrushRisk = true
				res.State = "invalid"
				results[iLocal] = res
				return
			}
			res, err := AnalyzeDive(subLocal, fluid)
			if err != nil {
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			}
			// compute time to its specific target
			if t, err := TimeToDepth(subLocal, fluid, target, g, 0.1, 10000); err == nil {
				res.TimeToDepth = t
			}
			res.Index = iLocal
			// check equilibrium vs target for crush risk
			if target > subLocal.CrushDepth {
				res.CrushRisk = true
			}
			results[iLocal] = res
		}()
	}
	wg.Wait()
	return results, nil
}
GO
