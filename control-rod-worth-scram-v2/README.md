# control-rod-worth-scram-v2
Python point kinetics 6-group with control rod S-curve worth and SCRAM transient. Agent implements /app/rod_scram.py simulate returning power, reactivity, period, shutdown margin, peak power. Hard part is stiff implicit kinetics solver, nonlinear S-curve, SCRAM drop profile, Doppler feedback.

## Description
Implements point reactor kinetics with six delayed neutron groups responding to time-varying control rod worth following cosine S-curve integral worth and linear SCRAM drop profile. Optional Doppler feedback via fuel temperature lag limits power excursion. Returns full trajectories and shutdown margin.

## Completion Rates
- Oracle validation: 3/3 passed locally after fix (previously passing).
- Agent pass rates before fix: avocado 0/5, opus 0/5, gpt 0/5 — too hard due to spec ambiguity on initial fuel temperature and type handling.
- Expected after fix: target 1-4/5 per agent (GOOD difficulty band).

## Model Analysis
Root cause of 0/5 failure: agents initialized fuel temperature Tf to T_f0 (600K) while reference originally used Tf0 + k_f*P0 steady-state offset, causing ~8% peak power overshoot exceeding 2% tolerance. Agents also added defensive float() casts breaking None and list handling for rod_position and scram_start, due to spec not explicitly stating union types. Fix aligns reference to Tf=T_f0 initial condition matching intuitive interpretation, and spec ambiguity mitigated via code robustness in reference implementation (tests unchanged in interface but reference updated). Remaining risk is solver numeric variance; tolerance 2% retained as convergent integrators agree within <1% in subcritical regime.

## Anti-Cheating Analysis
- Tests recompute independent reference in-process; no hardcoded outputs accepted.
- Output key set strictly enforced; extra keys fail.
- Harbor masks tests/ at runtime preventing leakage.
- Solution uses only stdlib math; no numpy allowed.
- Four scenarios cover slow withdrawal, SCRAM HFP, SCRAM HZP, rod drop — naive explicit Euler or missing S-curve nonlinearity fails tight tolerances.
