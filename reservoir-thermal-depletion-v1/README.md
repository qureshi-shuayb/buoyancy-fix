# reservoir-thermal-depletion-v1

## Description
Implement lumped 0D geothermal reservoir thermal depletion ODE in Python with explicit Euler integration, now hardened with mandatory list schedules for m_in and m_out, non-linear radiative heat loss term, trapezoidal lifetime integral, linear interpolation breakthrough, and expanded outputs Q_loss_trajectory, power_output_MW, cumulative_energy_MWh. Model accounts for rock heat capacity, porosity-defined fluid mass, reinjection enthalpy inflow, production enthalpy outflow, linear plus Stefan-Boltzmann radiative heat loss to ambient. Tests cover temperature trajectory elementwise tightened tolerance, thermal breakthrough year with interpolation, lifetime extracted thermal energy in MWh via trapezoidal rule, average temperature, Q loss trajectory, power and cumulative energy. Naive implementations ignoring radiative loss, omitting rock thermal mass, using wrong Euler order or start-of-step integral, or mis-defining breakthrough without interpolation are caught by dedicated test cases targeting medium-hard difficulty.

## Completion Rates

| Model | Pass Rate |
|-------|-----------|
| Oracle | 3/3 (100%) |
| Opus 4.1 | TBD pending cloud re-run after v5 hardening |
| Avocado | TBD |
| GPT-5 | TBD |
| Sonnet 4 | TBD |

## Model Analysis

Oracle passes locally with reference solution matching pinned explicit Euler order, trapezoidal energy integral, radiative Q loss, and interpolated breakthrough. Projected difficulty medium-hard targeting 2-8% pass band (1-2/5). Tolerances tightened to 5e-5 relative 1e-3 absolute for temperature and trajectories, 1e-7 years breakthrough, 5e-5 relative lifetime, 1e-3 absolute avg_T to discriminate naive variants while allowing floating rounding. Successful solutions demonstrate correct C_total rock+fluid, Q_loss = Q_loss_coeff*(T-T_ambient) + Q_loss_coeff_rad*sigma*(T^4 - T_ambient^4) with sigma 5.67e-8, explicit Euler Tn+1 = Tn + dt*dTdt, trapezoidal power using (Tn+Tn1)/2, breakthrough linear interpolation between steps, mandatory list handling for m_in m_out time series, and correct 7 output keys including Q_loss_trajectory length n_steps, power_output_MW length n_steps, cumulative_energy_MWh length n_steps+1. Failures typically: treat m_in/m_out as scalar ignoring list schedule causing >2% lifetime error in varying schedule test, omit radiative term causing >2C overprediction in high radiative case, use start-of-step T_n instead of trapezoidal average causing lifetime bias beyond 1e-4 tolerance, use discrete breakthrough index without interpolation causing 1e-7 year mismatch, wrong sign on Q_loss leading to divergence, omit rock mass halving C_total, average wrong length, missing new output keys.

## Anti-Cheating Analysis

Outputs depend on continuous physical inputs across transient scenarios with stateful ODE coupling and non-linear radiative term; no small constant to memorize. Grader runs out-of-process not in `/app`. Reference recomputed independently.

- **Hardcoded outputs**: Tests use continuous physical parameters across multiple transient scenarios including varying schedule sharp step and high radiative loss generated at runtime with tightened tolerances; pre-computed answers cannot match without implementing full model including radiative term and trapezoidal integral.
- **Overfitting to visible tests**: Test inputs parameterized across multiple regimes covering edge cases of heat loss linear+ radiative, varying production schedule list mandatory, no-breakthrough case, large dt explicit Euler sensitivity, breakthrough interpolation edge.
- **Modifying test files**: Tests mounted read-only by Codimango at `/tests/`; test.sh applies chmod 700 defense during pytest to mitigate C18 in-process oracle surface.
- **Bypassing intended solution path**: Tests verify full trajectories including Q_loss_trajectory power_output_MW cumulative_energy_MWh not just final output, so shortcutting detected by numeric drift. Stdlib-only check enforced to prevent external library bypass. Naive trap asserts linear-only model fails radiative dominant case by >2C and constant-m_out assumption fails varying schedule test.

<!-- v5 hardening to target 2-8% band with oracle 3/3 validated locally as of 2026-07-05 -->
