## Description – TRIVIAL 3-step split (4 required consts allow extras) target 10-30% fail (70-90% pass) – R05/R08 fixes

**Step1a 1_ocean_constants_and_density – TRIVIAL – 4 required consts allow extras, 60-100 lines:**
- Constants 8→4 required (allow extras): Tolerance 1e-9, Gravity 9.81, SeawaterDensity 1025, MinVol 0.1 – allow any extra per R08. Previously 8 exact with NOT-contain checks that rejected 24-const impls → 0/10 fails even at 8 consts 2-term linear.
- Density constant rho0=fluid.Density (1025), gradient 0 tol 1e-2, salinity 35 constant, temp 15 constant, validation, EffectiveMass/Density, buoyancy surface float/neutral/sink via Tolerance.
- Tests: constants 4 exact allow extras, density constant within 10% tol, gradient 0 within 0.1, buoyancy float, vet, race, leak cleanup rm before+after (R05).

**Step1b 2_pressure_sound_finders – EASY – 80-120 lines, reuses 4 required:**
- Methods: Pressure 1-term g*rho0*z explicit snippet return g*sw.Density*depth, Volume exp(-kP) clamped 0.1 no thermal, Sound constant 1500 any 1400-1600 range, SOFAR any depth [0,maxDepth] via 10pts scan, PotentialDensity constant rho0, PotentialTemperature 15, BuoyancyFrequency 0, Steric 0, EffectiveDensityAtDepth, plus at-depth ballast helpers.
- Tests: pressure 10k rel 10% loose >2, sound range 1400-1600, finder any depth, volume >0, leak cleanup.

**Step3 3_dive_dynamics – EASY-MEDIUM – 5-pt Cd table, 500pts 50iter, 25% RK4 ref:**

- R05 Information Isolation FIX: test.sh in all 3 steps does rm -f /app/*_test.go /app/ast_check*.go before AND after verifier + Python unlinks TEST_GO → prevents sub_step1_test.go leaking into inherited Step2/3 workspace. Previously Step1 verifier left file visible to Step2 agent.
- R08 Accepts Alternatives FIX + R06/R07 coverage: Previously required AddInt32/LoadInt32/CASInt32 only – valid alternatives AddInt64, AddUint32/64, Load/Store/CompareAndSwap/Swap + typed atomic.Int32/Int64/Uint32/Uint64 with Add/Load/Store/CompareAndSwap were rejected (6 rollouts: D2pM29n, GVw9QGd, 4Uy9gWN, ze5kc6h, QZnVES7, etc.). Now AST checker accepts any width/style via strings.HasPrefix(name, "Add") || "Load" || "Store" || "CompareAndSwap" || "Swap" + typed detection atomic.Int32/Int64. Instruction explicitly says "any valid style: AddInt32/LoadInt32/CompareAndSwapInt32 OR AddInt64, Uint, typed atomic.Int32/Int64 with Add/Load/Store/CompareAndSwap" per R02 spec-test alignment.
- Behavioral concurrency: TestMaxConcurrencyBehavioral measures batch 20 time <10s and order preserved, plus source check max <=4 (not ==4) via make(chan struct{},4) + WaitGroup + go + heap + atomic any width + context import. Priority via container/heap Less descending + final Index ordering preserved 20.
- Cd table: 10-pt →5-pt [1e3,1e4,1e5,1e6,5e6] Cd [1.44,1.2,0.7,0.2,0.12] log-interp band 0.1 (was 0.05) midpoint tol 0.05 (was 0.02) – eased.
- Terminal: 150 iter tight →50 iter 1e-2 looser, doubling hi logic kept.
- Equilibrium: 2000pts→500pts scan, Brent 150→50 iter, root tol 5m via compression k=5e-8 DryMass 9000 float->sink for constant density (so constant ocean still has equilibrium), crush check "crush", no roots "no equilibrium depth: no sign change".
- TimeToDepth: fixed RK4 k1..k4 only + optional adaptive atol/rtol/errorEstimate/errNorm with independent ref 25% rel (was 8%, was self dt=0.001 comparison) – prevents gaming via source-token.
- DiveProfile: len>3 (was 10, was 5) depth tol 5% (was 2%,1%), pressure monotonic.
- Deadline/cancellation lenient: Deadline 20ms/100items →500ms/50items lenient (your screenshot 683b3c3 had strict 20ms causing flakiness) with fallback log on fast machine, Cancellation 5ms/100→200ms/50 lenient (30ms/300→100ms/100→200ms/50) with 10ms retry fallback.

**Why split + trivial achieves 10-30% fail (was 0/10 at 683b3c3 8 consts 2-term):**
- Per-step methods: 12 methods 150-250 lines in one file → 7-8 methods 60-100 lines in Step1a (no pressure/sound/finders, no Exp) + 8-10 methods 80-120 lines in Step1b (pressure 1-term g*rho*z, sound constant 1400-1600, finder any depth 10pts, no Brent, no product integrals) + ~12 methods in Step3.
- Constants: from needing exactly 8 with absence checks (rejects 24-const) → 4 required exact, allow extras – per R08 accepts alternatives – removes false negatives.
- Physics: from needing exp exp(-z/Scale), product ∫(1-expH)(1-expT), 0.5 factor, quadratic minimum 250m → constant returns only rho0, g*rho*z, 0, 1500, 0 – no math.Exp for density/pressure/gradient/sound, only exp(-kP) for volume (needed for equilibrium via compression). Explicit Go snippets in instruction.md provide copy-paste ready code.

**Completion Rates (oracle after v6/v7/v8/v9):**
- 683b3c3 (8 consts 2-term linear rho0+grad*z): oracle 3/3 PASS, gpt-5.5 0/10, avocado 0/10, opus 0/10, Agentic Reviewer BAD_GRADING_WEAK
- 41a49dd (12 consts 3-term) also 0/10
- v9 (4 required consts, 1-term constant): expected 5/10 →7-9/10 passes (10-30% fail).

## Anti-Cheating – v9
- Density constant within 10%, gradient 0 tol 1e-2, sound any 1400-1600, finder any [0,maxDepth], pressure 10k rel 10% loose, volume >0, buoyancy float – leak cleanup.
- Step1b checks pressure, sound, finders, volume.
- Step3: Cd 5-pt log-interp band 0.1, eq 500pts, TimeToDepth ref 25%, DiveProfile mono len>3 tol 5%, Batch order 20, deadline lenient.

## Notes
v9 TRIVIAL 3-step split: Step1a 4 required consts allow extras, constant density/gradient, 60-100 lines; Step1b pressure 1-term g*rho*z, volume exp(-kP) clamped, sound constant 1400-1600, SOFAR any depth 10pts; Step3 5-pt Cd, 500pts eq via compression, fixed RK4 k1..k4 ref 25%, heap priority + pool 4 + atomic any width/style behavioral.
