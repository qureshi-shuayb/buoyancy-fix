#!/bin/bash
set -euo pipefail

cat > /app/dive.go <<'GO'
package submarine

import (
	"context"
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

type EquilibriumPoint struct {
	Depth  float64
	Stable bool
	FPrime float64
}

func CdFromRe(re float64) float64 {
	if re < 1e-6 {
		return 1.2
	}
	// Clift-Gauvin base
	base := 24.0/re*(1+0.15*math.Pow(re, 0.687)) + 0.42/(1+42500*math.Pow(re, -1.16))
	crisis := 0.2 + 0.8/(1+math.Exp((re-3e5)/4e4))
	cd := base * crisis
	if cd > 1.2 {
		cd = 1.2
	}
	if cd < 0.08 {
		cd = 0.08
	}
	_ = math.Sqrt(re)
	return cd
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
	re := rho * math.Abs(velocity) * sub.Length / SeawaterViscosity
	cd := CdFromRe(re)
	drag := 0.0
	if cd != 0 {
		drag = 0.5 * rho * cd * area * velocity * math.Abs(velocity)
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
	delta := fb - fw
	if math.Abs(delta) <= 1e-12 {
		return 0, nil
	}
	absDelta := math.Abs(delta)
	_ = math.Sqrt(absDelta)

	dragMag := func(vMag float64) float64 {
		re := rho * vMag * sub.Length / SeawaterViscosity
		cd := CdFromRe(re)
		return 0.5 * rho * cd * area * vMag * vMag
	}

	lo := 0.0
	hi := 1.0
	for hi < 1e6 {
		if dragMag(hi) >= absDelta {
			break
		}
		hi *= 2
	}
	if hi >= 1e6 && dragMag(hi) < absDelta {
		return 0, errors.New("unable to find terminal velocity upper bound")
	}

	// scanning for all roots due to crisis dip
	N := 2000
	dv := hi / float64(N)
	var brackets [][2]float64
	prevV := 0.0
	prevH := dragMag(prevV) - absDelta
	for i := 1; i <= N; i++ {
		curV := float64(i) * dv
		curH := dragMag(curV) - absDelta
		if prevH*curH <= 0 {
			brackets = append(brackets, [2]float64{prevV, curV})
		}
		prevV = curV
		prevH = curH
	}
	if len(brackets) == 0 {
		// fallback bisection over [lo,hi]
		brackets = append(brackets, [2]float64{lo, hi})
	}
	var roots []float64
	for _, br := range brackets {
		l := br[0]
		h := br[1]
		for iter := 0; iter < 200; iter++ {
			mid := (l + h) / 2
			d := dragMag(mid)
			diff := d - absDelta
			if math.Abs(diff) <= 1e-9 || (h-l) < 1e-9 {
				isDup := false
				for _, r := range roots {
					if math.Abs(r-mid) <= 1e-6 {
						isDup = true
						break
					}
				}
				if !isDup {
					roots = append(roots, mid)
				}
				break
			}
			if dragMag(l)-absDelta < 0 && d-absDelta < 0 {
				// both negative, need upper
				if (dragMag(l)-absDelta)*(d-absDelta) <= 0 {
					h = mid
				} else {
					// actually drag - absDelta increasing overall but may dip, handle by moving lo
					// For scanning we already have bracket, so use sign
					if dragMag(l) < absDelta && d < absDelta {
						l = mid
					} else if dragMag(l) > absDelta && d > absDelta {
						h = mid
					} else {
						if d < absDelta {
							l = mid
						} else {
							h = mid
						}
					}
				}
			} else {
				if d < absDelta {
					l = mid
				} else {
					h = mid
				}
			}
		}
	}
	if len(roots) == 0 {
		return 0, errors.New("no terminal velocity root found")
	}
	// sort roots ascending
	for i := 0; i < len(roots); i++ {
		for j := i + 1; j < len(roots); j++ {
			if roots[j] < roots[i] {
				roots[i], roots[j] = roots[j], roots[i]
			}
		}
	}
	vMag := roots[0] // smallest magnitude
	if delta > 0 {
		return vMag, nil
	}
	return -vMag, nil
}

func FindEquilibriumDepth(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) (float64, error) {
	roots, err := FindEquilibriumDepths(sub, fluid, g, maxDepth, tolerance)
	if err != nil {
		return 0, err
	}
	if len(roots) == 0 {
		return 0, errors.New("no equilibrium depth: no sign change")
	}
	return roots[0], nil
}

func FindEquilibriumDepths(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]float64, error) {
	pts, err := FindEquilibriumDepthsWithStability(sub, fluid, g, maxDepth, tolerance)
	if err != nil {
		return nil, err
	}
	if len(pts) == 0 {
		return nil, errors.New("no equilibrium depth: no sign change")
	}
	out := make([]float64, len(pts))
	for i, p := range pts {
		out[i] = p.Depth
	}
	return out, nil
}

func FindEquilibriumDepthsWithStability(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]EquilibriumPoint, error) {
	if err := sub.Validate(); err != nil {
		return nil, err
	}
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if g <= 0 {
		return nil, errors.New("gravity must be positive")
	}
	if maxDepth <= 0 {
		return nil, errors.New("maxDepth must be positive")
	}
	if tolerance <= 0 {
		return nil, errors.New("tolerance must be positive")
	}
	if maxDepth > sub.CrushDepth {
		return nil, errors.New("crush depth exceeded: maxDepth beyond crush depth")
	}
	f := func(z float64) (float64, error) {
		return NetVerticalForceAtDepth(sub, fluid, z, 0, g)
	}
	f0, err := f(0)
	if err != nil {
		return nil, err
	}
	_ = f0

	N := 2000
	dz := maxDepth / float64(N)
	zs := make([]float64, N+1)
	fs := make([]float64, N+1)
	for i := 0; i <= N; i++ {
		z := float64(i) * dz
		zs[i] = z
		val, err := f(z)
		if err != nil {
			return nil, err
		}
		fs[i] = val
	}
	var brackets [][2]float64
	for i := 0; i < N; i++ {
		if math.Abs(fs[i]) <= 1e-12 {
			brackets = append(brackets, [2]float64{zs[i], zs[i]})
			continue
		}
		if fs[i]*fs[i+1] <= 0 {
			brackets = append(brackets, [2]float64{zs[i], zs[i+1]})
		}
	}
	// handle near zero at surface already included via loop

	var roots []EquilibriumPoint
	for _, br := range brackets {
		lo := br[0]
		hi := br[1]
		if lo == hi {
			fval, _ := f(lo)
			// stability derivative
			delta := 0.1
			fPlus, _ := f(lo + delta)
			fMinus, _ := f(lo - delta)
			if lo < delta {
				fMinus = fPlus
			}
			dFdZ := (fPlus - fMinus) / (2 * delta)
			stable := dFdZ > 0
			isDup := false
			for _, r := range roots {
				if math.Abs(r.Depth-lo) <= tolerance*10 {
					isDup = true
					break
				}
			}
			if !isDup {
				roots = append(roots, EquilibriumPoint{Depth: lo, Stable: stable, FPrime: dFdZ})
				_ = fval
			}
			continue
		}
		fLo, _ := f(lo)
		var mid float64
		for iter := 0; iter < 200; iter++ {
			mid = (lo + hi) / 2
			fmid, _ := f(mid)
			if math.Abs(fmid) <= 1e-9 || (hi-lo) < tolerance {
				break
			}
			if fLo*fmid <= 0 {
				hi = mid
			} else {
				lo = mid
				fLo = fmid
			}
		}
		// compute stability
		delta := 0.1
		fPlus, _ := f(mid + delta)
		fMinus, _ := f(mid - delta)
		if mid < delta {
			fMinus, _ = f(mid)
			fPlus, _ = f(mid + delta)
			// forward diff
		}
		dFdZ := (fPlus - fMinus) / (2 * delta)
		stable := dFdZ > 0

		isDup := false
		for _, r := range roots {
			if math.Abs(r.Depth-mid) <= tolerance*10 || math.Abs(r.Depth-mid) <= 1e-6 {
				isDup = true
				break
			}
		}
		if !isDup {
			roots = append(roots, EquilibriumPoint{Depth: mid, Stable: stable, FPrime: dFdZ})
		}
	}
	if len(roots) == 0 {
		return nil, errors.New("no equilibrium depth: no sign change")
	}
	// sort by depth
	for i := 0; i < len(roots); i++ {
		for j := i + 1; j < len(roots); j++ {
			if roots[j].Depth < roots[i].Depth {
				roots[i], roots[j] = roots[j], roots[i]
			}
		}
	}
	return roots, nil
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

	// helper to compute Fnet_down and m_total at given z, v_down
	fnetDown := func(z float64, vDown float64) (float64, float64, error) {
		// vDown positive down, vUp = -vDown
		vUp := -vDown
		// compute rho, vol, area, Cd, drag via NetVerticalForceAtDepth logic but we need m_total too
		rho, err := fluid.DensityAtDepth(z)
		if err != nil {
			return 0, 0, err
		}
		vol, err := sub.VolumeAtDepth(z, fluid, g)
		if err != nil {
			return 0, 0, err
		}
		if sub.Length <= 0 {
			return 0, 0, errors.New("length must be positive")
		}
		area := vol / sub.Length
		re := rho * math.Abs(vUp) * sub.Length / SeawaterViscosity
		cd := CdFromRe(re)
		fb := rho * vol * g
		fw := mass * g
		dragDown := 0.5 * rho * cd * area * vDown * math.Abs(vDown)
		fnet := fw - fb - dragDown
		mTot := mass + 0.5*rho*vol
		_ = math.Exp(-rho*1e-9)
		return fnet, mTot, nil
	}

	time := 0.0
	z := 0.0
	v := 0.0

	_ = context.Background()

	dtCurrent := dt
	atol := 1e-6

	for time < maxTime {
		if z >= targetDepth {
			return time, nil
		}
		// RK4 full step
		computeStep := func(z0, v0, dtt float64) (float64, float64, error) {
			f1, m1, err := fnetDown(z0, v0)
			if err != nil {
				return 0, 0, err
			}
			k1_z := v0
			k1_v := f1 / m1

			f2, m2, err := fnetDown(z0+0.5*dtt*k1_z, v0+0.5*dtt*k1_v)
			if err != nil {
				return 0, 0, err
			}
			k2_z := v0 + 0.5*dtt*k1_v
			k2_v := f2 / m2

			f3, m3, err := fnetDown(z0+0.5*dtt*k2_z, v0+0.5*dtt*k2_v)
			if err != nil {
				return 0, 0, err
			}
			k3_z := v0 + 0.5*dtt*k2_v
			k3_v := f3 / m3

			f4, m4, err := fnetDown(z0+dtt*k3_z, v0+dtt*k3_v)
			if err != nil {
				return 0, 0, err
			}
			k4_z := v0 + dtt*k3_v
			k4_v := f4 / m4

			zNext := z0 + dtt/6*(k1_z+2*k2_z+2*k3_z+k4_z)
			vNext := v0 + dtt/6*(k1_v+2*k2_v+2*k3_v+k4_v)
			return zNext, vNext, nil
		}

		z1, v1, err := computeStep(z, v, dtCurrent)
		if err != nil {
			return 0, err
		}
		zm, vm, err := computeStep(z, v, dtCurrent/2)
		if err != nil {
			return 0, err
		}
		z2, v2, err := computeStep(zm, vm, dtCurrent/2)
		if err != nil {
			return 0, err
		}
		errEst := math.Abs(z2-z1) + math.Abs(v2-v1)
		if errEst > atol {
			dtCurrent /= 2
			if dtCurrent < 1e-9 {
				return 0, errors.New("dt too small")
			}
			continue
		}
		// check crossing
		if z2 >= targetDepth {
			if z2 != z {
				frac := (targetDepth - z) / (z2 - z)
				if frac < 0 {
					frac = 0
				}
				if frac > 1 {
					frac = 1
				}
				return time + frac*dtCurrent, nil
			}
			return time + dtCurrent, nil
		}
		z = z2
		v = v2
		time += dtCurrent

		if z > sub.CrushDepth {
			return 0, errors.New("crush depth exceeded during dive")
		}
		if errEst < atol/4 {
			dtCurrent *= 2
			if dtCurrent > dt*2 {
				dtCurrent = dt * 2
			}
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

	eqDepth := -1.0
	maxSearch := sub.CrushDepth
	if maxSearch > 2000 {
		maxSearch = 2000
	}
	if ed, err := FindEquilibriumDepth(sub, fluid, g, maxSearch, 1e-6); err == nil {
		eqDepth = ed
	}

	termVel, _ := TerminalVelocity(sub, fluid, 0, g)

	t2d := 0.0
	if timeVal, err := TimeToDepth(sub, fluid, 100, g, 0.1, 10000); err == nil {
		t2d = timeVal
	}

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
	sem := make(chan struct{}, 4)
	var wg sync.WaitGroup
	ctx := context.Background()
	_ = ctx

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
	sem := make(chan struct{}, 4)
	var wg sync.WaitGroup
	ctx := context.Background()
	_ = ctx

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
			if t, err := TimeToDepth(subLocal, fluid, target, g, 0.1, 10000); err == nil {
				res.TimeToDepth = t
			}
			res.Index = iLocal
			results[iLocal] = res
		}()
	}
	wg.Wait()
	return results, nil
}

func BatchAnalyzeFleetWithContext(ctx context.Context, subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if g <= 0 {
		return nil, errors.New("gravity must be positive")
	}
	if len(subs) != len(targetDepths) {
		return nil, errors.New("subs and targetDepths length mismatch")
	}
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if subs == nil {
		return []DiveResult{}, nil
	}
	if len(subs) == 0 {
		return []DiveResult{}, nil
	}
	results := make([]DiveResult, len(subs))
	sem := make(chan struct{}, 4)
	var wg sync.WaitGroup

	for i := range subs {
		wg.Add(1)
		iLocal := i
		subLocal := subs[iLocal]
		target := targetDepths[iLocal]
		go func() {
			defer wg.Done()
			select {
			case <-ctx.Done():
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			case sem <- struct{}{}:
			}
			defer func() { <-sem }()

			select {
			case <-ctx.Done():
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			default:
			}

			if err := subLocal.Validate(); err != nil {
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid", CrushRisk: target > subLocal.CrushDepth}
				return
			}
			if target < 0 {
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			}
			if target > subLocal.CrushDepth {
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
			if t, err := TimeToDepth(subLocal, fluid, target, g, 0.1, 10000); err == nil {
				res.TimeToDepth = t
			}
			res.Index = iLocal
			results[iLocal] = res
		}()
	}
	wg.Wait()
	if err := ctx.Err(); err != nil {
		return results, err
	}
	return results, nil
}
GO
