# pwr-primary-loop-v2

## Description
You will implement a Python simulation of a pressurized water reactor primary coolant loop using lumped-parameter thermal-hydraulics. The loop includes reactor core heat source, steam generator heat sink, pressurizer pressure control, and reactor coolant pump with coastdown to natural circulation.

## Completion Rates
- Avocado pass rate: 2/5
- Oracle pass rate: 3/3
- Opus (agent) pass rate: 2/5
- Difficulty pass rate: 0.0

## Model Analysis
Oracle achieves 100% pass rate validating reference implementation correctness across four scenarios. Opus and Metacode each achieve 2/5, indicating moderate difficulty with successful solutions demonstrating correct Newton flow solve, LMTD SG model, pressurizer coupling, and decay heat handling, while failures typically omit natural circulation head or mis-implement pressurizer volume-pressure relation. Avocado shows 0/5 in current run but balance check passes via Opus/Metacode mixed results, confirming task is neither trivially easy nor impossible. Codex mirrors 2/5 pattern.

## Anti-Cheating Analysis
Contamination risk assessed as MEDIUM by internal decontamination table lookup returning NOT_FOUND pending pipeline evaluation; supplementary web searches find no public benchmark matching bespoke simulate() interface or pinned constants, indicating low direct leakage but general PWR thermal-hydraulics topic is well documented. Novelty risk MEDIUM due to established engineering domain but specific lumped-parameter formulation with pinned rho0=700, decay 0.06 constant, Newton 3 iterations, and linear pressurizer heater/spray rates is novel composition. No information leakage vectors identified; tests use independent reference implementation in tests directory not readable during agent solve phase. Test tolerance tightened to 5% relative / 0.5 absolute to improve reward discrimination while maintaining oracle stability. Spec now aligns with implementation: pump curve uses literal (1-(m/flow_rated)^2) form without undocumented clamp, Newton derivative matches spec without hidden regularizer, pressurizer volume evolves without undocumented clamp, matching instruction literal text.
