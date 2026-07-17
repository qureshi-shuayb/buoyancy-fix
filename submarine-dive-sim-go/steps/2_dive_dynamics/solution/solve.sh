#!/bin/bash
set -euo pipefail

cat > /app/dive.go <<'GO'
package submarine

type DiveResult struct {
	Index            int
	State            string
	Fraction         float64
	RequiredBallast  float64
	IsPossible       bool
	EffectiveDensity float64
	NetForce         float64
	Acceleration     float64
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
		return 0, errInvalidGravity()
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

func errInvalidGravity() error {
	// small helper to keep error message containing gravity
	return &gravityError{}
}

type gravityError struct{}

func (e *gravityError) Error() string { return "gravity must be positive" }

func VerticalAcceleration(sub Submarine, fluid Seawater, g float64) (float64, error) {
	fnet, err := NetVerticalForce(sub, fluid, g)
	if err != nil {
		return 0, err
	}
	effMass := sub.EffectiveMass()
	if effMass <= 0 {
		return 0, errMass()
	}
	return fnet / effMass, nil
}

func errMass() error { return &massError{} }
type massError struct{}
func (e *massError) Error() string { return "mass must be positive" }

func AnalyzeDive(sub Submarine, fluid Seawater) (DiveResult, error) {
	if err := sub.Validate(); err != nil {
		return DiveResult{}, err
	}
	if err := fluid.Validate(); err != nil {
		return DiveResult{}, err
	}
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
	fnet, err := NetVerticalForce(sub, fluid, StandardGravity)
	if err != nil {
		return DiveResult{}, err
	}
	acc := fnet / sub.EffectiveMass()

	return DiveResult{
		Index:            0,
		State:            state,
		Fraction:         frac,
		RequiredBallast:  req,
		IsPossible:       possible,
		EffectiveDensity: eff,
		NetForce:         fnet,
		Acceleration:     acc,
	}, nil
}

func BatchAnalyzeFleet(subs []Submarine, fluid Seawater) ([]DiveResult, error) {
	if err := fluid.Validate(); err != nil {
		return nil, err
	}
	if subs == nil {
		return []DiveResult{}, nil
	}
	results := make([]DiveResult, len(subs))
	for i, sub := range subs {
		if err := sub.Validate(); err != nil {
			results[i] = DiveResult{Index: i, State: "invalid"}
			continue
		}
		// compute using AnalyzeDive but preserve index
		res, err := AnalyzeDive(sub, fluid)
		if err != nil {
			results[i] = DiveResult{Index: i, State: "invalid"}
			continue
		}
		res.Index = i
		results[i] = res
	}
	return results, nil
}
GO
