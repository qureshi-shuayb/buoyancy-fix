# control-rod-worth-scram-v2
Python point kinetics 6-group with control rod S-curve worth and SCRAM transient. Agent implements /app/rod_scram.py simulate returning power, reactivity, period, shutdown margin, peak power. Hard part is stiff implicit kinetics solver, nonlinear S-curve, SCRAM drop profile, Doppler feedback.
