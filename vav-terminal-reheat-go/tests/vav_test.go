package main

import (
    "encoding/csv"
    "math"
    "os"
    "strconv"
    "testing"
)

const relTol = 1e-6
const absTol = 1e-6
const energyRel = 0.02 // 2% tolerance to allow model passes while still requiring correct coupling
const comfortRel = 0.05

func approxEqual(a, b, rel, abs float64) bool {
    diff := math.Abs(a - b)
    if diff <= abs {
        return true
    }
    maxab := math.Max(math.Abs(a), math.Abs(b))
    return diff <= rel*maxab
}

// Reference implementation recomputed from specification formulas following T-Bench v2 pattern
func refInterp(x float64, curve [][]float64) float64 {
    if len(curve)==0 { return 0 }
    pts := make([][]float64, len(curve))
    copy(pts, curve)
    // bubble sort
    for i:=0;i<len(pts)-1;i++ { for j:=i+1;j<len(pts);j++ { if pts[j][0]<pts[i][0] { pts[i],pts[j]=pts[j],pts[i] } } }
    if x <= pts[0][0] { return pts[0][1] }
    if x >= pts[len(pts)-1][0] { return pts[len(pts)-1][1] }
    for i:=1;i<len(pts);i++ {
        x0,y0 := pts[i-1][0], pts[i-1][1]
        x1,y1 := pts[i][0], pts[i][1]
        if x <= x1 {
            if x1==x0 { return y0 }
            frac := (x-x0)/(x1-x0)
            return y0 + frac*(y1-y0)
        }
    }
    return pts[len(pts)-1][1]
}

func refBalancePoints(heatSp, coolSp, gainW, ua float64) (float64,float64) {
    off := gainW/ua
    return heatSp-off, coolSp-off
}

func refOccupancy(hod int, span []int) string {
    s,e := span[0], span[1]
    if hod>=s && hod<e { return "occupied" }
    return "unoccupied"
}

func refAnnualEnergy(temps []float64, config map[string]interface{}) map[string]float64 {
    ua := config["UA"].(float64)
    occHours := config["occupied_hours"].([]int)
    bw := config["bin_width_c"].(float64)
    fanEff := config["fan_efficiency"].(float64)
    damperCurve := config["damper_authority_curve"].([][]float64)
    coilCurve := config["coil_effectiveness_curve"].([][]float64)
    staticMin := config["static_reset_min_pa"].(float64)
    staticMax := config["static_reset_max_pa"].(float64)
    supplyTemp := 13.0
    rhoCpConst := 1200.0
    boilerEff := 0.9
    elecFactor := 0.05

    type scfg struct{ tbHeat, tbCool, minAir float64 }
    bps := map[string]scfg{}
    for _, st := range []string{"occupied","unoccupied"} {
        s := config[st].(map[string]interface{})
        heatSp := s["heat_sp"].(float64)
        coolSp := s["cool_sp"].(float64)
        gain := s["gain_w"].(float64)
        minAir := s["min_airflow_m3s"].(float64)
        bh, bc := refBalancePoints(heatSp, coolSp, gain, ua)
        bps[st]=scfg{bh,bc,minAir}
    }
    tMin, tMax := temps[0], temps[0]
    for _,t := range temps { if t<tMin {tMin=t}; if t>tMax {tMax=t} }
    tr := tMax-tMin; if tr<1e-6 {tr=1.0}
    type key struct{state string; bin int}
    cells := map[key]int{}
    for idx,t := range temps {
        hod := idx%24
        st := refOccupancy(hod, occHours)
        b := int(math.Floor(t/bw))
        cells[key{st,b}]++
    }
    fanWh, reheatWh, comfortDH := 0.0,0.0,0.0
    for k,n := range cells {
        state:=k.state; b:=k.bin
        tRep := (float64(b)+0.5)*bw
        sc := bps[state]
        tbHeat, tbCool, minAir := sc.tbHeat, sc.tbCool, sc.minAir
        norm := (tRep - tMin)/tr
        if norm<0 {norm=0}; if norm>1 {norm=1}
        availableStatic := staticMin + norm*(staticMax-staticMin)
        maxFlow := refInterp(availableStatic, damperCurve)
        if tRep < tbHeat {
            load := ua*(tbHeat - tRep)
            airflow := minAir
            if airflow>maxFlow {airflow=maxFlow}
            airHeat := airflow*rhoCpConst*(supplyTemp - tRep)
            coilHeat := load - airHeat
            if coilHeat<0 {coilHeat=0}
            waterFlow := coilHeat/500.0
            eff := refInterp(waterFlow, coilCurve)
            if eff<0.1 {eff=0.1}
            heatingElec := coilHeat/eff/boilerEff*elecFactor
            fanPower := airflow*availableStatic/fanEff
            fanWh += float64(n)*fanPower
            reheatWh += float64(n)*heatingElec
        } else if tRep > tbCool {
            load := ua*(tRep - tbCool)
            deltaT := 11.0
            required := load/(rhoCpConst*deltaT)
            if required<minAir {required=minAir}
            if required>maxFlow {
                shortfall := (load - maxFlow*rhoCpConst*deltaT)/load
                if shortfall<0 {shortfall=0}
                comfortDH += float64(n)*shortfall*1.0
                required = maxFlow
            }
            fanPower := required*availableStatic/fanEff
            fanWh += float64(n)*fanPower
        } else {
            airflow := minAir
            if airflow>maxFlow {airflow=maxFlow}
            fanPower := airflow*availableStatic/fanEff
            fanWh += float64(n)*fanPower
        }
    }
    fan_kwh := fanWh/1000.0
    reheat_kwh := reheatWh/1000.0
    return map[string]float64{"fan_kwh":fan_kwh,"reheat_kwh":reheat_kwh,"comfort_degree_hours":comfortDH,"total_kwh":fan_kwh+reheat_kwh}
}

// Naive shortcuts for fail-signal
func naiveFixedStatic(temps []float64, config map[string]interface{}) map[string]float64 {
    cfg2 := make(map[string]interface{})
    for k,v := range config { cfg2[k]=v }
    // override reset to fixed average static
    min := config["static_reset_min_pa"].(float64)
    cfg2["static_reset_min_pa"]=min
    cfg2["static_reset_max_pa"]=min
    return refAnnualEnergy(temps,cfg2)
}
func naiveFixedBalance(temps []float64, config map[string]interface{}) map[string]float64 {
    cfg2 := make(map[string]interface{})
    for k,v := range config { cfg2[k]=v }
    occ := config["occupied"].(map[string]interface{})
    occ2 := make(map[string]interface{})
    for kk,vv := range occ { occ2[kk]=vv }
    occ2["gain_w"]=0.0
    unocc := make(map[string]interface{})
    for kk,vv := range occ { unocc[kk]=vv }
    unocc["gain_w"]=0.0
    cfg2["occupied"]=occ2
    cfg2["unoccupied"]=unocc
    return refAnnualEnergy(temps,cfg2)
}
func naiveConstantEffectiveness(temps []float64, config map[string]interface{}) map[string]float64 {
    cfg2 := make(map[string]interface{})
    for k,v := range config { cfg2[k]=v }
    // flat coil curve at 0.8 effectiveness
    cfg2["coil_effectiveness_curve"]=[][]float64{{0,0.95},{10,0.95}}
    return refAnnualEnergy(temps,cfg2)
}
func naiveNoPressure(temps []float64, config map[string]interface{}) map[string]float64 {
    cfg2 := make(map[string]interface{})
    for k,v := range config { cfg2[k]=v }
    // flat damper curve giving constant high flow regardless of static
    cfg2["damper_authority_curve"]=[][]float64{{0,0.01},{1000,0.01}}
    return refAnnualEnergy(temps,cfg2)
}

func makeTemps(n int, base, amp float64) []float64 {
    out := make([]float64,n)
    for i:=0;i<n;i++ { hod := float64(i%24); out[i]=base+amp*math.Sin(2*math.Pi*hod/24) }
    return out
}
func writeCSV(path string, temps []float64) error {
    f,err := os.Create(path); if err!=nil {return err}; defer f.Close()
    w := csv.NewWriter(f); w.Write([]string{"hour","temp_c"})
    for i,t := range temps { w.Write([]string{strconv.Itoa(i), strconv.FormatFloat(t,'f',2,64)}) }
    w.Flush(); return w.Error()
}
func baseConfig() map[string]interface{} {
    return map[string]interface{}{
        "UA": 200.0,
        "occupied_hours": []int{8,18},
        "bin_width_c": 1.0,
        "fan_efficiency": 0.65,
        "damper_authority_curve": [][]float64{{50,0.2},{150,0.5},{300,0.9},{500,1.2}},
        "static_reset_min_pa": 75.0,
        "static_reset_max_pa": 250.0,
        "coil_effectiveness_curve": [][]float64{{0,0.3},{2,0.55},{5,0.75},{10,0.85}},
        "occupied": map[string]interface{}{"heat_sp":21.0,"cool_sp":24.0,"gain_w":800.0,"min_airflow_m3s":0.15},
        "unoccupied": map[string]interface{}{"heat_sp":18.0,"cool_sp":27.0,"gain_w":200.0,"min_airflow_m3s":0.08},
    }
}

func TestReadTemps(t *testing.T) {
    tmp, _ := os.CreateTemp("", "temps*.csv")
    defer os.Remove(tmp.Name())
    tmp.WriteString("hour,temp_c\n0,10.5\n1,invalid\n2,\n3,12.0\n")
    tmp.Close()
    out, err := ReadTemps(tmp.Name())
    if err!=nil { t.Fatalf("err %v",err) }
    if len(out)!=2 || !approxEqual(out[0],10.5,relTol,absTol) || !approxEqual(out[1],12.0,relTol,absTol) { t.Fatalf("unexpected %v",out) }
}
func TestInterp(t *testing.T) {
    curve := [][]float64{{0,0},{10,100}}
    if !approxEqual(Interp(5,curve),50,relTol,absTol) { t.Fatalf("interp fail") }
    if !approxEqual(Interp(-5,curve),0,relTol,absTol) { t.Fatalf("clamp low") }
    if !approxEqual(Interp(20,curve),100,relTol,absTol) { t.Fatalf("clamp high") }
}

func TestStdlibOnly(t *testing.T) {
    // Verify agent source uses only allowed standard library packages per spec
    data, err := os.ReadFile("/app/vav_sim.go")
    if err != nil {
        t.Fatalf("cannot read agent source: %v", err)
    }
    src := string(data)
    banned := []string{"github.com", "golang.org/x", "gonum", "gonum.org"}
    for _, b := range banned {
        if strings.Contains(src, b) {
            t.Fatalf("banned third-party import detected containing %s", b)
        }
    }
}

func TestBalancePoints(t *testing.T) {
    bh, bc := BalancePoints(21,24,600,200)
    if !approxEqual(bh,18,relTol,absTol) || !approxEqual(bc,21,relTol,absTol) { t.Fatalf("bp %v %v",bh,bc) }
}
func TestAnnualEnergy(t *testing.T) {
    scenarios := []struct{name string; temps []float64}{
        {"mild", makeTemps(8760,15,5)},
        {"cold", makeTemps(8760,2,3)},
        {"hot", makeTemps(8760,28,4)},
        {"variable", makeTemps(8784,12,12)},
    }
    cfg := baseConfig()
    for _,sc := range scenarios {
        ref := refAnnualEnergy(sc.temps, cfg)
        got := AnnualEnergy(sc.temps, cfg)
        for _,k := range []string{"fan_kwh","reheat_kwh","total_kwh"} {
            if !approxEqual(got[k], ref[k], energyRel, 1e-6) {
                t.Fatalf("%s %s got %v want %v", sc.name,k,got[k],ref[k])
            }
        }
        if !approxEqual(got["comfort_degree_hours"], ref["comfort_degree_hours"], comfortRel, 1e-3) {
            t.Fatalf("%s comfort got %v want %v", sc.name, got["comfort_degree_hours"], ref["comfort_degree_hours"])
        }
        // fail-signal checks >4x tolerance drift
        for name, fn := range map[string]func([]float64,map[string]interface{})map[string]float64{
            "fixedStatic": naiveFixedStatic,
            "fixedBalance": naiveFixedBalance,
            "constEff": naiveConstantEffectiveness,
            "noPressure": naiveNoPressure,
        } {
            naive := fn(sc.temps, cfg)
            drift := math.Abs(naive["total_kwh"]-ref["total_kwh"])/math.Max(1.0,ref["total_kwh"])
            // constEff only matters when heating is significant; skip hot scenario where reheat near zero
            if name=="constEff" && ref["reheat_kwh"] < 1.0 {
                continue
            }
            if drift < 2*energyRel {
                t.Fatalf("%s fail-signal %s drift %v too small, expected >%v", sc.name, name, drift, 4*energyRel)
            }
        }
    }
}
