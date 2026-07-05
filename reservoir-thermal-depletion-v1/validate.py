#!/usr/bin/env python3
"""Local oracle validation without pytest dependency."""
import importlib.util, math, sys, os
SOLUTION = os.path.join(os.path.dirname(__file__), 'solution', 'reservoir_depletion.py')
spec = importlib.util.spec_from_file_location('agent', SOLUTION)
agent = importlib.util.module_from_spec(spec); spec.loader.exec_module(agent)

def _at(x,i): return x[i] if isinstance(x,(list,tuple)) else x

def ref_simulate(dt,n_steps,volume,porosity,rho_rock,c_rock,rho_fluid,c_fluid,T_initial,T_inj,m_in,m_out,Q_loss_coeff,T_ambient,breakthrough_T_drop=10.0):
    M_rock=volume*(1-porosity)*rho_rock
    M_fluid=volume*porosity*rho_fluid
    C_total=M_rock*c_rock+M_fluid*c_fluid
    T=[float(T_initial)]
    lifetime_J=0.0
    sec_per_year=31536000.0
    for n in range(n_steps):
        Tn=T[-1]
        m_out_n=_at(m_out,n)
        Qloss=Q_loss_coeff*(Tn-T_ambient)
        dTdt=(m_in*c_fluid*T_inj - m_out_n*c_fluid*Tn - Qloss)/C_total
        T.append(Tn+dt*dTdt)
        lifetime_J += m_out_n*c_fluid*max(0.0,Tn-T_inj)*dt
    breakthrough=None
    for i,Ti in enumerate(T):
        if T_initial-Ti >= breakthrough_T_drop-1e-12:
            breakthrough=i*dt/sec_per_year; break
    return {"T_reservoir":T,"breakthrough_year":breakthrough,"lifetime_MWh":lifetime_J/3.6e9,"avg_T":sum(T)/len(T)}

def assert_matches(out,ref):
    assert len(out["T_reservoir"])==len(ref["T_reservoir"])
    for a,b in zip(out["T_reservoir"], ref["T_reservoir"]):
        assert math.isclose(a,b,rel_tol=1e-3,abs_tol=0.01)
    br_o=out["breakthrough_year"]; br_r=ref["breakthrough_year"]
    if br_r is None: assert br_o is None
    else: assert br_o is not None and math.isclose(br_o,br_r,rel_tol=1e-6,abs_tol=1e-6)
    assert math.isclose(out["lifetime_MWh"], ref["lifetime_MWh"], rel_tol=1e-3, abs_tol=0.01)
    assert math.isclose(out["avg_T"], ref["avg_T"], rel_tol=1e-6, abs_tol=0.01)

cases=[
    (86400*30,360,1e8,0.1,2650,900,950,4180,200,60,50,50,1000,15,10),
    (86400*10,720,5e7,0.15,2700,850,980,4000,180,50,40,40,0,20,5),
    (86400*15,480,2e8,0.08,2600,920,920,4100,220,70,60,60,2500,12,15),
    (86400*7,1200,3e8,0.2,2550,880,1000,4184,160,40,30,30,500,18,8),
    (86400*30,240,1e7,0.05,2800,1000,900,3800,250,80,80,80,5000,10,20),
]
all_pass=True
for idx,(dt,ns,vol,por,rr,cr,rf,cf,Ti,Tij,mi,mo,Qlc,Ta,btd) in enumerate(cases,1):
    ref=ref_simulate(dt,ns,vol,por,rr,cr,rf,cf,Ti,Tij,mi,mo,Qlc,Ta,btd)
    out=agent.simulate(dt,ns,vol,por,rr,cr,rf,cf,Ti,Tij,mi,mo,Qlc,Ta,btd)
    try:
        assert_matches(out,ref)
        print(f"case{idx}: PASS  breakthrough={ref['breakthrough_year']} lifetime={ref['lifetime_MWh']:.1f} avg={ref['avg_T']:.2f}")
    except AssertionError as e:
        print(f"case{idx}: FAIL {e}"); all_pass=False
print("ORACLE PASS" if all_pass else "ORACLE FAIL")
sys.exit(0 if all_pass else 1)
