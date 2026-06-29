#!/bin/bash
set -euo pipefail
mkdir -p /app
cd /app
cat > /app/reactor_kinetics.py <<'PYEOF'
import math

def _solve_linear(A, b):
    n = len(b)
    M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for col in range(n):
        pivot_row = max(range(col, n), key=lambda r: abs(M[r][col]))
        if abs(M[pivot_row][col]) < 1e-14:
            continue
        if pivot_row != col:
            M[col], M[pivot_row] = M[pivot_row], M[col]
        piv = M[col][col]
        for j in range(col, n+1):
            M[col][j] /= piv
        for r in range(n):
            if r == col:
                continue
            factor = M[r][col]
            if factor == 0:
                continue
            for j in range(col, n+1):
                M[r][j] -= factor * M[col][j]
    return [M[i][n] for i in range(n)]

def _at(x, i):
    return x[i] if isinstance(x, (list, tuple)) else x

def simulate(dt, n_steps, rod_rho, initial_power, beta, beta_groups, lambda_groups, Lambda, gamma_I, gamma_Xe, lambda_I, lambda_Xe, sigma_Xe, Sigma_f_phi_coeff, nu_Sigma_f, alpha_f, alpha_m, T_f0, T_m0, tau_f, tau_m, k_f, k_m):
    n0 = 1.0
    c = [beta_groups[i] / (Lambda * lambda_groups[i]) * n0 for i in range(6)]
    n = n0
    P0 = float(initial_power)
    I = gamma_I * Sigma_f_phi_coeff * P0 / lambda_I
    Xe = (gamma_Xe * Sigma_f_phi_coeff * P0 + lambda_I * I) / (lambda_Xe + sigma_Xe * Sigma_f_phi_coeff * P0)
    Tf = T_f0 + k_f * P0
    Tm = T_m0 + k_m * P0
    power = [P0]; iodine = [I]; xenon = [Xe]
    rho0 = _at(rod_rho,0) + alpha_f*(Tf-T_f0)+alpha_m*(Tm-T_m0)-sigma_Xe*Xe/nu_Sigma_f
    reactivity = [rho0]
    for step in range(n_steps):
        rod = _at(rod_rho, step)
        rho_k = rod + alpha_f*(Tf-T_f0)+alpha_m*(Tm-T_m0)-sigma_Xe*Xe/nu_Sigma_f
        A = [[0.0]*7 for _ in range(7)]
        A[0][0] = (rho_k - beta) / Lambda
        for i in range(6):
            A[0][i+1] = lambda_groups[i]
            A[i+1][0] = beta_groups[i] / Lambda
            A[i+1][i+1] = -lambda_groups[i]
        M = [[0.0]*7 for _ in range(7)]
        for i in range(7):
            for j in range(7):
                M[i][j] = -dt * A[i][j]
            M[i][i] += 1.0
        xk = [n] + c
        xnext = _solve_linear(M, xk)
        n_next = xnext[0]; c_next = xnext[1:]
        P_next = initial_power * n_next / n0
        P_k = initial_power * n / n0
        I_next = I + dt * (gamma_I * Sigma_f_phi_coeff * P_k - lambda_I * I)
        Xe_next = Xe + dt * (gamma_Xe * Sigma_f_phi_coeff * P_k + lambda_I * I - lambda_Xe * Xe - sigma_Xe * Sigma_f_phi_coeff * P_k * Xe)
        if I_next < 0: I_next = 0.0
        if Xe_next < 0: Xe_next = 0.0
        Tf_next = Tf + dt * (T_f0 + k_f * P_k - Tf) / tau_f
        Tm_next = Tm + dt * (T_m0 + k_m * P_k - Tm) / tau_m
        rod_next = _at(rod_rho, step+1) if isinstance(rod_rho,(list,tuple)) and step+1 < n_steps else rod
        rho_next = rod_next + alpha_f*(Tf_next-T_f0)+alpha_m*(Tm_next-T_m0)-sigma_Xe*Xe_next/nu_Sigma_f
        power.append(P_next); iodine.append(I_next); xenon.append(Xe_next); reactivity.append(rho_next)
        n,c,I,Xe,Tf,Tm = n_next,c_next,I_next,Xe_next,Tf_next,Tm_next
    return {"power":power,"xenon":xenon,"iodine":iodine,"reactivity":reactivity,"peak_power":float(max(power)),"final_xenon":float(xenon[-1])}
PYEOF
echo "reactor_kinetics.py written"
