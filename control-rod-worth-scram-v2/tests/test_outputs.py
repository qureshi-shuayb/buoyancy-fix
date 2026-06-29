import importlib.util, math, pytest
def load():
    s=importlib.util.spec_from_file_location("rod_scram","/app/rod_scram.py"); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
def _at(x,i): return x[i] if isinstance(x,(list,tuple)) else x
def _solve(A,b):
    n=len(b); M=[A[i][:]+[b[i]] for i in range(n)]
    for col in range(n):
        pr=max(range(col,n),key=lambda r:abs(M[r][col])); M[col],M[pr]=M[pr],M[col]; piv=M[col][col] or 1e-14
        for j in range(col,n+1): M[col][j]/=piv
        for r in range(n):
            if r==col: continue
            f=M[r][col]
            for j in range(col,n+1): M[r][j]-=f*M[col][j]
    return [M[i][n] for i in range(n)]
def ref(dt,n_steps,rod_position,rod_total_worth,H,scram_start,scram_duration,initial_power,beta,beta_groups,lambda_groups,Lambda,alpha_doppler,T_f0,tau_f,k_f,use_doppler):
    def worth(z): return rod_total_worth*(1-math.cos(math.pi*z/H))/2
    n=1.0; c=[beta_groups[i]/(Lambda*lambda_groups[i]) for i in range(6)]; Tf=T_f0+k_f*initial_power
    power=[initial_power]; react=[0.0]; period=[1e9]
    for step in range(n_steps):
        zp=_at(rod_position,step); t=step*dt
        if scram_start is not None and t>=scram_start: frac=min(1.0,(t-scram_start)/scram_duration); zp=H*(1-frac)
        rho_ext=worth(zp); rho_f=alpha_doppler*math.log(max(Tf,1)/T_f0) if use_doppler else 0.0; rho=rho_ext+rho_f
        A=[[0]*7 for _ in range(7)]; A[0][0]=(rho-beta)/Lambda
        for i in range(6): A[0][i+1]=lambda_groups[i]; A[i+1][0]=beta_groups[i]/Lambda; A[i+1][i+1]=-lambda_groups[i]
        M=[[0]*7 for _ in range(7)]
        for i in range(7):
            for j in range(7): M[i][j]=-dt*A[i][j]
            M[i][i]+=1
        xk=[n]+c; xn=_solve(M,xk); n_next=xn[0]; c_next=xn[1:]; P_next=initial_power*n_next; Pk=initial_power*n
        Tf_next=Tf+dt*(T_f0+k_f*Pk-Tf)/tau_f
        per=1e9
        if step>0: dP=(P_next-power[-1])/dt; per=P_next/dP if abs(dP)>1e-9 else 1e9
        power.append(P_next); react.append(rho); period.append(per); n,c,Tf=n_next,c_next,Tf_next
    return {"power":power,"reactivity":react,"period":period,"shutdown_margin":-rod_total_worth,"peak_power":max(power)}
BASE=dict(dt=0.01,n_steps=200,rod_total_worth=0.05,H=3.7,scram_start=None,scram_duration=1.0,initial_power=1e8,beta=0.0065,beta_groups=[0.0065*0.033,0.0065*0.219,0.0065*0.196,0.0065*0.395,0.0065*0.115,0.0065*0.042],lambda_groups=[0.0124,0.0305,0.111,0.301,1.14,3.01],Lambda=0.001,alpha_doppler=-0.002,T_f0=600,tau_f=5,k_f=1e-6,use_doppler=True)
def run(a,p): return a.simulate(**p)
def assert_m(o,r):
    expected_keys = {"power","reactivity","period","shutdown_margin","peak_power"}
    assert isinstance(o, dict)
    assert set(o.keys()) == expected_keys, f"output keys must be exactly {expected_keys}, got {set(o.keys())}"
    for k in ("power","reactivity","period"): assert len(o[k])==len(r[k])
    for key in ("power","reactivity","period"):
        for a,b in zip(o[key],r[key]): assert math.isclose(a,b,rel_tol=1e-2,abs_tol=1e-2)
    assert math.isclose(o["peak_power"],r["peak_power"],rel_tol=1e-2); assert math.isclose(o["shutdown_margin"],r["shutdown_margin"],rel_tol=1e-2)
def test_slow():
    a=load(); p=dict(BASE); p.update(n_steps=300,rod_position=[3.7*min(1,i/300) for i in range(300)]); r=ref(**p); o=run(a,p); assert_m(o,r)
def test_scram_hfp():
    a=load(); p=dict(BASE); p.update(n_steps=400,rod_position=3.7,scram_start=1.0,scram_duration=0.5); r=ref(**p); o=run(a,p); assert_m(o,r)
def test_scram_hzp():
    a=load(); p=dict(BASE); p.update(initial_power=1e3,use_doppler=False,n_steps=400,rod_position=3.7,scram_start=1.0); r=ref(**p); o=run(a,p); assert_m(o,r)
def test_rod_drop():
    a=load(); p=dict(BASE); p.update(n_steps=200,rod_position=[3.7]*10+[0.0]*190); r=ref(**p); o=run(a,p); assert_m(o,r)


def test_stdlib_only():
    """Ensure agent solution uses only Python standard library per spec."""
    import pathlib, ast, os
    agent_path = "/app/rod_scram.py"
    if not os.path.exists(agent_path):
        candidates = list(pathlib.Path(__file__).parent.parent.glob('solution/*.py'))
        if candidates:
            agent_path = str(candidates[0])
        else:
            return
    src = pathlib.Path(agent_path).read_text()
    tree = ast.parse(src)
    allowed = {"math","sys","os","json","typing","collections","itertools","functools","heapq","bisect","random","statistics","decimal","fractions","datetime"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                root = alias.name.split('.')[0]
                assert root in allowed, f"disallowed import {alias.name}"
        if isinstance(node, ast.ImportFrom):
            root = (node.module or '').split('.')[0]
            assert root in allowed, f"disallowed import from {node.module}"

