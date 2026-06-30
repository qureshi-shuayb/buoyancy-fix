import math
def _solve(A,b):
    n=len(b); M=[A[i][:]+[b[i]] for i in range(n)]
    for col in range(n):
        pr=max(range(col,n),key=lambda r:abs(M[r][col]))
        if abs(M[pr][col])<1e-14: continue
        M[col],M[pr]=M[pr],M[col]; piv=M[col][col]
        for j in range(col,n+1): M[col][j]/=piv
        for r in range(n):
            if r==col: continue
            f=M[r][col]
            if f: 
                for j in range(col,n+1): M[r][j]-=f*M[col][j]
    return [M[i][n] for i in range(n)]
def _at(x,i): return x[i] if isinstance(x,(list,tuple)) else x
def simulate(dt,n_steps,rod_position,rod_total_worth,H,scram_start,scram_duration,initial_power,beta,beta_groups,lambda_groups,Lambda,alpha_doppler,T_f0,tau_f,k_f,use_doppler):
    def worth(z): return rod_total_worth*(1-math.cos(math.pi*z/H))/2
    n=1.0; c=[beta_groups[i]/(Lambda*lambda_groups[i]) for i in range(6)]; Tf=T_f0+k_f*initial_power
    power=[initial_power]; react=[0.0]; period=[1e9]
    for step in range(n_steps):
        zp=_at(rod_position,step)
        t=step*dt
        if scram_start is not None and t>=scram_start:
            frac=min(1.0,(t-scram_start)/scram_duration); zp=H*(1-frac)  # linear drop defined
        rho_ext=worth(zp)
        rho_f= alpha_doppler*math.log(max(Tf,1)/T_f0) if use_doppler else 0.0
        rho=rho_ext+rho_f
        A=[[0]*7 for _ in range(7)]; A[0][0]=(rho-beta)/Lambda
        for i in range(6): A[0][i+1]=lambda_groups[i]; A[i+1][0]=beta_groups[i]/Lambda; A[i+1][i+1]=-lambda_groups[i]
        M=[[0]*7 for _ in range(7)]
        for i in range(7):
            for j in range(7): M[i][j]=-dt*A[i][j]
            M[i][i]+=1
        xk=[n]+c; xn=_solve(M,xk); n_next=xn[0]; c_next=xn[1:]; P_next=initial_power*n_next
        Pk=initial_power*n
        Tf_next=Tf+dt*(T_f0+k_f*Pk-Tf)/tau_f
        # period approx
        if step>0 and power[-1]>0 and P_next>0:
            dP=(P_next-power[-1])/dt; per= P_next/dP if abs(dP)>1e-9 else 1e9
        else: per=1e9
        power.append(P_next); react.append(rho); period.append(per)
        n,c,Tf=n_next,c_next,Tf_next
    # shutdown margin as negative reactivity at fully inserted rod at end
    sm = -rod_total_worth
    return {"power":power,"reactivity":react,"period":period,"shutdown_margin":sm,"peak_power":max(power)}
