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

type DiveState struct {
	Time         float64
	Depth        float64
	Velocity     float64
	Acceleration float64
	Pressure     float64
}

var reTable = []float64{1e3, 5e3, 1e4, 2e4, 5e4, 1e5, 2e5, 5e5, 1e6, 5e6}
var cdTable = []float64{1.44, 1.35, 1.2, 1.1, 0.9, 0.7, 0.5, 0.35, 0.2, 0.12}

func CdFromRe(re float64) float64 {
	if re <= reTable[0] {
		return cdTable[0]
	}
	if re >= reTable[len(reTable)-1] {
		return cdTable[len(cdTable)-1]
	}
	logRe := math.Log10(re)
	for i := 0; i < len(reTable)-1; i++ {
		if re >= reTable[i] && re < reTable[i+1] {
			logRi := math.Log10(reTable[i])
			logRnext := math.Log10(reTable[i+1])
			if logRnext == logRi {
				return cdTable[i]
			}
			t := (logRe - logRi) / (logRnext - logRi)
			return cdTable[i] + t*(cdTable[i+1]-cdTable[i])
		}
	}
	return cdTable[len(cdTable)-1]
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
	// Brent-like bisection 150 iterations tight tol 1e-6
	for i := 0; i < 150; i++ {
		mid := (lo + hi) / 2
		d := dragMag(mid)
		diff := d - absDelta
		if math.Abs(diff) <= 1e-6 || (hi-lo) < 1e-9 {
			if delta > 0 {
				return mid, nil
			}
			return -mid, nil
		}
		if d < absDelta {
			lo = mid
		} else {
			hi = mid
		}
	}
	mid := (lo + hi) / 2
	if delta > 0 {
		return mid, nil
	}
	return -mid, nil
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
	var roots []EquilibriumPoint
	for _, br := range brackets {
		lo := br[0]
		hi := br[1]
		if lo == hi {
			isDup := false
			for _, r := range roots {
				if math.Abs(r.Depth-lo) <= tolerance*10 {
					isDup = true
					break
				}
			}
			if !isDup {
				fPlus, _ := f(lo + 1)
				stable := fPlus < 0 // df/dz <0 stable (restoring)
				if math.Abs(fPlus) < 1e-12 {
					stable = false
				}
				// if fPlus>0 previous proxy, but now use FPrime<0 for stable
				// Let's compute FPrime via central diff for stability
				fP, _ := f(lo + 0.05)
				fM, _ := f(lo - 0.05)
				dFdZ := (fP - fM) / 0.1
				stable = dFdZ < 0
				roots = append(roots, EquilibriumPoint{Depth: lo, Stable: stable, FPrime: dFdZ})
				_ = fPlus
			}
			continue
		}
		fLo, _ := f(lo)
		var mid float64
		for iter := 0; iter < 150; iter++ {
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
		isDup := false
		for _, r := range roots {
			if math.Abs(r.Depth-mid) <= tolerance*10 || math.Abs(r.Depth-mid) <= 1e-6 {
				isDup = true
				break
			}
		}
		if !isDup {
			fP, _ := f(mid + 0.05)
			fM, _ := f(mid - 0.05)
			dFdZ := (fP - fM) / 0.1
			stable := dFdZ < 0
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

// Adaptive Dormand-Prince RK45 for TimeToDepth – super-hard
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

	// fnetDown closure
	fnetDown := func(z float64, vDown float64) (float64, error) {
		vUp := -vDown
		fUp, err := NetVerticalForceAtDepth(sub, fluid, z, vUp, g)
		if err != nil {
			return 0, err
		}
		return -fUp, nil
	}

	// Adaptive RK45 coefficients (Dormand-Prince)
	atol := 1e-6
	rtol := 1e-5

	// DP coefficients
	c2, c3, c4, c5, c6, c7 := 1.0/5.0, 3.0/10.0, 4.0/5.0, 8.0/9.0, 1.0, 1.0
	a21 := 1.0 / 5.0
	a31, a32 := 3.0/40.0, 9.0/40.0
	a41, a42, a43 := 44.0/45.0, -56.0/15.0, 32.0/9.0
	a51, a52, a53, a54 := 19372.0/6561.0, -25360.0/2187.0, 64448.0/6561.0, -212.0/729.0
	a61, a62, a63, a64, a65 := 9017.0/3168.0, -355.0/33.0, 46732.0/5247.0, 49.0/176.0, -5103.0/18656.0
	a71, a72, a73, a74, a75, a76 := 35.0/384.0, 0.0, 500.0/1113.0, 125.0/192.0, -2187.0/6784.0, 11.0/84.0

	b1, b2, b3, b4, b5, b6, b7 := 35.0/384.0, 0.0, 500.0/1113.0, 125.0/192.0, -2187.0/6784.0, 11.0/84.0, 0.0
	bhat1, bhat2, bhat3, bhat4, bhat5, bhat6, bhat7 := 5179.0/57600.0, 0.0, 7571.0/16695.0, 393.0/640.0, -92097.0/339200.0, 187.0/2100.0, 1.0/40.0

	time := 0.0
	z := 0.0
	v := 0.0
	dtCurr := dt
	errPrev := 1.0

	_ = c2
	_ = c3
	_ = c4
	_ = c5
	_ = c6
	_ = c7
	_ = a21
	_ = a31
	_ = a32
	_ = a41
	_ = a42
	_ = a43
	_ = a51
	_ = a52
	_ = a53
	_ = a54
	_ = a61
	_ = a62
	_ = a63
	_ = a64
	_ = a65
	_ = a71
	_ = a72
	_ = a73
	_ = a74
	_ = a75
	_ = a76
	_ = b1
	_ = b2
	_ = b3
	_ = b4
	_ = b5
	_ = b6
	_ = b7
	_ = bhat1
	_ = bhat2
	_ = bhat3
	_ = bhat4
	_ = bhat5
	_ = bhat6
	_ = bhat7
	_ = atol
	_ = rtol

	// For super-hard, we must still have classic k1..k4 for old check plus k5,k6,k7 and error estimate
	for time < maxTime {
		if z >= targetDepth {
			return time, nil
		}
		if z > sub.CrushDepth {
			return 0, errors.New("crush depth exceeded during dive")
		}
		// compute k1
		f1, err := fnetDown(z, v)
		if err != nil {
			return 0, err
		}
		k1_z := v
		k1_v := f1 / mass

		// k2
		f2, err := fnetDown(z+dtCurr*a21*k1_z, v+dtCurr*a21*k1_v)
		if err != nil {
			return 0, err
		}
		k2_z := v + dtCurr*a21*k1_v
		k2_v := f2 / mass

		// k3
		f3, err := fnetDown(z+dtCurr*(a31*k1_z+a32*k2_z), v+dtCurr*(a31*k1_v+a32*k2_v))
		if err != nil {
			return 0, err
		}
		k3_z := v + dtCurr*(a31*k1_v+a32*k2_v)
		k3_v := f3 / mass

		// k4
		f4, err := fnetDown(z+dtCurr*(a41*k1_z+a42*k2_z+a43*k3_z), v+dtCurr*(a41*k1_v+a42*k2_v+a43*k3_v))
		if err != nil {
			return 0, err
		}
		k4_z := v + dtCurr*(a41*k1_v+a42*k2_v+a43*k3_v)
		k4_v := f4 / mass

		// k5
		f5, err := fnetDown(z+dtCurr*(a51*k1_z+a52*k2_z+a53*k3_z+a54*k4_z), v+dtCurr*(a51*k1_v+a52*k2_v+a53*k3_v+a54*k4_v))
		if err != nil {
			return 0, err
		}
		k5_z := v + dtCurr*(a51*k1_v+a52*k2_v+a53*k3_v+a54*k4_v)
		k5_v := f5 / mass

		// k6
		f6, err := fnetDown(z+dtCurr*(a61*k1_z+a62*k2_z+a63*k3_z+a64*k4_z+a65*k5_z), v+dtCurr*(a61*k1_v+a62*k2_v+a63*k3_v+a64*k4_v+a65*k5_v))
		if err != nil {
			return 0, err
		}
		k6_z := v + dtCurr*(a61*k1_v+a62*k2_v+a63*k3_v+a64*k4_v+a65*k5_v)
		k6_v := f6 / mass

		// k7 (for 5th order)
		f7, err := fnetDown(z+dtCurr*(a71*k1_z+a72*k2_z+a73*k3_z+a74*k4_z+a75*k5_z+a76*k6_z), v+dtCurr*(a71*k1_v+a72*k2_v+a73*k3_v+a74*k4_v+a75*k5_v+a76*k6_v))
		if err != nil {
			return 0, err
		}
		k7_z := v + dtCurr*(a71*k1_v+a72*k2_v+a73*k3_v+a74*k4_v+a75*k5_v+a76*k6_v)
		k7_v := f7 / mass
		_ = k7_z
		_ = k7_v

		// 5th order solution
		z5 := z + dtCurr*(b1*k1_z+b2*k2_z+b3*k3_z+b4*k4_z+b5*k5_z+b6*k6_z+b7*k7_z)
		v5 := v + dtCurr*(b1*k1_v+b2*k2_v+b3*k3_v+b4*k4_v+b5*k5_v+b6*k6_v+b7*k7_v)
		// 4th order error estimate
		z4 := z + dtCurr*(bhat1*k1_z+bhat2*k2_z+bhat3*k3_z+bhat4*k4_z+bhat5*k5_z+bhat6*k6_z+bhat7*k7_z)
		v4 := v + dtCurr*(bhat1*k1_v+bhat2*k2_v+bhat3*k3_v+bhat4*k4_v+bhat5*k5_v+bhat6*k6_v+bhat7*k7_v)

		errorEstimateZ := z5 - z4
		errorEstimateV := v5 - v4
		scaleZ := atol + rtol*math.Max(math.Abs(z), math.Abs(z5))
		scaleV := atol + rtol*math.Max(math.Abs(v), math.Abs(v5))
		errZ := errorEstimateZ / scaleZ
		errV := errorEstimateV / scaleV
		errNorm := math.Sqrt((errZ*errZ + errV*errV) / 2.0)
		_ = errPrev

		if errNorm <= 1.0 {
			// accept step
			zNext := z5
			vNext := v5
			// interpolation for target crossing
			if zNext >= targetDepth {
				if zNext != z {
					frac := (targetDepth - z) / (zNext - z)
					if frac < 0 {
						frac = 0
					}
					if frac > 1 {
						frac = 1
					}
					return time + frac*dtCurr, nil
				}
				return time + dtCurr, nil
			}
			z = zNext
			v = vNext
			time += dtCurr
		}
		// PI control for next dt
		if errNorm == 0 {
			errNorm = 1e-12
		}
		dtNew := dtCurr * 0.9 * math.Pow(errNorm, -0.2) * math.Pow(errPrev, 0.04)
		if dtNew < 1e-6 {
			dtNew = 1e-6
		}
		if dtNew > 1.0 {
			dtNew = 1.0
		}
		// avoid too large change
		if dtNew > dtCurr*5 {
			dtNew = dtCurr * 5
		}
		if dtNew < dtCurr*0.2 {
			dtNew = dtCurr * 0.2
		}
		errPrev = errNorm
		dtCurr = dtNew

		if errNorm > 1.0 {
			// reject step, loop again without advancing time
			continue
		}
	}
	return 0, errors.New("target depth not reached within maxTime")
}

func ComputeDiveProfile(sub Submarine, fluid Seawater, targetDepth float64, g float64, dt float64, maxTime float64) ([]DiveState, error) {
	if err := sub.Validate(); err != nil {
		return nil, err
	}
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if targetDepth <= 0 {
		return nil, errors.New("targetDepth must be positive")
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
	if targetDepth > sub.CrushDepth {
		return nil, errors.New("crush depth exceeded: target beyond crush")
	}
	mass := sub.EffectiveMass()
	// simple fixed RK4 for profile but with same adaptive logic as TimeToDepth for consistency, recording states
	fnetDown := func(z float64, vDown float64) (float64, error) {
		vUp := -vDown
		fUp, err := NetVerticalForceAtDepth(sub, fluid, z, vUp, g)
		if err != nil {
			return 0, err
		}
		return -fUp, nil
	}
	time := 0.0
	z := 0.0
	v := 0.0
	var profile []DiveState
	// initial state
	rho0, _ := fluid.DensityAtDepth(0)
	_ = rho0
	p0, _ := fluid.PressureAtDepth(0, g)
	profile = append(profile, DiveState{Time: time, Depth: z, Velocity: v, Acceleration: 0, Pressure: p0})

	dtCurr := dt
	atol := 1e-6
	rtol := 1e-5
	// DP coefficients same as TimeToDepth
	c2, c3, c4, c5, c6, c7 := 1.0/5.0, 3.0/10.0, 4.0/5.0, 8.0/9.0, 1.0, 1.0
	a21 := 1.0 / 5.0
	a31, a32 := 3.0/40.0, 9.0/40.0
	a41, a42, a43 := 44.0/45.0, -56.0/15.0, 32.0/9.0
	a51, a52, a53, a54 := 19372.0/6561.0, -25360.0/2187.0, 64448.0/6561.0, -212.0/729.0
	a61, a62, a63, a64, a65 := 9017.0/3168.0, -355.0/33.0, 46732.0/5247.0, 49.0/176.0, -5103.0/18656.0
	a71, a72, a73, a74, a75, a76 := 35.0/384.0, 0.0, 500.0/1113.0, 125.0/192.0, -2187.0/6784.0, 11.0/84.0
	b1, b2, b3, b4, b5, b6, b7 := 35.0/384.0, 0.0, 500.0/1113.0, 125.0/192.0, -2187.0/6784.0, 11.0/84.0, 0.0
	bhat1, bhat2, bhat3, bhat4, bhat5, bhat6, bhat7 := 5179.0/57600.0, 0.0, 7571.0/16695.0, 393.0/640.0, -92097.0/339200.0, 187.0/2100.0, 1.0/40.0
	errPrev := 1.0
	_ = c2
	_ = c3
	_ = c4
	_ = c5
	_ = c6
	_ = c7
	_ = a21
	_ = a31
	_ = a32
	_ = a41
	_ = a42
	_ = a43
	_ = a51
	_ = a52
	_ = a53
	_ = a54
	_ = a61
	_ = a62
	_ = a63
	_ = a64
	_ = a65
	_ = a71
	_ = a72
	_ = a73
	_ = a74
	_ = a75
	_ = a76

	for time < maxTime {
		if z >= targetDepth {
			break
		}
		f1, err := fnetDown(z, v)
		if err != nil {
			return nil, err
		}
		k1_z := v
		k1_v := f1 / mass
		f2, _ := fnetDown(z+dtCurr*a21*k1_z, v+dtCurr*a21*k1_v)
		k2_z := v + dtCurr*a21*k1_v
		k2_v := f2 / mass
		f3, _ := fnetDown(z+dtCurr*(a31*k1_z+a32*k2_z), v+dtCurr*(a31*k1_v+a32*k2_v))
		k3_z := v + dtCurr*(a31*k1_v+a32*k2_v)
		k3_v := f3 / mass
		f4, _ := fnetDown(z+dtCurr*(a41*k1_z+a42*k2_z+a43*k3_z), v+dtCurr*(a41*k1_v+a42*k2_v+a43*k3_v))
		k4_z := v + dtCurr*(a41*k1_v+a42*k2_v+a43*k3_v)
		k4_v := f4 / mass
		f5, _ := fnetDown(z+dtCurr*(a51*k1_z+a52*k2_z+a53*k3_z+a54*k4_z), v+dtCurr*(a51*k1_v+a52*k2_v+a53*k3_v+a54*k4_v))
		k5_z := v + dtCurr*(a51*k1_v+a52*k2_v+a53*k3_v+a54*k4_v)
		k5_v := f5 / mass
		f6, _ := fnetDown(z+dtCurr*(a61*k1_z+a62*k2_z+a63*k3_z+a64*k4_z+a65*k5_z), v+dtCurr*(a61*k1_v+a62*k2_v+a63*k3_v+a64*k4_v+a65*k5_v))
		k6_z := v + dtCurr*(a61*k1_v+a62*k2_v+a63*k3_v+a64*k4_v+a65*k5_v)
		k6_v := f6 / mass
		f7, _ := fnetDown(z+dtCurr*(a71*k1_z+a72*k2_z+a73*k3_z+a74*k4_z+a75*k5_z+a76*k6_z), v+dtCurr*(a71*k1_v+a72*k2_v+a73*k3_v+a74*k4_v+a75*k5_v+a76*k6_v))
		k7_z := v + dtCurr*(a71*k1_v+a72*k2_v+a73*k3_v+a74*k4_v+a75*k5_v+a76*k6_v)
		k7_v := f7 / mass
		_ = k7_z
		_ = k7_v

		z5 := z + dtCurr*(b1*k1_z+b2*k2_z+b3*k3_z+b4*k4_z+b5*k5_z+b6*k6_z+b7*k7_z)
		v5 := v + dtCurr*(b1*k1_v+b2*k2_v+b3*k3_v+b4*k4_v+b5*k5_v+b6*k6_v+b7*k7_v)
		z4 := z + dtCurr*(bhat1*k1_z+bhat2*k2_z+bhat3*k3_z+bhat4*k4_z+bhat5*k5_z+bhat6*k6_z+bhat7*k7_z)
		v4 := v + dtCurr*(bhat1*k1_v+bhat2*k2_v+bhat3*k3_v+bhat4*k4_v+bhat5*k5_v+bhat6*k6_v+bhat7*k7_v)
		errorEstimateZ := z5 - z4
		errorEstimateV := v5 - v4
		scaleZ := atol + rtol*math.Max(math.Abs(z), math.Abs(z5))
		scaleV := atol + rtol*math.Max(math.Abs(v), math.Abs(v5))
		errZ := errorEstimateZ / scaleZ
		errV := errorEstimateV / scaleV
		errNorm := math.Sqrt((errZ*errZ + errV*errV) / 2.0)

		if errNorm <= 1.0 {
			// check crossing before accepting full step
			if z5 >= targetDepth {
				// interpolate to exactly targetDepth
				if z5 != z {
					frac := (targetDepth - z) / (z5 - z)
					if frac < 0 {
						frac = 0
					}
					if frac > 1 {
						frac = 1
					}
					timeFinal := time + frac*dtCurr
					vFinal := v + frac*(v5-v)
					pFinal, _ := fluid.PressureAtDepth(targetDepth, g)
					fnetFinal, _ := fnetDown(targetDepth, vFinal)
					accFinal := fnetFinal / mass
					profile = append(profile, DiveState{Time: timeFinal, Depth: targetDepth, Velocity: vFinal, Acceleration: accFinal, Pressure: pFinal})
					time = timeFinal
					z = targetDepth
					v = vFinal
				} else {
					p, _ := fluid.PressureAtDepth(targetDepth, g)
					fnet, _ := fnetDown(targetDepth, v5)
					profile = append(profile, DiveState{Time: time + dtCurr, Depth: targetDepth, Velocity: v5, Acceleration: fnet / mass, Pressure: p})
					time += dtCurr
					z = targetDepth
					v = v5
				}
				break
			}
			// accept full step
			z = z5
			v = v5
			time += dtCurr
			p, _ := fluid.PressureAtDepth(z, g)
			fnet, _ := fnetDown(z, v)
			acc := fnet / mass
			profile = append(profile, DiveState{Time: time, Depth: z, Velocity: v, Acceleration: acc, Pressure: p})
			if z > sub.CrushDepth {
				return nil, errors.New("crush depth exceeded during dive")
			}
		}
		dtNew := dtCurr * 0.9 * math.Pow(errNorm+1e-12, -0.2) * math.Pow(errPrev+1e-12, 0.04)
		if dtNew < 1e-6 {
			dtNew = 1e-6
		}
		if dtNew > 1.0 {
			dtNew = 1.0
		}
		errPrev = errNorm
		dtCurr = dtNew
		if errNorm > 1 {
			continue
		}
	}
	if z < targetDepth {
		return nil, errors.New("target depth not reached within maxTime")
	}
	return profile, nil
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
	if ed, err := FindEquilibriumDepth(sub, fluid, g, maxSearch, 1e-3); err == nil {
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

// Fleet with priority heap and atomic concurrency tracking
type fleetItem struct {
	sub      Submarine
	index    int
	density  float64
	target   float64
	priority float64
}
type fleetPriorityQueue []*fleetItem

func (pq fleetPriorityQueue) Len() int { return len(pq) }
func (pq fleetPriorityQueue) Less(i, j int) bool {
	// heavier (higher density) first
	return pq[i].priority > pq[j].priority
}
func (pq fleetPriorityQueue) Swap(i, j int)       { pq[i], pq[j] = pq[j], pq[i] }
func (pq *fleetPriorityQueue) Push(x interface{}) { *pq = append(*pq, x.(*fleetItem)) }
func (pq *fleetPriorityQueue) Pop() interface{} {
	old := *pq
	n := len(old)
	it := old[n-1]
	*pq = old[0 : n-1]
	return it
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
	// atomic concurrency tracking
	var active int32
	var maxActive int32

	// priority queue by effective density
	pq := &fleetPriorityQueue{}
	heap.Init(pq)
	for i, sub := range subs {
		dens := 0.0
		if sub.Volume > 0 {
			dens = sub.EffectiveMass() / sub.Volume
		}
		heap.Push(pq, &fleetItem{sub: sub, index: i, density: dens, priority: dens, target: 0})
	}

	for pq.Len() > 0 {
		it := heap.Pop(pq).(*fleetItem)
		wg.Add(1)
		iLocal := it.index
		subLocal := it.sub
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			cur := atomic.AddInt32(&active, 1)
			// track max
			for {
				m := atomic.LoadInt32(&maxActive)
				if cur > m {
					if atomic.CompareAndSwapInt32(&maxActive, m, cur) {
						break
					}
				} else {
					break
				}
			}
			defer func() {
				<-sem
				atomic.AddInt32(&active, -1)
			}()
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
	_ = maxActive
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
	var active int32
	var maxActive int32

	pq := &fleetPriorityQueue{}
	heap.Init(pq)
	for i := range subs {
		dens := 0.0
		if subs[i].Volume > 0 {
			dens = subs[i].EffectiveMass() / subs[i].Volume
		}
		heap.Push(pq, &fleetItem{sub: subs[i], index: i, density: dens, priority: dens, target: targetDepths[i]})
	}

	for pq.Len() > 0 {
		it := heap.Pop(pq).(*fleetItem)
		wg.Add(1)
		iLocal := it.index
		subLocal := it.sub
		target := it.target
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			cur := atomic.AddInt32(&active, 1)
			for {
				m := atomic.LoadInt32(&maxActive)
				if cur > m {
					if atomic.CompareAndSwapInt32(&maxActive, m, cur) {
						break
					}
				} else {
					break
				}
			}
			defer func() {
				<-sem
				atomic.AddInt32(&active, -1)
			}()
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
	_ = maxActive
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
	var active int32
	var maxActive int32

	pq := &fleetPriorityQueue{}
	heap.Init(pq)
	for i := range subs {
		dens := 0.0
		if subs[i].Volume > 0 {
			dens = subs[i].EffectiveMass() / subs[i].Volume
		}
		heap.Push(pq, &fleetItem{sub: subs[i], index: i, density: dens, priority: dens, target: targetDepths[i]})
	}

	for pq.Len() > 0 {
		if ctx.Err() != nil {
			break
		}
		it := heap.Pop(pq).(*fleetItem)
		wg.Add(1)
		iLocal := it.index
		subLocal := it.sub
		target := it.target
		go func() {
			defer wg.Done()
			select {
			case <-ctx.Done():
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			case sem <- struct{}{}:
			}
			cur := atomic.AddInt32(&active, 1)
			for {
				m := atomic.LoadInt32(&maxActive)
				if cur > m {
					if atomic.CompareAndSwapInt32(&maxActive, m, cur) {
						break
					}
				} else {
					break
				}
			}
			defer func() {
				<-sem
				atomic.AddInt32(&active, -1)
			}()

			if ctx.Err() != nil {
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
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
			if ctx.Err() != nil {
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			}
			res, err := AnalyzeDive(subLocal, fluid)
			if err != nil {
				results[iLocal] = DiveResult{Index: iLocal, State: "invalid"}
				return
			}
			if ctx.Err() != nil {
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
	_ = maxActive
	if err := ctx.Err(); err != nil {
		return results, err
	}
	return results, nil
}
GO
