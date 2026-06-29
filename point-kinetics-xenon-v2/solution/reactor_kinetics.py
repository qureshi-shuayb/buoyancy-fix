import math

def _solve_linear(A, b):
    """Solve Ax=b for 7x7 via Gaussian elimination with partial pivoting. A is list of lists, b list."""
    n = len(b)
    # augment
    M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for col in range(n):
        # pivot
        pivot_row = max(range(col, n), key=lambda r: abs(M[r][col]))
        if abs(M[pivot_row][col]) < 1e-14:
            continue
        if pivot_row != col:
            M[col], M[pivot_row] = M[pivot_row], M[col]
        piv = M[col][col]
        # normalize pivot row
        for j in range(col, n+1):
            M[col][j] /= piv
        # eliminate other rows
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

def simulate(
    dt, n_steps, rod_rho, initial_power, beta, beta_groups, lambda_groups, Lambda,
    gamma_I, gamma_Xe, lambda_I, lambda_Xe, sigma_Xe, Sigma_f_phi_coeff, nu_Sigma_f,
    alpha_f, alpha_m, T_f0, T_m0, tau_f, tau_m, k_f, k_m,
):
    n0 = 1.0
    # initial precursor equilibrium
    c = [beta_groups[i] / (Lambda * lambda_groups[i]) * n0 for i in range(6)]
    n = n0
    P0 = float(initial_power)
    # initial I Xe equilibrium
    I0 = gamma_I * Sigma_f_phi_coeff * P0 / lambda_I
    Xe0 = (gamma_Xe * Sigma_f_phi_coeff * P0 + lambda_I * I0) / (lambda_Xe + sigma_Xe * Sigma_f_phi_coeff * P0)
    T_f = T_f0 + k_f * P0
    T_m = T_m0 + k_m * P0

    power_traj = [P0]
    iodine_traj = [I0]
    xenon_traj = [Xe0]
    # initial reactivity should be ~0; compute to verify
    rho_init = _at(rod_rho, 0) + alpha_f*(T_f - T_f0) + alpha_m*(T_m - T_m0) - sigma_Xe*Xe0/nu_Sigma_f
    reactivity_traj = [rho_init]

    I = I0
    Xe = Xe0
    # state vectors
    for step in range(n_steps):
        rod = _at(rod_rho, step)
        # reactivity at beginning
        rho_k = rod + alpha_f*(T_f - T_f0) + alpha_m*(T_m - T_m0) - sigma_Xe*Xe/nu_Sigma_f
        # build A matrix 7x7
        A = [[0.0]*7 for _ in range(7)]
        A[0][0] = (rho_k - beta) / Lambda
        for i in range(6):
            A[0][i+1] = lambda_groups[i]
            A[i+1][0] = beta_groups[i] / Lambda
            A[i+1][i+1] = -lambda_groups[i]
        # Build I - dt*A
        M = [[0.0]*7 for _ in range(7)]
        for i in range(7):
            for j in range(7):
                M[i][j] = -dt * A[i][j]
            M[i][i] += 1.0
        x_k = [n] + c
        x_next = _solve_linear(M, x_k)
        n_next = x_next[0]
        c_next = x_next[1:]
        P_next = initial_power * n_next / n0
        P_k = initial_power * n / n0
        # explicit update slow dynamics using P_k
        I_next = I + dt * (gamma_I * Sigma_f_phi_coeff * P_k - lambda_I * I)
        Xe_next = Xe + dt * (gamma_Xe * Sigma_f_phi_coeff * P_k + lambda_I * I - lambda_Xe * Xe - sigma_Xe * Sigma_f_phi_coeff * P_k * Xe)
        if I_next < 0:
            I_next = 0.0
        if Xe_next < 0:
            Xe_next = 0.0
        T_f_next = T_f + dt * (T_f0 + k_f * P_k - T_f) / tau_f
        T_m_next = T_m + dt * (T_m0 + k_m * P_k - T_m) / tau_m
        # reactivity at end for output; use rod at next step if available else current
        rod_next = _at(rod_rho, step+1) if isinstance(rod_rho, (list, tuple)) and step+1 < n_steps else rod
        rho_next = rod_next + alpha_f*(T_f_next - T_f0) + alpha_m*(T_m_next - T_m0) - sigma_Xe*Xe_next/nu_Sigma_f

        power_traj.append(P_next)
        iodine_traj.append(I_next)
        xenon_traj.append(Xe_next)
        reactivity_traj.append(rho_next)

        # advance state
        n, c, I, Xe, T_f, T_m = n_next, c_next, I_next, Xe_next, T_f_next, T_m_next

    peak_power = max(power_traj)
    final_xenon = xenon_traj[-1]
    return {
        "power": power_traj,
        "xenon": xenon_traj,
        "iodine": iodine_traj,
        "reactivity": reactivity_traj,
        "peak_power": float(peak_power),
        "final_xenon": float(final_xenon),
    }
