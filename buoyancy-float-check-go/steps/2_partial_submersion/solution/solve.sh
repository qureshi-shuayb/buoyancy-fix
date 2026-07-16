#!/bin/bash
set -euo pipefail

cat > /app/partial.go <<'GO'
package buoyancy

type SubmersionResult struct {
	Index    int
	State    string
	Fraction float64
	Depth    float64
	Density  float64
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
	return fraction * obj.Height, nil
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

	return SubmersionResult{
		Index:    0,
		State:    state,
		Fraction: fraction,
		Depth:    fraction * obj.Height,
		Density:  density,
	}, nil
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

		result, err := AnalyzeObject(obj, fluid)
		if err != nil {
			results[i] = SubmersionResult{Index: i, State: "invalid"}
			continue
		}
		result.Index = i
		results[i] = result
	}
	return results, nil
}
GO
