# reservoir-thermal-depletion-v1

## Description
Implement lumped 0D geothermal reservoir thermal depletion ODE in Python with explicit Euler integration hardened v9, mandatory list schedules for m_in and m_out with no scalar fallback test rejects scalar, non-linear Stefan-Boltzmann radiative heat loss term sigma 5.67e-8, trapezoidal lifetime integral mandatory, linear interpolation breakthrough, explicit seconds_per_year constant 31536000.0, and expanded 7-key outputs Q_loss_trajectory, power_output_MW, cumulative_energy_MWh. Model accounts for rock heat capacity, porosity-defined fluid mass, reinjection enthalpy inflow, production enthalpy outflow, linear plus radiative heat loss to ambient. Tests cover temperature trajectory elementwise tightened to 1e-6 relative 1e-4 absolute tolerance, thermal breakthrough year with interpolation 1e-11, lifetime extracted thermal energy in MWh via trapezoidal rule, average temperature 1e-9, Q loss trajectory, power and cumulative energy. Naive implementations ignoring radiative loss, omitting rock thermal mass, using wrong Euler order or start-of-step integral instead of trapezoidal, or mis-defining breakthrough without interpolation are caught by dedicated test cases targeting hard difficulty v9.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Avocado | 0/5 (0%) |
| Opus 4.1 | 0/5 (0%) |
| GPT-5 | 0/5 (0%) |
| Sonnet 4 | 0/5 (0%) |

## Model Analysis

Oracle passes locally 3/3 with reference solution matching pinned explicit Euler order, trapezoidal energy integral mandatory, radiative Q loss with sigma 5.67e-8, seconds_per_year 31536000.0 explicit, and interpolated breakthrough. Projected difficulty hard 0% band not medium-hard 2-8%, targeting 0/5 pass rate across Avocado, Opus 4.1, GPT-5, Sonnet 4. Tolerances tightened v9 to 1e-6 relative 1e-4 absolute for temperature trajectories Q_loss_trajectory power_output_MW cumulative_energy_MWh, 1e-11 years breakthrough, 1e-6 relative lifetime_MWh, 1e-9 relative avg_T to discriminate naive variants while allowing floating rounding across 21 scenarios plus scalar rejection test. Successful solutions demonstrate correct C_total rock+fluid, Q_loss = Q_loss_coeff*(T-T_ambient) + Q_loss_coeff_rad*sigma*(T^4 - T_ambient^4) with sigma 5.67e-8 mandatory radiative term, explicit Euler Tn+1 = Tn + dt*dTdt, trapezoidal power using (Tn+Tn1)/2 mandatory for lifetime integral, breakthrough linear interpolation between steps using seconds_per_year 31536000.0, mandatory list handling for m_in m_out time series with TypeError on scalar per v9, and correct 7 output keys including Q_loss_trajectory length n_steps, power_output_MW length n_steps, cumulative_energy_MWh length n_steps+1. Failures typically: treat m_in/m_out as scalar ignoring list schedule causing >2% lifetime error in varying schedule test and scalar rejection test failure, omit radiative term causing >2C overprediction in high radiative case, use start-of-step T_n instead of trapezoidal average causing lifetime bias beyond 1e-6 tolerance, use discrete breakthrough index without interpolation causing 1e-11 year mismatch, wrong sign on Q_loss leading to divergence, omit rock mass halving C_total, average wrong length, missing new output keys.

## Anti-Cheating Analysis

Outputs depend on continuous physical inputs across transient scenarios with stateful ODE coupling and non-linear radiative term sigma 5.67e-8 mandatory; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently v9 hardened.

- **Hardcoded outputs**: Tests use continuous physical parameters across 21 transient scenarios including varying schedule sharp step and high radiative loss generated at runtime with tightened 1e-6 tolerances; pre-computed answers cannot match without implementing full model including radiative term and trapezoidal integral mandatory.
- **Overfitting to visible tests**: Test inputs parameterized across multiple regimes covering edge cases of heat loss linear+ radiative, varying production schedule list mandatory with scalar rejection test, no-breakthrough case, large dt explicit Euler sensitivity, breakthrough interpolation edge, 21 scenarios plus scalar rejection total.
- **Modifying test files**: Tests mounted read-only by Codimango at `/tests/`; test.sh applies chmod 700 defense during pytest to mitigate C18 in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories including Q_loss_trajectory power_output_MW cumulative_energy_MWh not just final output, so shortcutting detected by numeric drift beyond 1e-6 tolerance. Stdlib-only check enforced to prevent external library bypass. Naive trap asserts linear-only model fails radiative dominant case by >2C and constant-m_out assumption fails varying schedule test and scalar test rejects non-list.

<!-- v9 hardening 2026-07-07 to hard Oracle 3/3 Avocado 0/5 Opus 0/5 GPT 0/5 Sonnet 0/5 with 1e-6 rel tolerance radiative sigma 5.67e-8 trapezoidal mandatory 7 keys seconds_per_year 31536000 explicit scalar rejection -->
