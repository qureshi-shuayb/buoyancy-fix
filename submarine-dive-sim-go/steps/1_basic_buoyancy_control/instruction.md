# Step 1: Stratified Ocean – ULTRA-ULTRA-HARD – 44 Constants, Quadruple Cabbeling, 26-Term Pressure, 5th Derivative, P³ Non-Linear

## Overview
Step 1 of 2. **ULTRA-ULTRA-HARD** version – 44 exact constants, quadruple cabbeling s²t², compensated layer pyc1*pyc2*s, baroclinic z*s*t*(1-expI), z² thermosteric/halosteric, second-order vorticity z²*(1-expDm), cubic+quartic density, 26-term pressure analytic requiring generic product integrals for up to 4 scales (2^4=16 subsets) plus ∫z*exp and ∫z²*exp polynomial-exponential integrals, derivatives up to 5th order via mul2/mul3 Leibniz, sound speed with depth-cubed z³ + T³ + (S-35)³ + P²*T + z*P couplings, curvature second derivative, potential temperature 4th order x⁴ + z² lapse, steric P²+P³, volume P³ + thermal-pressure cross, 7 finders via 3000 pts + Brent 200 iter, N² acoustic correction + gradient. Types/constants/methods reused in Step 2 (10-pt log-interp drag, implicit terminal Brent, adaptive RK45, priority heap fleet). Target solve rate <0.1% and ~1800-2200 lines.

**Why this is ULTRA-ULTRA-HARD (vs previous 36-const ultra):**
- **44 constants** fingerprint (8 new beyond 36), all verified.
- **Density 26 terms**: old 20 + 6 new quadruple/compensated/baroclinic/z²-t/z²-s/z²-vort, monotonic inc, diff at 60m without cab/quad/cubic/triple/quadruple/second-order >=1.5 (was 1.0).
- **Pressure 26-term** closed-form: old 18 + 8 new (z² sAnom, z² tAnom, z*s*t*I, s²t², pyc1*pyc2*s, z² vort, P cubic non-linear contributions via depth integrals). Requires helpers `integralZExp(S,z)=S²*(1-exp(-z/S)*(1+z/S))` and `integralZ2Exp(S,z)=2S³ - exp(-z/S)*(S*z²+2S²*z+2S³)` and `∫z*(1-exp)=0.5z² + S*z*exp + S²*exp - S²`, `∫z²*(1-exp)=z³/3 - integralZ2Exp`, plus `integralProduct` via subset enumeration for up to 4 scales (16 masks) and `integralZProduct`, `integralZ2Product`. Missing any mixed/double/z*exp/z²*exp/triple/quad/baroclinic/vort/second-order fails Simpson 500k rel 1e-6 by >30 (was >20).
- **Derivatives up to 5th** analytic via mul2 product rule and mul3 for triple product Leibniz: (f*g)^(n) sum binom, (f*g*h)^(n)=sum n!/(i!j!k!) f^(i)g^(j)h^(k). Verified vs central diff h=0.001 tight: grad 1e-8, second 1e-7, third 1e-6, fourth 1e-5, fifth 1e-4 (was h=0.005 looser).
- **Cabbeling** includes quadruple s²t² + compensated pyc1*pyc2*s.
- **Sound** includes depth-cube z³ + T³ + (S-35)³ + pressure cubic P²*T + z*P couplings using 4 new constants, gradient includes P² chain rule, curvature second derivative required.
- **Potential temperature** 4th order x⁴ + z² lapse: theta=T*(1 -x -Thermobaric*x² -0.2*x³ -0.05*x⁴)*(1 - Adiabatic*z*0.001 - Adiabatic²*z²*1e-7).
- **Steric** with P²+P³: (P/g - rho0*z - Pn*P²*1e-9 - Pc*P³*1e-13)/rho0, tol 1e-4.
- **Volume** with P³ + thermal-pressure cross: exp(-kP + Pn*P²*1e-12 + Pc*P³*1e-18)*(1+alpha*dT+alpha2*dT²+Comp*dT*P*1e-9), bulk modulus K=1/(k -2*Pn*P*1e-12 -3*Pc*P²*1e-18 + Comp*dT*1e-9) positive.
- **Finders**: 3000 pts scan (was 2000) + Brent 200 iter (was 150) for SOFAR, pycno max, spice max, double-diffusive layer, plus new FindThermoclineDepth, FindHaloclineDepth, FindCompensatedLayer (density-compensated root where |beta*dS+gamma*dT| minimal). Brute 0.2m within 1m.
- **New methods**: DensityFifthDerivative, SoundSpeedCurvature, BuoyancyFrequencyGradient, SpicinessTorsion, plus 3 finders = 6 new, total ~35 depth methods.
- **Bulk**: N² gradient dN²/dz, PV, spice torsion third derivative.

## Constants (44 exact values – ULTRA-HARD FINGERPRINT)

```go
const Tolerance = 1e-9
const StandardGravity = 9.81
const StandardSeawaterDensity = 1025.0
const DepthDensityGradient = 0.02
const MinimumVolumeFraction = 0.1
const PycnoclineDelta = 10.0
const PycnoclineScale = 200.0
const DeepPycnoclineDelta = 4.5
const DeepPycnoclineScale = 45.0
const MidPycnoclineDelta = 7.0
const MidPycnoclineScale = 90.0
const HaloclineDelta = 2.5
const HaloclineScale = 30.0
const ThermoclineScale = 120.0
const HullThermalExpansionCoeff = 2.0e-4
const SeawaterViscosity = 0.001
const SalinityDensityCoeff = 0.8
const BulkModulus = 2.2e9
const CabbelingCoeff = 0.06
const HullThermalExpansionQuadCoeff = 1.2e-6
const SoundSpeedPressureQuadCoeff = 1.2e-5
const ThermobaricCoeff = 0.5
const ThermalCouplingCoeff = 0.15
const GammaDepthFactor = 0.0001
const TAnomQuadCoeff = 0.002
const SAnomQuadCoeff = 0.01
// Previous ultra (10)
const SecondOrderCabbelingCoeff = 0.015
const TripleCabbelingCoeff = 0.004
const ThermostericAnomalyCoeff = 0.0008
const HalostericAnomalyCoeff = 0.0003
const AdiabaticLapseRate = 0.0002
const SoundSpeedThermoQuadCoeff = -0.00025
const SoundSpeedSalinityQuadCoeff = 0.00012
const VorticityMixingCoeff = 0.00005
const DoubleDiffusiveMixingScale = 18.0
const PressureNonLinearCoeff = 1.5e-6
// NEW ultra-ultra (8)
const QuadrupleCabbelingCoeff = 0.0009
const CompensatedLayerCoeff = 0.00006
const ThermohalineIntrusionScale = 22.0
const BaroclinicShearCoeff = 0.00004
const ThermostericSecondOrderCoeff = 2.5e-7
const HalostericSecondOrderCoeff = 1.2e-7
const SoundSpeedDepthCubeCoeff = 2e-9
const PressureCubicNonLinearCoeff = 7e-16
```

All 44 must be defined exactly. beta=SalinityDensityCoeff, gamma0=ThermalCouplingCoeff.

## Ocean State

Coordinate z>=0 downward, surface 0. Validation: depth<0 error contains "depth", g<=0 error contains "gravity".

**Salinity:** `S(z)=35+HaloclineDelta*(1-exp(-z/HaloclineScale))`. Surface 35, monotonic increasing.

**Temperature:** `T(z)=15-12*(1-exp(-z/ThermoclineScale))`. Surface 15, decreasing.

**Intermediate Variables – explicit definitions used in density and pressure:**

- `sAnom(z) = HaloclineDelta * (1 - exp(-z / HaloclineScale))` amplitude 2.5 scale 30m
- `tAnom(z) = 12 * (1 - exp(-z / ThermoclineScale))` amplitude 12 scale 120m
- `pyc1(z) = PycnoclineDelta * (1 - exp(-z / PycnoclineScale))` amplitude 10 scale 200m
- `pyc2(z) = DeepPycnoclineDelta * (1 - exp(-z / DeepPycnoclineScale))` amplitude 4.5 scale 45m
- `pyc3(z) = MidPycnoclineDelta * (1 - exp(-z / MidPycnoclineScale))` amplitude 7 scale 90m
- `expS1(z) = exp(-z / PycnoclineScale)`
- `expS2(z) = exp(-z / DeepPycnoclineScale)`
- `expS3(z) = exp(-z / MidPycnoclineScale)`
- `expH(z) = exp(-z / HaloclineScale)`
- `expT(z) = exp(-z / ThermoclineScale)`
- `expDm(z) = exp(-z / DoubleDiffusiveMixingScale)` scale 18m
- `expIntr(z) = exp(-z / ThermohalineIntrusionScale)` scale 22m for baroclinic
- `Smix24 = Hs*Ts/(Hs+Ts)=24m`, `expMix24=exp(-z/Smix24)`
- `Smix22_5 = Mid*Hs/(Mid+Hs)=22.5m`
- `SmixS1_Hs = S1*Hs/(S1+Hs)=26.0869565217m`
- `SmixS2_Ts = S2*Ts/(S2+Ts)=32.7272727272m`
- `SmixS1_Ts = S1*Ts/(S1+Ts)=75m`
- `SmixS2_Hs = S2*Hs/(S2+Hs)=18m`
- `SmixS1_Hs_Ts = 1/(1/S1+1/Hs+1/Ts)=21.4285714286m`
- `SmixS2_Hs_Ts = 1/(1/S2+1/Hs+1/Ts)=15.652173913m`
- `exp2H = exp(-2*z/Hs)` scale Hs/2=15m
- `exp2T = exp(-2*z/Ts)` scale Ts/2=60m
- `Smix_2H_T = 1/(2/Hs+1/Ts)=13.3333333333m` for s²t
- `Smix_H_2T = 1/(1/Hs+2/Ts)=20m` for s*t²
- **NEW scales**
- `SmixS1_S2 = S1*S2/(S1+S2)=36.7346938775m` for pyc1*pyc2
- `SmixS1_S2_Hs = 1/(1/S1+1/S2+1/Hs)=16.5137614679m` for pyc1*pyc2*s
- `SmixQuad = 1/(2/Hs+2/Ts)=12.0m` for s²t² quadruple (Hs/2 Ts/2 product)
- `Smix24_Intr = 1/(1/Smix24+1/Ti)=11.4782608696m` where Ti=ThermohalineIntrusionScale 22m, for s*t*I term
- `SmixS1_Hs_Ts_Intr = 1/(1/S1+1/Hs+1/Ts+1/Ti)=10.8695652174m` for pyc1*Hs*Ts*Ti? Used for z*s*t*I product 3 scales+intrusion
- `SmixS2_Hs_Ts_Intr = 1/(1/S2+1/Hs+1/Ts+1/Ti)=9.137...m` compute as ~9.13

Go must use `math.Exp(-depth/Scale)` and mixed scales as defined. Any deviation fails pressure Simpson.

**Density – ULTRA-HARD 26 terms:**

```
rho(z) = rho0 + DepthDensityGradient*z + pyc1+pyc2+pyc3 + beta*sAnom + gamma0*tAnom*(1+Gamma*z)
       + Cc*sAnom*tAnom + Cc*pyc3*sAnom + Cc*pyc1*sAnom + Cc*pyc2*tAnom
       + TAnomQuad*tAnom² + SAnomQuad*sAnom²
       + SecondOrder*sAnom²*tAnom + SecondOrder*sAnom*tAnom²
       + Triple*sAnom*tAnom*pyc1 + Triple*sAnom*tAnom*pyc2
       + Thermosteric*0.01*tAnom*z + Halosteric*0.01*sAnom*z + Vorticity*z*(1-expDm)
       // NEW 6 terms
       + QuadrupleCabbelingCoeff*sAnom²*tAnom²
       + CompensatedLayerCoeff*pyc1*pyc2*sAnom
       + BaroclinicShearCoeff*z*sAnom*tAnom*(1-expIntr)
       + ThermostericSecondOrderCoeff*0.001*tAnom*z²
       + HalostericSecondOrderCoeff*0.001*sAnom*z²
       + VorticityMixingCoeff*0.01*z²*(1-expDm)
```

Where rho0=fluid.Density, sAnom=Hd*(1-expH), tAnom=12*(1-expT), expIntr=exp(-z/Ti). Properties: rho(0)=rho0, monotonic increasing (derivative >0), at 60m differs from model without cab/quad/cubic/triple/quadruple/baroclinic/second-order by >=1.5.

**Cabbeling parameter – ultra-hard includes quadruple & compensated:**

```
cab = Cc*s*t + Cc*pyc3*s + Cc*pyc1*s + Cc*pyc2*t + Tquad*t² + Squad*s²
    + SecondOrder*s²*t + SecondOrder*s*t² + Triple*s*t*pyc1 + Triple*s*t*pyc2
    + Quadruple*s²*t² + Compensated*pyc1*pyc2*s
```

Zero at surface.

**Spiciness:** `spice(z)=beta*(S-35)+gamma0*(T-15)`, zero at surface.

**Spiciness curvature:** second derivative of spice, `d²spice/dz²`, for mixing layer detection. `dS/dz=Hd/Hs*expH`, `d²S=-Hd/Hs²*expH`, `dT/dz=-12/Ts*expT`, `d²T=12/Ts²*expT`, so curvature = beta*d²S + gamma0*d²T.

**Spiciness torsion – NEW:** third derivative `d³spice/dz³ = beta*d³S + gamma0*d³T` where `d³S=Hd/Hs³*expH`, `d³T=-12/Ts³*expT`.

**Potential density:** `rho_pot=rho - DepthDensityGradient*z`, surface rho0.

**Potential temperature – 4th order + z² adiabatic lapse:**

```
x = P(z)/BulkModulus*1e-3
theta(z)=T(z)*(1 - x - ThermobaricCoeff*x² -0.2*x³ -0.05*x⁴) * (1 - AdiabaticLapseRate*z*0.001 - AdiabaticLapseRate*AdiabaticLapseRate*z²*1e-7)
```

Surface theta(0)=T(0)=15. Monotonic decreasing, <=T.

**Sound speed – ultra-hard with depth-cubed + T³ + S³ + P²*T + z*P:**

```
c(z)=1449.2+4.6*T -0.055*T² +1.34*(S-35)+0.016*z+SoundSpeedPressureQuadCoeff*z²+SoundSpeedDepthCubeCoeff*z³ +0.01*T*(S-35)
    + SoundSpeedThermoQuadCoeff*T²*(S-35) + SoundSpeedSalinityQuadCoeff*T*(S-35)²
    + BaroclinicShearCoeff*100*T³ + CompensatedLayerCoeff*10*(S-35)³
    + PressureNonLinearCoeff*1e2 * (P/BulkModulus*1e3) * T
    + PressureCubicNonLinearCoeff*1e9 * (P/BulkModulus*1e3)² * T
    + ThermohalineIntrusionScale*1e-5 * z*(P/BulkModulus*1e3)
```

Minimum: c0>c200 and c1500>c200, plus exact formula verification using T,S,P at 200m etc. Missing any cubic/baroclinic/compensated/depth-cube/P²/P*z term fails by >=0.01 test.

**Sound speed gradient – ultra-hard (10+ terms):**

```
dc/dz = 4.6*dT -0.11*T*dT +1.34*dS +0.016 +2*SSPressureQuad*z +3*SSDepthCube*z²
      +0.01*dT*(S-35)+0.01*T*dS
      + SoundSpeedThermoQuad*(2*T*dT*(S-35)+T²*dS)
      + SoundSpeedSalinityQuad*(dT*(S-35)² + T*2*(S-35)*dS)
      + Baroclinic*100*3*T²*dT
      + Compensated*10*3*(S-35)²*dS
      + PressureNonLinear*1e2 * [ (dP/dz/Bulk*1e3)*T + (P/Bulk*1e3)*dT ]
      + PressureCubic*1e9 * [ 2*(P/Bulk*1e3)*(dP/dz/Bulk*1e3)*T + (P/Bulk*1e3)²*dT ]
      + ThermohalineIntrusion*1e-5 * [ (P/Bulk*1e3) + z*(dP/dz/Bulk*1e3) ]
```

Where dP/dz = rho*g, rho from DensityAtDepth. Matches central diff h=0.05 within 2e-4.

**Sound speed curvature – NEW:** second derivative `d²c/dz²`, matches central diff of c via h=0.05 within 5e-4. Implement as central diff of gradient: (grad(z+h)-grad(z-h))/(2h) with h=0.001 or analytic second derivative.

**Finders – 3000 points + Brent 200 iter**

All finders via scanning **3000 points** equally spaced [0,maxDepth] then **Brent's method** (ternary+inverse quadratic) until width<tolerance.

- `FindSOFARAxis`: depth of minimum c.
- `FindPycnoclineMaxGradient`: depth where density gradient maximal.
- `FindSpicinessMaximum`: depth where spiciness maximal.
- `FindDoubleDiffusiveLayer(maxDepth,tol)`: depth where Turner angle crosses 45° or -45, root of |Tu|-45, scanning for sign change then Brent. Brute 0.5m within 1m.
- `FindThermoclineDepth`: depth where |dT/dz| maximal? Since dT/dz magnitude decreases exponentially, max at surface 0, but scanning still works – should return near 0. Brute 0.2m within 1.5m.
- `FindHaloclineDepth`: depth where dS/dz maximal (also at surface). Brute within 1.5m.
- `FindCompensatedLayer`: depth where density compensation minimal, i.e., |beta*dS/dz + gamma0*dT/dz| minimal (or |beta*gradS + gamma*gradT|). Since beta*dS positive, gamma0*dT negative (dT negative), they partially cancel. Find root of beta*dS+gamma*dT near where derivative crosses zero if gamma0*|dT| ~ beta*dS. Scan for minimum absolute value, then Brent. Brute 0.2m within 2m.

Validation maxDepth>0, tol>0 else error contains "maxDepth"/"tolerance".

**Buoyancy frequency – with acoustic correction:**

```
N² = g/rho * (drho/dz - rho*g/c²)
```

Positive, g/rho*grad at surface approximately, but includes rho*g/c². Verified vs formula exact.

**Buoyancy frequency gradient – NEW:** `dN²/dz`, matches central diff h=0.05 of N² within 1e-7? Implement as (N²(z+h)-N²(z-h))/(2h) with h=0.001 internally, but test via central diff h=0.05 tol 1e-6.

**Potential vorticity:** `PV = f * N² / g` where f=1e-4 Coriolis.

**Turner angle:** `Tu=atan2(gamma*dT/dz+beta*dS/dz, beta*dS/dz - gamma*dT/dz)*180/pi`, range -90..90.

**Double-diffusive regime:** Tu>45 contains "salt" and "finger", <-45 contains "diffus", else if |Tu|<10 and |spice curvature|>VorticityMixingCoeff contains "intrusion" or "thermohaline", else contains "stable".

**Pressure – 26-term ULTRA-HARD closed-form:**

`P(z)=g*Integral(z)`, P(0)=0, monotonic inc, matches Simpson 500k (or 1M) rel 1e-6 (was 5e-6). Missing any mixed, double-freq, z*exp, z²*exp, triple, quadruple, baroclinic, vort-second-order fails by >30.

Helper integrals required:

- `integralOneMinusExp(S,z)= z + S*exp(-z/S) - S`
- `integralExp(S,z)= S*(1-exp(-z/S))`
- `integralProductOneMinusExp(scales,z)`: generic product ∫0^z prod_i (1-exp(-u/Scale_i)) du = sum_{mask} (-1)^{bits} * scale_{mask}*(1-exp(-z/scale_{mask})) where scale_{mask}=1/(sum_{i in mask} 1/Scale_i), with mask=0 term = z. This is inclusion-exclusion over 2^k masks (up to k=4 -> 16 masks). Must implement.
- `integralZExp(S,z)=∫0^z u*exp(-u/S) du = S²*(1 - exp(-z/S)*(1+z/S))` plus variant `∫0^z u*(1-exp(-u/S)) du = 0.5*z² + S*z*exp + S²*exp - S²`
- `integralZ2Exp(S,z)=∫0^z u²*exp(-u/S) du = 2S³ - exp(-z/S)*(S*z²+2S²*z+2S³)`, so `∫0^z u²*(1-exp) du = z³/3 - integralZ2Exp`
- `integralZProductOneMinusExp(scales,z)`: ∫0^z u*prod_i(1-exp(-u/Scale_i)) du – expand similarly: sum masks (-1)^{bits} * integralZExpCombination? Actually ∫0^z u*exp(-u/Scale_comb) du = S²*(1 - exp(-z/S)*(1+z/S)). For mixed product with z factor, need inclusion-exclusion: ∫0^z u*prod(1-exp) = sum_{mask} (-1)^bits * I_ZExp(comb) where I_ZExp(comb) is integral of u*exp(-u/Scale_comb) with comb = combined scale of mask, and mask=0 term = 0.5*z².
- Similarly `integralZ2ProductOneMinusExp`: ∫0^z u²*prod(1-exp) du = sum (-1)^bits * integralZ2Exp(comb) with mask0 = z³/3.

Provide explicit table:

| Term | Meaning | Integral Formula | Scale(s) |
|------|---------|------------------|----------|
| Surface ref | rho0 | rho0*z | – |
| Linear | 0.5*grad*z² | 0.5*DepthDensityGradient*z² | – |
| Shallow pycno | Pycno*(z+S*exp-S) | PycnoclineDelta*(z+S1*expS1 -S1) | 200 |
| Deep pycno | | Deep*(z+S2*expS2 -S2) | 45 |
| Mid pycno | | Mid*(z+S3*expS3 -S3) | 90 |
| Halocline beta | | beta*Hd*(z+Hs*expH-Hs) | 30 |
| Thermocline gamma | | gamma0*12*(z+Ts*expT-Ts) | 120 |
| Depth gamma | z*tAnom | gamma0*Gamma*12*(0.5*z²+Ts*z*expT+Ts²*expT -Ts²) | z*exp 120 |
| Cab s*t | | Cc*Hd*12*(z+Hs*(expH-1)+Ts*(expT-1)+Smix24*(1-expMix24)) | 24 |
| Cab pyc3*s | | Cc*Mid*Hd*(z+Mid*(expMid-1)+Hs*(expH-1)+Smix22_5*(1-expMix22_5)) | 22.5 |
| Cab pyc1*s | | Cc*Pycno*Hd*(z+S1*(expS1-1)+Hs*(expH-1)+SmixS1_Hs*(1-expMixS1_Hs)) | 26.08 |
| Cab pyc2*t | | Cc*Deep*12*(z+S2*(expS2-1)+Ts*(expT-1)+SmixS2_Ts*(1-expMixS2_Ts)) | 32.72 |
| Quad t² | | Tquad*144*(z+2*Ts*expT-2*Ts+Ts/2*(1-exp2T)) | 60 |
| Quad s² | | Squad*Hd²*(z+2*Hs*expH-2*Hs+Hs/2*(1-exp2H)) | 15 |
| Halosteric z*s | | Halosteric*0.01*Hd*(0.5*z²+Hs*z*expH+Hs²*expH-Hs²) | z*exp 30 |
| Thermosteric z*t | | Thermo*0.01*12*(0.5*z²+Ts*z*expT+Ts²*expT-Ts²) | z*exp 120 |
| Vorticity z*(1-expDm) | | Vm*(0.5*z²+Dm*z*expDm+Dm²*expDm -Dm²) | 18 |
| s²t cubic | | SecondOrder*Hd²*12* integralProduct([Hs,Hs,Ts]) | 15,24,13.33 |
| s*t² cubic | | SecondOrder*Hd*144* integralProduct([Hs,Ts,Ts]) | 24,60,20 |
| triple pyc1*s*t | | Triple*300* integralProduct([S1,Hs,Ts]) | 26.08,75,24,21.42 |
| triple pyc2*s*t | | Triple*135* integralProduct([S2,Hs,Ts]) | 18,32.72,24,15.65 |
| **NEW** s²t² quadruple | | Quadruple*Hd²*144* integralProduct([Hs,Hs,Ts,Ts]) quad: scales Hs,Hs,Ts,Ts combined 12m etc => uses integralProduct 4 scales | 12m |
| **NEW** pyc1*pyc2*s compensated | | Compensated*Pyc1*Pyc2*Hd? Actually need amplitude: Compensated*Pyc1Delta*Pyc2Delta*Hd? Use 10*4.5*2.5=112.5 factor * integralProduct([S1,S2,Hs]) | 16.51 etc |
| **NEW** baroclinic z*s*t*(1-expI) | | Baroclinic* z*s*t*I => integralZProduct([Hs,Ts,Ti]) + combinations: integral of z*(1-expH)*(1-expT)*(1-expI) = 0.5z² - I_ZExp(Hs)-I_ZExp(Ts)-I_ZExp(Ti)+I_ZExp(Smix24)+I_ZExp(SmixHs_Ti)+I_ZExp(SmixTs_Ti)-I_ZExp(SmixHs_Ts_Ti) where I_ZExp(S)=S²(1-exp(-z/S)*(1+z/S))? Actually need ∫z*exp(-z/S) vs ∫z*(1-exp). Use helper integralZProduct. | Ti=22, 11.47 etc |
| **NEW** thermosteric z²*t | | ThermostericSecondOrder*0.001*12* integralZ2OneMinusExp: ∫z²*(1-expT) = z³/3 - integralZ2Exp(Ts) | z² 120 |
| **NEW** halosteric z²*s | | HalostericSecondOrder*0.001*Hd* ∫z²*(1-expH) = HalostericSecondOrder*0.001*Hd*(z³/3 - integralZ2Exp(Hs)) | z² 30 |
| **NEW** vorticity z²*(1-expDm) second order | | Vorticity*0.01*(z³/3 - integralZ2Exp(Dm)) | 18 |

Go must use math.Exp(-depth/Scale) and mixed scales as defined. Matches Simpson 500k rel 1e-6.

**Steric height – P²+P³ correction:**

`(P/g - rho0*z - PressureNonLinearCoeff*P²*1e-9 - PressureCubicNonLinearCoeff*P³*1e-13)/rho0` matches exact formula rel 1e-4.

**Hull volume – P³ non-linear + thermal-pressure cross:**

`V(z)=V0*exp(-k*P + PressureNonLinearCoeff*P*P*1e-12 + PressureCubicNonLinearCoeff*P*P*P*1e-18)*(1+alpha*(T-15)+alpha2*(T-15)² + CompensatedLayerCoeff*dT*P*1e-9)` clamped to MinimumVolumeFraction*V0, crush error "crush". FactorThermal clamped 0.1.

**Bulk modulus:** `K = -V / (dV/dP)` where `dV/dP = V*(-k +2*Pn*P*1e-12 +3*Pc*P²*1e-18) * factorThermal + V*exp*Comp*dT*1e-9` approx `V*exp*(-k+2*Pn*P*1e-12+3*Pc*P²*1e-18+Comp*dT*1e-9)` then `K=1/(k -2*Pn*P*1e-12 -3*Pc*P²*1e-18 - Comp*dT*1e-9)`. Must be positive.

## File Location
`/app/submarine.go`, package `submarine`, Go 1.23+, stdlib only. `go vet` passes. Expect ~1800-2200 lines due to 44 constants and 26-term pressure.

## Types
```go
type Submarine struct { DryMass float64; Volume float64; Length float64; BallastCapacity float64; BallastLevel float64; HullCompressibility float64; CrushDepth float64; DragCoefficient float64 }
type Seawater struct { Density float64 }
```

## Methods Required – ULTRA-HARD (35 methods)

Section A – Core Ocean (11 methods):
- `SalinityAtDepth(depth) (float64,error)`
- `SalinityGradientAtDepth(depth) (float64,error)`
- `TemperatureAtDepth(depth) (float64,error)`
- `TemperatureGradientAtDepth(depth) (float64,error)`
- `DensityAtDepth(depth) (float64,error)` – 26 terms with quadruple/second-order
- `DensityGradientAtDepth(depth) (float64,error)` matches central diff h=0.001 within 1e-8 (was 1e-6)
- `DensitySecondDerivativeAtDepth(depth) (float64,error)` matches diff h=0.001 within 1e-7
- `DensityThirdDerivativeAtDepth(depth) (float64,error)` matches diff h=0.001 within 1e-6
- `DensityFourthDerivativeAtDepth(depth) (float64,error)` matches diff h=0.001 within 1e-5
- `DensityFifthDerivativeAtDepth(depth) (float64,error)` **NEW** matches diff h=0.001 of fourth within 1e-4

Section B – Acoustic (10 methods):
- `SoundSpeedAtDepth(depth) (float64,error)` – depth-cube + T³+S³+P²*T+z*P
- `SoundSpeedGradientAtDepth(depth) (float64,error)` – 10 product + pressure P² chain + z*P terms, central diff h=0.05 tol 2e-4
- `SoundSpeedCurvatureAtDepth(depth) (float64,error)` **NEW** – second derivative d²c/dz², central diff h=0.05 tol 5e-4
- `FindSOFARAxis(maxDepth,tolerance float64) (float64,error)` – 3000 pts scan then Brent 200 iter
- `FindPycnoclineMaxGradient(maxDepth,tolerance float64) (float64,error)` – 3000 pts
- `FindSpicinessMaximum(maxDepth,tolerance float64) (float64,error)` – 3000 pts
- `FindDoubleDiffusiveLayer(maxDepth,tolerance float64) (float64,error)` – root |Tu|-45 via Brent
- `FindThermoclineDepth(maxDepth,tolerance float64) (float64,error)` **NEW** – depth max |dT/dz|, 3000 pts Brent
- `FindHaloclineDepth(maxDepth,tolerance float64) (float64,error)` **NEW** – depth max dS/dz, 3000 pts Brent
- `FindCompensatedLayer(maxDepth,tolerance float64) (float64,error)` **NEW** – depth min |beta*dS+gamma*dT|, 3000 pts Brent

Section C – Stability & Derived (14 methods):
- `PotentialDensityAtDepth(depth) (float64,error)`
- `PotentialTemperatureAtDepth(depth) (float64,error)` – 4th order x⁴ + z² adiabatic lapse
- `BuoyancyFrequencySquared(depth,g float64) (float64,error)` – g/rho*(drho/dz - rho*g/c²)
- `BuoyancyFrequencyGradientAtDepth(depth,g float64) (float64,error)` **NEW** – dN²/dz, central diff h=0.05 tol 1e-6
- `TurnerAngleAtDepth(depth) (float64,error)`
- `DoubleDiffusiveRegimeAtDepth(depth) (string,error)` – salt-finger >45, diffusive <-45, intrusion if |Tu|<10 and |spice curvature|>VorticityMixingCoeff, else stable
- `CabbelingParameterAtDepth(depth) (float64,error)` – includes quadruple + compensated
- `SpicinessAtDepth(depth) (float64,error)`
- `SpicinessCurvatureAtDepth(depth) (float64,error)` – second derivative
- `SpicinessTorsionAtDepth(depth) (float64,error)` **NEW** – third derivative
- `PotentialVorticityAtDepth(depth,g float64) (float64,error)` = 1e-4 * N² / g
- `BulkModulusAtDepth(depth,fluid Seawater,g float64) (float64,error)` = -V/(dV/dP) with P³
- plus Finders already in B

Section D – Hull & Buoyancy (4 methods):
- `PressureAtDepth(depth,g float64) (float64,error)` – 26-term analytic, Simpson 500k rel 1e-6, missing any mixed/double/z*exp/z²*exp/triple/quad/baroclinic/vort-second fails >30
- `StericHeightAtDepth(depth,g float64) (float64,error)` – includes P²+P³
- `VolumeAtDepth(depth,fluid Seawater,g float64) (float64,error)` – exp(-kP + Pn*P²*1e-12 + Pc*P³*1e-18)*(thermal quad + Comp*dT*P*1e-9) clamped
- `EffectiveDensityAtDepth(depth,fluid Seawater,g float64) (float64,error)`

Section E – Validation & Helpers (4 methods):
- `(Submarine) Validate() error` – same keywords
- `(Seawater) Validate() error` – Density>0
- `(Submarine) EffectiveMass() float64`
- `(Submarine) EffectiveDensity() (float64,error)`

Note: ~2000 lines estimate. All depth methods validate depth>=0 else error contains "depth". Use math.Exp, Abs, Atan2, Log for future Step2.

## Functions Required (Step 1)
```go
func BuoyantForce(fluid Seawater, sub Submarine, g float64) (float64,error)
func WeightForce(sub Submarine, g float64) (float64,error)
func RequiredBallastForNeutral(sub Submarine, fluid Seawater) (float64,error)
func CheckSubmarineState(sub Submarine, fluid Seawater) (string,error)
func IsNeutralBuoyancyPossible(sub Submarine, fluid Seawater) (bool,error)
func BuoyantForceAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func RequiredBallastForNeutralAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64,error)
func CheckSubmarineStateAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (string,error)
func IsNeutralBuoyancyPossibleAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (bool,error)
```

State via Tolerance: |eff-fluid|<=Tol neutral, eff<fluid float else sink.

## Requirements
- 44 constants exact, structs exact, signatures exact, 35 methods (including 5th derivative + 6 new)
- Stdlib only, go vet passes, 3000 pt scans for finders, Brent 200 iter, 5th derivative
- Pressure 26-term rel 1e-6, steric with P²+P³, volume with P³+cross, N² acoustic correction + gradient, sound cubic+z³+T³+S³+P²+zP, potential temp 4th order + z² lapse, curvature/torsion
- Expected lines 1800-2200, single file /app/submarine.go
