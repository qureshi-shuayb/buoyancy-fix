# pwr-primary-loop-v2
## Description
Python lumped-parameter PWR primary loop with core, SG, pressurizer, pump coastdown to natural circulation. Agent implements simulate in /app/pwr_loop.py returning temperature, flow, pressure trajectories. Hard part is coupled nonlinear flow solve each step, pressurizer volume-pressure coupling, LMTD heat transfer, decay heat after trip, transition forced to natural circulation.
## Grading
Independent reference over 4 scenarios: steady normal, pump trip coastdown, steam demand step, loss of feedwater heating. Verifier writes reward.txt.
