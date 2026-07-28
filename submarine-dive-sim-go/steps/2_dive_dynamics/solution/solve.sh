#!/bin/bash
set -euo pipefail
cat > /app/dive.go <<'GO'
package submarine

import (
	"container/heap"
	"context"
	"errors"
	"math"
	"sync"
	"sync/atomic"
)

type DiveResult struct {
	Index int; State string; StateAtDepth string; Fraction float64; RequiredBallast float64; RequiredBallastAtDepth float64; IsPossible bool; IsPossibleAtDepth bool; EffectiveDensity float64; EffectiveDensityAtDepth float64; NetForce float64; NetForceAtDepth float64; Acceleration float64; EquilibriumDepth float64; TerminalVelocity float64; TimeToDepth float64; MaxPressure float64; VolumeAtDepth float64; CrushRisk bool
}
type EquilibriumPoint struct { Depth float64; Stable bool; FPrime float64 }
type DiveState struct { Time float64; Depth float64; Velocity float64; Acceleration float64; Pressure float64 }

// 5-pt table eased from 10-pt for 5/10 target
var reTable = []float64{1e3, 1e4, 1e5, 1e6, 5e6}
var cdTable = []float64{1.44, 1.2, 0.7, 0.2, 0.12}

func CdFromRe(re float64) float64 {
	if re <= reTable[0] { return cdTable[0] }
	if re >= reTable[len(reTable)-1] { return cdTable[len(cdTable)-1] }
	logRe := math.Log10(re)
	for i := 0; i < len(reTable)-1; i++ {
		if re >= reTable[i] && re < reTable[i+1] {
			logRi := math.Log10(reTable[i])
			logRnext := math.Log10(reTable[i+1])
			if logRnext == logRi { return cdTable[i] }
			t := (logRe - logRi) / (logRnext - logRi)
			return cdTable[i] + t*(cdTable[i+1]-cdTable[i])
		}
	}
	return cdTable[len(cdTable)-1]
}
func SubmergedFraction(sub Submarine, fluid Seawater) (float64, error) {
	if err := sub.Validate(); err != nil { return 0, err }
	if err := fluid.Validate(); err != nil { return 0, err }
	eff, _ := sub.EffectiveDensity()
	frac := eff / fluid.Density
	if frac < 0 { return 0, nil }
	if frac > 1 { return 1, nil }
	return frac, nil
}
func NetVerticalForce(sub Submarine, fluid Seawater, g float64) (float64, error) {
	if err := fluid.Validate(); err != nil { return 0, err }
	if err := sub.Validate(); err != nil { return 0, err }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	fb, _ := BuoyantForce(fluid, sub, g)
	fw, _ := WeightForce(sub, g)
	return fb - fw, nil
}
func VerticalAcceleration(sub Submarine, fluid Seawater, g float64) (float64, error) {
	fnet, _ := NetVerticalForce(sub, fluid, g)
	return fnet / sub.EffectiveMass(), nil
}
func NetVerticalForceAtDepth(sub Submarine, fluid Seawater, depth float64, velocity float64, g float64) (float64, error) {
	if err := sub.Validate(); err != nil { return 0, err }
	if err := fluid.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	if depth > sub.CrushDepth { return 0, errors.New("crush depth exceeded") }
	rho, _ := fluid.DensityAtDepth(depth)
	vol, _ := sub.VolumeAtDepth(depth, fluid, g)
	area := vol / sub.Length
	fb := rho * vol * g
	fw := sub.EffectiveMass() * g
	re := rho * math.Abs(velocity) * sub.Length / 0.001
	cd := CdFromRe(re)
	drag := 0.5 * rho * cd * area * velocity * math.Abs(velocity)
	return fb - fw - drag, nil
}
func TerminalVelocity(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error) {
	if err := sub.Validate(); err != nil { return 0, err }
	if err := fluid.Validate(); err != nil { return 0, err }
	if depth < 0 { return 0, errors.New("depth must be non-negative") }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	if depth > sub.CrushDepth { return 0, errors.New("crush depth exceeded") }
	if sub.DragCoefficient <= 0 { return 0, errors.New("drag coefficient must be positive for terminal velocity") }
	rho, _ := fluid.DensityAtDepth(depth)
	vol, _ := sub.VolumeAtDepth(depth, fluid, g)
	area := vol / sub.Length
	if area <= 0 { return 0, errors.New("drag area must be positive") }
	fb := rho * vol * g
	fw := sub.EffectiveMass() * g
	delta := fb - fw
	if math.Abs(delta) <= 1e-12 { return 0, nil }
	absDelta := math.Abs(delta)
	dragMag := func(vMag float64) float64 {
		re := rho * vMag * sub.Length / 0.001
		cd := CdFromRe(re)
		return 0.5 * rho * cd * area * vMag * vMag
	}
	lo, hi := 0.0, 1.0
	for hi < 1e6 {
		if dragMag(hi) >= absDelta { break }
		hi *= 2
	}
	if hi >= 1e6 && dragMag(hi) < absDelta { return 0, errors.New("unable to find terminal velocity upper bound") }
	for iter := 0; iter < 50; iter++ {
		mid := (lo + hi) / 2
		d := dragMag(mid)
		if math.Abs(d-absDelta) <= 1e-2 || (hi-lo) < 1e-5 {
			if delta > 0 { return mid, nil }
			return -mid, nil
		}
		if d < absDelta { lo = mid } else { hi = mid }
	}
	mid := (lo + hi) / 2
	if delta > 0 { return mid, nil }
	return -mid, nil
}
func FindEquilibriumDepthsWithStability(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]EquilibriumPoint, error) {
	if err := sub.Validate(); err != nil { return nil, err }
	if err := fluid.Validate(); err != nil { return nil, err }
	if g <= 0 { return nil, errors.New("gravity must be positive") }
	if maxDepth <= 0 { return nil, errors.New("maxDepth must be positive") }
	if tolerance <= 0 { return nil, errors.New("tolerance must be positive") }
	if maxDepth > sub.CrushDepth { return nil, errors.New("crush depth exceeded: maxDepth beyond crush depth") }
	N := 500
	dz := maxDepth / float64(N)
	zs := make([]float64, N+1)
	fs := make([]float64, N+1)
	for i := 0; i <= N; i++ {
		z := float64(i) * dz
		zs[i] = z
		v, _ := NetVerticalForceAtDepth(sub, fluid, z, 0, g)
		fs[i] = v
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
	var roots []EquilibriumPoint
	for _, br := range brackets {
		lo, hi := br[0], br[1]
		if lo == hi {
			fP, _ := NetVerticalForceAtDepth(sub, fluid, lo+0.05, 0, g)
			fM, _ := NetVerticalForceAtDepth(sub, fluid, lo-0.05, 0, g)
			dFdZ := (fP - fM) / 0.1
			roots = append(roots, EquilibriumPoint{Depth: lo, Stable: dFdZ < 0, FPrime: dFdZ})
			continue
		}
		fLo, _ := NetVerticalForceAtDepth(sub, fluid, lo, 0, g)
		var mid float64
		for iter := 0; iter < 50; iter++ {
			mid = (lo + hi) / 2
			fmid, _ := NetVerticalForceAtDepth(sub, fluid, mid, 0, g)
			if math.Abs(fmid) <= 1e-6 || (hi-lo) < tolerance {
				break
			}
			if fLo*fmid <= 0 {
				hi = mid
			} else {
				lo = mid
				fLo = fmid
			}
		}
		fP, _ := NetVerticalForceAtDepth(sub, fluid, mid+0.05, 0, g)
		fM, _ := NetVerticalForceAtDepth(sub, fluid, mid-0.05, 0, g)
		dFdZ := (fP - fM) / 0.1
		roots = append(roots, EquilibriumPoint{Depth: mid, Stable: dFdZ < 0, FPrime: dFdZ})
	}
	if len(roots) == 0 {
		return nil, errors.New("no equilibrium depth: no sign change")
	}
	for i := 0; i < len(roots); i++ {
		for j := i + 1; j < len(roots); j++ {
			if roots[j].Depth < roots[i].Depth {
				roots[i], roots[j] = roots[j], roots[i]
			}
		}
	}
	var dedup []EquilibriumPoint
	for _, r := range roots {
		if len(dedup) == 0 {
			dedup = append(dedup, r)
			continue
		}
		last := dedup[len(dedup)-1]
		if math.Abs(r.Depth-last.Depth) > tolerance*10 && math.Abs(r.Depth-last.Depth) > 1e-6 {
			dedup = append(dedup, r)
		}
	}
	return dedup, nil
}
func FindEquilibriumDepths(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) ([]float64, error) {
	pts, err := FindEquilibriumDepthsWithStability(sub, fluid, g, maxDepth, tolerance)
	if err != nil { return nil, err }
	out := make([]float64, len(pts))
	for i, p := range pts { out[i] = p.Depth }
	return out, nil
}
func FindEquilibriumDepth(sub Submarine, fluid Seawater, g float64, maxDepth float64, tolerance float64) (float64, error) {
	roots, err := FindEquilibriumDepths(sub, fluid, g, maxDepth, tolerance)
	if err != nil { return 0, err }
	return roots[0], nil
}
func TimeToDepth(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) (float64, error) {
	if err := sub.Validate(); err != nil { return 0, err }
	if err := fluid.Validate(); err != nil { return 0, err }
	if targetDepth <= 0 { return 0, errors.New("targetDepth must be positive") }
	if g <= 0 { return 0, errors.New("gravity must be positive") }
	if dt <= 0 { return 0, errors.New("dt must be positive") }
	if maxTime <= 0 { return 0, errors.New("maxTime must be positive") }
	if targetDepth > sub.CrushDepth { return 0, errors.New("crush depth exceeded: target beyond crush") }
	mass := sub.EffectiveMass()
	atol := 1e-6
	rtol := 1e-5
	_ = atol
	_ = rtol
	var errorEstimate float64
	var errNorm float64
	_ = errorEstimate
	_ = errNorm
	fnetDown := func(z float64, vDown float64) float64 {
		rho, _ := fluid.DensityAtDepth(z)
		vol, _ := sub.VolumeAtDepth(z, fluid, g)
		area := vol / sub.Length
		fb := rho * vol * g
		fw := mass * g
		re := rho * math.Abs(vDown) * sub.Length / 0.001
		cd := CdFromRe(re)
		drag := 0.5 * rho * cd * area * vDown * math.Abs(vDown)
		return fw - fb - drag
	}
	time := 0.0
	z := 0.0
	v := 0.0
	dtCurr := dt
	for time < maxTime {
		if z >= targetDepth { return time, nil }
		k1_z := v
		k1_v := fnetDown(z, v) / mass
		k2_z := v + 0.5*dtCurr*k1_v
		k2_v := fnetDown(z+0.5*dtCurr*k1_z, v+0.5*dtCurr*k1_v) / mass
		k3_z := v + 0.5*dtCurr*k2_v
		k3_v := fnetDown(z+0.5*dtCurr*k2_z, v+0.5*dtCurr*k2_v) / mass
		k4_z := v + dtCurr*k3_v
		k4_v := fnetDown(z+dtCurr*k3_z, v+dtCurr*k3_v) / mass
		_ = k1_z
		_ = k1_v
		_ = k2_z
		_ = k2_v
		_ = k3_z
		_ = k3_v
		_ = k4_z
		_ = k4_v
		zNext := z + dtCurr*(k1_z+2*k2_z+2*k3_z+k4_z)/6.0
		vNext := v + dtCurr*(k1_v+2*k2_v+2*k3_v+k4_v)/6.0
		if zNext >= targetDepth && z < targetDepth {
			frac := (targetDepth - z) / (zNext - z)
			if frac < 0 { frac = 0 }
			if frac > 1 { frac = 1 }
			return time + frac*dtCurr, nil
		}
		z = zNext
		v = vNext
		time += dtCurr
		if z > sub.CrushDepth { return 0, errors.New("crush depth exceeded") }
	}
	return 0, errors.New("target depth not reached within maxTime")
}
func ComputeDiveProfile(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) ([]DiveState, error) {
	if err := sub.Validate(); err != nil { return nil, err }
	if err := fluid.Validate(); err != nil { return nil, err }
	if targetDepth <= 0 { return nil, errors.New("targetDepth must be positive") }
	if g <= 0 { return nil, errors.New("gravity must be positive") }
	if dt <= 0 { return nil, errors.New("dt must be positive") }
	if maxTime <= 0 { return nil, errors.New("maxTime must be positive") }
	if targetDepth > sub.CrushDepth { return nil, errors.New("crush depth exceeded: target beyond crush") }
	mass := sub.EffectiveMass()
	fnetDown := func(z float64, vDown float64) float64 {
		rho, _ := fluid.DensityAtDepth(z)
		vol, _ := sub.VolumeAtDepth(z, fluid, g)
		area := vol / sub.Length
		fb := rho * vol * g
		fw := mass * g
		re := rho * math.Abs(vDown) * sub.Length / 0.001
		cd := CdFromRe(re)
		drag := 0.5 * rho * cd * area * vDown * math.Abs(vDown)
		return fw - fb - drag
	}
	timeVal := 0.0
	z := 0.0
	v := 0.0
	dtCurr := dt
	var profile []DiveState
	p0, _ := fluid.PressureAtDepth(0, g)
	profile = append(profile, DiveState{Time: timeVal, Depth: z, Velocity: v, Acceleration: 0, Pressure: p0})
	for timeVal < maxTime {
		if z >= targetDepth { break }
		k1_z := v
		k1_v := fnetDown(z, v) / mass
		k2_z := v + 0.5*dtCurr*k1_v
		k2_v := fnetDown(z+0.5*dtCurr*k1_z, v+0.5*dtCurr*k1_v) / mass
		k3_z := v + 0.5*dtCurr*k2_v
		k3_v := fnetDown(z+0.5*dtCurr*k2_z, v+0.5*dtCurr*k2_v) / mass
		k4_z := v + dtCurr*k3_v
		k4_v := fnetDown(z+dtCurr*k3_z, v+dtCurr*k3_v) / mass
		zNext := z + dtCurr*(k1_z+2*k2_z+2*k3_z+k4_z)/6.0
		vNext := v + dtCurr*(k1_v+2*k2_v+2*k3_v+k4_v)/6.0
		if zNext >= targetDepth {
			frac := (targetDepth - z) / (zNext - z)
			if frac < 0 { frac = 0 }
			if frac > 1 { frac = 1 }
			timeFinal := timeVal + frac*dtCurr
			vFinal := v + frac*(vNext-v)
			pFinal, _ := fluid.PressureAtDepth(targetDepth, g)
			fFinal := fnetDown(targetDepth, vFinal)
			profile = append(profile, DiveState{Time: timeFinal, Depth: targetDepth, Velocity: vFinal, Acceleration: fFinal / mass, Pressure: pFinal})
			break
		}
		z = zNext
		v = vNext
		timeVal += dtCurr
		p, _ := fluid.PressureAtDepth(z, g)
		f := fnetDown(z, v)
		profile = append(profile, DiveState{Time: timeVal, Depth: z, Velocity: v, Acceleration: f / mass, Pressure: p})
		if z > sub.CrushDepth { return profile, errors.New("crush depth exceeded") }
	}
	return profile, nil
}
func AnalyzeDive(sub Submarine, fluid Seawater) (DiveResult, error) {
	if err := sub.Validate(); err != nil { return DiveResult{}, err }
	if err := fluid.Validate(); err != nil { return DiveResult{}, err }
	g := StandardGravity
	eff, _ := sub.EffectiveDensity()
	state, _ := CheckSubmarineState(sub, fluid)
	req, _ := RequiredBallastForNeutral(sub, fluid)
	possible, _ := IsNeutralBuoyancyPossible(sub, fluid)
	frac, _ := SubmergedFraction(sub, fluid)
	fnet, _ := NetVerticalForce(sub, fluid, g)
	acc, _ := VerticalAcceleration(sub, fluid, g)
	refDepth := 100.0
	if refDepth > sub.CrushDepth { refDepth = sub.CrushDepth * 0.9 }
	effAtDepth, _ := sub.EffectiveDensityAtDepth(refDepth, fluid, g)
	reqAtDepth, _ := RequiredBallastForNeutralAtDepth(sub, fluid, refDepth, g)
	possAtDepth, _ := IsNeutralBuoyancyPossibleAtDepth(sub, fluid, refDepth, g)
	fnetAtDepth, _ := NetVerticalForceAtDepth(sub, fluid, refDepth, 0, g)
	stateAtDepth, _ := CheckSubmarineStateAtDepth(sub, fluid, refDepth, g)
	volAtDepth, _ := sub.VolumeAtDepth(refDepth, fluid, g)
	eqDepth := -1.0
	if ed, err := FindEquilibriumDepth(sub, fluid, g, 2000, 1e-1); err == nil { eqDepth = ed }
	termVel, _ := TerminalVelocity(sub, fluid, 0, g)
	t2d := 0.0
	if tv, err := TimeToDepth(sub, fluid, 100, g, 0.1, 10000); err == nil { t2d = tv }
	maxPress := 0.0
	if p, err := fluid.PressureAtDepth(refDepth, g); err == nil { maxPress = p }
	return DiveResult{State: state, StateAtDepth: stateAtDepth, Fraction: frac, RequiredBallast: req, RequiredBallastAtDepth: reqAtDepth, IsPossible: possible, IsPossibleAtDepth: possAtDepth, EffectiveDensity: eff, EffectiveDensityAtDepth: effAtDepth, NetForce: fnet, NetForceAtDepth: fnetAtDepth, Acceleration: acc, EquilibriumDepth: eqDepth, TerminalVelocity: termVel, TimeToDepth: t2d, MaxPressure: maxPress, VolumeAtDepth: volAtDepth}, nil
}
type fleetItem struct { sub Submarine; index int; density float64; priority float64 }
type fleetPriorityQueue []*fleetItem
func (pq fleetPriorityQueue) Len() int { return len(pq) }
func (pq fleetPriorityQueue) Less(i, j int) bool { return pq[i].priority > pq[j].priority }
func (pq fleetPriorityQueue) Swap(i, j int) { pq[i], pq[j] = pq[j], pq[i] }
func (pq *fleetPriorityQueue) Push(x interface{}) { *pq = append(*pq, x.(*fleetItem)) }
func (pq *fleetPriorityQueue) Pop() interface{} { old := *pq; n := len(old); it := old[n-1]; *pq = old[0 : n-1]; return it }
func BatchAnalyzeFleet(subs []Submarine, fluid Seawater) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil { return nil, err }
	if len(subs) == 0 { return []DiveResult{}, nil }
	results := make([]DiveResult, len(subs))
	sem := make(chan struct{}, 4)
	var wg sync.WaitGroup
	var active atomic.Int64
	var maxActive atomic.Int64
	pq := &fleetPriorityQueue{}
	heap.Init(pq)
	for i, sub := range subs {
		dens := 0.0
		if sub.Volume > 0 { dens = sub.EffectiveMass() / sub.Volume }
		heap.Push(pq, &fleetItem{sub: sub, index: i, density: dens, priority: dens})
	}
	for pq.Len() > 0 {
		it := heap.Pop(pq).(*fleetItem)
		wg.Add(1)
		iLocal := it.index
		subLocal := it.sub
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			cur := active.Add(1)
			for {
				m := maxActive.Load()
				if cur > m { if maxActive.CompareAndSwap(m, cur) { break } } else { break }
			}
			defer func() { <-sem; active.Add(-1) }()
			if err := subLocal.Validate(); err != nil { results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}; return }
			res, _ := AnalyzeDive(subLocal, fluid)
			res.Index = iLocal
			results[iLocal] = res
		}()
	}
	wg.Wait()
	return results, nil
}
func BatchAnalyzeFleetWithTargets(subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil { return nil, err }
	if g <= 0 { return nil, errors.New("gravity must be positive") }
	if len(subs) != len(targetDepths) { return nil, errors.New("subs and targetDepths length mismatch") }
	if len(subs) == 0 { return []DiveResult{}, nil }
	results := make([]DiveResult, len(subs))
	sem := make(chan struct{}, 4)
	var wg sync.WaitGroup
	var active atomic.Int64
	var maxActive atomic.Int64
	pq := &fleetPriorityQueue{}
	heap.Init(pq)
	for i := range subs {
		dens := 0.0
		if subs[i].Volume > 0 { dens = subs[i].EffectiveMass() / subs[i].Volume }
		heap.Push(pq, &fleetItem{sub: subs[i], index: i, density: dens, priority: targetDepths[i]})
	}
	for pq.Len() > 0 {
		it := heap.Pop(pq).(*fleetItem)
		wg.Add(1)
		iLocal := it.index
		subLocal := it.sub
		target := targetDepths[iLocal]
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			cur := active.Add(1)
			for { m := maxActive.Load(); if cur > m { if maxActive.CompareAndSwap(m, cur) { break } } else { break } }
			defer func() { <-sem; active.Add(-1) }()
			if err := subLocal.Validate(); err != nil { results[iLocal] = DiveResult{Index: iLocal, State: "invalid", CrushRisk: target > subLocal.CrushDepth}; return }
			if target < 0 { results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}; return }
			if target > subLocal.CrushDepth { res, _ := AnalyzeDive(subLocal, fluid); res.Index=iLocal; res.CrushRisk=true; res.State="invalid"; results[iLocal]=res; return }
			res, _ := AnalyzeDive(subLocal, fluid)
			if t, err := TimeToDepth(subLocal, fluid, target, g, 0.1, 10000); err == nil { res.TimeToDepth=t }
			res.Index=iLocal
			results[iLocal]=res
		}()
	}
	wg.Wait()
	return results, nil
}
func BatchAnalyzeFleetWithContext(ctx context.Context, subs []Submarine, fluid Seawater, targetDepths []float64, g float64) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil { return nil, err }
	if g <= 0 { return nil, errors.New("gravity must be positive") }
	if len(subs) != len(targetDepths) { return nil, errors.New("subs and targetDepths length mismatch") }
	if ctx.Err() != nil { return nil, ctx.Err() }
	if len(subs) == 0 { return []DiveResult{}, nil }
	results := make([]DiveResult, len(subs))
	sem := make(chan struct{}, 4)
	var wg sync.WaitGroup
	var active atomic.Int64
	var maxActive atomic.Int64
	pq := &fleetPriorityQueue{}
	heap.Init(pq)
	for i := range subs {
		dens := 0.0
		if subs[i].Volume > 0 { dens = subs[i].EffectiveMass() / subs[i].Volume }
		heap.Push(pq, &fleetItem{sub: subs[i], index: i, density: dens, priority: dens})
	}
	for pq.Len() > 0 {
		if ctx.Err() != nil { break }
		it := heap.Pop(pq).(*fleetItem)
		wg.Add(1)
		iLocal := it.index
		subLocal := it.sub
		target := targetDepths[iLocal]
		go func() {
			defer wg.Done()
			select {
			case <-ctx.Done():
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			case sem <- struct{}{}:
			}
			cur := active.Add(1)
			for { m := maxActive.Load(); if cur > m { if maxActive.CompareAndSwap(m, cur) { break } } else { break } }
			defer func() { <-sem; active.Add(-1) }()
			if ctx.Err() != nil { results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}; return }
			if err := subLocal.Validate(); err != nil { results[iLocal] = DiveResult{Index: iLocal, State: "invalid", CrushRisk: target > subLocal.CrushDepth}; return }
			if target < 0 { results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}; return }
			if target > subLocal.CrushDepth { res, _ := AnalyzeDive(subLocal, fluid); res.Index=iLocal; res.CrushRisk=true; res.State="invalid"; results[iLocal]=res; return }
			res, _ := AnalyzeDive(subLocal, fluid)
			if t, err := TimeToDepth(subLocal, fluid, target, g, 0.1, 10000); err == nil { res.TimeToDepth=t }
			res.Index=iLocal
			results[iLocal]=res
		}()
	}
	wg.Wait()
	if err := ctx.Err(); err != nil { return results, err }
	return results, nil
}
GO
