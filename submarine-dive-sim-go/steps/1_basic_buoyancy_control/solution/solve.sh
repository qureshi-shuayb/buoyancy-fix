#!/bin/bash
set -euo pipefail
cat > /app/submarine.go <<'GO'
package submarine

import (
	"errors"
	"math"
)

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

type Submarine struct {
	DryMass float64
	Volume float64
	Length float64
	BallastCapacity float64
	BallastLevel float64
	HullCompressibility float64
	CrushDepth float64
	DragCoefficient float64
}
type Seawater struct { Density float64 }

func (s Submarine) Validate() error {
	if s.DryMass <=0 { return errors.New("dry mass must be positive") }
	if s.Volume<=0 { return errors.New("volume must be positive") }
	if s.Length<=0 { return errors.New("length must be positive") }
	if s.BallastCapacity<=0 { return errors.New("ballast capacity must be positive") }
	if s.BallastLevel<0 { return errors.New("ballast level must be non-negative") }
	if s.BallastLevel> s.BallastCapacity+1e-12 { return errors.New("ballast level exceeds capacity") }
	if s.HullCompressibility<0 { return errors.New("hull compressibility must be non-negative") }
	if s.CrushDepth<=0 { return errors.New("crush depth must be positive") }
	if s.DragCoefficient<0 { return errors.New("drag coefficient must be non-negative") }
	return nil
}
func (sw Seawater) Validate() error {
	if sw.Density<=0 { return errors.New("seawater density must be positive") }
	return nil
}
func (s Submarine) EffectiveMass() float64 { return s.DryMass+s.BallastLevel }
func (s Submarine) EffectiveDensity() (float64, error) {
	if err:=s.Validate(); err!=nil { return 0,err }
	if s.Volume<=0 { return 0,errors.New("volume must be positive") }
	return s.EffectiveMass()/s.Volume, nil
}
func (sw Seawater) SalinityAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	return 35.0+HaloclineDelta*(1.0-math.Exp(-depth/HaloclineScale)), nil
}
func (sw Seawater) SalinityGradientAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	return HaloclineDelta/HaloclineScale*math.Exp(-depth/HaloclineScale), nil
}
func (sw Seawater) TemperatureAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	return 15.0-12.0*(1.0-math.Exp(-depth/ThermoclineScale)), nil
}
func (sw Seawater) TemperatureGradientAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	return -12.0/ThermoclineScale*math.Exp(-depth/ThermoclineScale), nil
}
func (sw Seawater) CabbelingParameterAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	sAnom:=HaloclineDelta*(1.0-math.Exp(-depth/HaloclineScale))
	tAnom:=12.0*(1.0-math.Exp(-depth/ThermoclineScale))
	pyc3:=MidPycnoclineDelta*(1.0-math.Exp(-depth/MidPycnoclineScale))
	return CabbelingCoeff*sAnom*tAnom + CabbelingCoeff*pyc3*sAnom, nil
}
func (sw Seawater) SpicinessAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	s,_:=sw.SalinityAtDepth(depth)
	t,_:=sw.TemperatureAtDepth(depth)
	return SalinityDensityCoeff*(s-35.0)+ThermalCouplingCoeff*(t-15.0), nil
}
func (sw Seawater) DensityAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	sAnom:=HaloclineDelta*(1.0-math.Exp(-depth/HaloclineScale))
	tAnom:=12.0*(1.0-math.Exp(-depth/ThermoclineScale))
	pyc1:=PycnoclineDelta*(1.0-math.Exp(-depth/PycnoclineScale))
	pyc2:=DeepPycnoclineDelta*(1.0-math.Exp(-depth/DeepPycnoclineScale))
	pyc3:=MidPycnoclineDelta*(1.0-math.Exp(-depth/MidPycnoclineScale))
	cab1:=CabbelingCoeff*sAnom*tAnom
	cab2:=CabbelingCoeff*pyc3*sAnom
	gammaTerm:=ThermalCouplingCoeff*tAnom*(1.0+GammaDepthFactor*depth)
	return sw.Density+DepthDensityGradient*depth+pyc1+pyc2+pyc3+SalinityDensityCoeff*sAnom+gammaTerm+cab1+cab2, nil
}
func (sw Seawater) DensityGradientAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	exp1:=math.Exp(-depth/PycnoclineScale)
	exp2:=math.Exp(-depth/DeepPycnoclineScale)
	expMid:=math.Exp(-depth/MidPycnoclineScale)
	expH:=math.Exp(-depth/HaloclineScale)
	expT:=math.Exp(-depth/ThermoclineScale)
	sAnom:=HaloclineDelta*(1.0-expH)
	tAnom:=12.0*(1.0-expT)
	pyc3:=MidPycnoclineDelta*(1.0-expMid)
	dS:=HaloclineDelta/HaloclineScale*expH
	dtAnom:=12.0/ThermoclineScale*expT
	dp1:=PycnoclineDelta/PycnoclineScale*exp1
	dp2:=DeepPycnoclineDelta/DeepPycnoclineScale*exp2
	dp3:=MidPycnoclineDelta/MidPycnoclineScale*expMid
	df:=dtAnom*(1.0+GammaDepthFactor*depth)+tAnom*GammaDepthFactor
	termH:=SalinityDensityCoeff*dS
	termGamma:=ThermalCouplingCoeff*df
	termCab1:=CabbelingCoeff*(dS*tAnom+sAnom*dtAnom)
	termCab2:=CabbelingCoeff*(dp3*sAnom+pyc3*dS)
	return DepthDensityGradient+dp1+dp2+dp3+termH+termGamma+termCab1+termCab2, nil
}
func (sw Seawater) DensitySecondDerivativeAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	exp1:=math.Exp(-depth/PycnoclineScale)
	exp2:=math.Exp(-depth/DeepPycnoclineScale)
	expMid:=math.Exp(-depth/MidPycnoclineScale)
	expH:=math.Exp(-depth/HaloclineScale)
	expT:=math.Exp(-depth/ThermoclineScale)
	sAnom:=HaloclineDelta*(1.0-expH)
	tAnom:=12.0*(1.0-expT)
	pyc3:=MidPycnoclineDelta*(1.0-expMid)
	dS:=HaloclineDelta/HaloclineScale*expH
	dtAnom:=12.0/ThermoclineScale*expT
	d2S:=-HaloclineDelta/(HaloclineScale*HaloclineScale)*expH
	d2tAnom:=-12.0/(ThermoclineScale*ThermoclineScale)*expT
	d2p3:=-MidPycnoclineDelta/(MidPycnoclineScale*MidPycnoclineScale)*expMid
	d2p1:=-PycnoclineDelta/(PycnoclineScale*PycnoclineScale)*exp1
	d2p2:=-DeepPycnoclineDelta/(DeepPycnoclineScale*DeepPycnoclineScale)*exp2
	dp3:=MidPycnoclineDelta/MidPycnoclineScale*expMid
	d2f:=d2tAnom*(1.0+GammaDepthFactor*depth)+2.0*GammaDepthFactor*dtAnom
	_ = dp3
	tH:=SalinityDensityCoeff*d2S
	tGamma:=ThermalCouplingCoeff*d2f
	tCab1:=CabbelingCoeff*(d2S*tAnom+2.0*dS*dtAnom+sAnom*d2tAnom)
	tCab2:=CabbelingCoeff*(d2p3*sAnom+2.0*dp3*dS+pyc3*d2S)
	return d2p1+d2p2+d2p3+tH+tGamma+tCab1+tCab2, nil
}
func (sw Seawater) DensityThirdDerivativeAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	exp1:=math.Exp(-depth/PycnoclineScale)
	exp2:=math.Exp(-depth/DeepPycnoclineScale)
	expMid:=math.Exp(-depth/MidPycnoclineScale)
	expH:=math.Exp(-depth/HaloclineScale)
	expT:=math.Exp(-depth/ThermoclineScale)
	sAnom:=HaloclineDelta*(1.0-expH)
	tAnom:=12.0*(1.0-expT)
	pyc3:=MidPycnoclineDelta*(1.0-expMid)
	dS:=HaloclineDelta/HaloclineScale*expH
	dtAnom:=12.0/ThermoclineScale*expT
	d2S:=-HaloclineDelta/(HaloclineScale*HaloclineScale)*expH
	d2tAnom:=-12.0/(ThermoclineScale*ThermoclineScale)*expT
	d3S:=HaloclineDelta/(HaloclineScale*HaloclineScale*HaloclineScale)*expH
	d3tAnom:=12.0/(ThermoclineScale*ThermoclineScale*ThermoclineScale)*expT
	d2p3:=-MidPycnoclineDelta/(MidPycnoclineScale*MidPycnoclineScale)*expMid
	d3p3:=MidPycnoclineDelta/(MidPycnoclineScale*MidPycnoclineScale*MidPycnoclineScale)*expMid
	dp3:=MidPycnoclineDelta/MidPycnoclineScale*expMid
	d3p1:=PycnoclineDelta/(PycnoclineScale*PycnoclineScale*PycnoclineScale)*exp1
	d3p2:=DeepPycnoclineDelta/(DeepPycnoclineScale*DeepPycnoclineScale*DeepPycnoclineScale)*exp2
	d3f:=d3tAnom*(1.0+GammaDepthFactor*depth)+3.0*GammaDepthFactor*d2tAnom
	tH:=SalinityDensityCoeff*d3S
	tGamma:=ThermalCouplingCoeff*d3f
	tCab1:=CabbelingCoeff*(d3S*tAnom+3.0*d2S*dtAnom+3.0*dS*d2tAnom+sAnom*d3tAnom)
	tCab2:=CabbelingCoeff*(d3p3*sAnom+3.0*d2p3*dS+3.0*dp3*d2S+pyc3*d3S)
	return d3p1+d3p2+d3p3+tH+tGamma+tCab1+tCab2, nil
}
func (sw Seawater) SoundSpeedAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	T,_:=sw.TemperatureAtDepth(depth)
	S,_:=sw.SalinityAtDepth(depth)
	c:=1449.2+4.6*T-0.055*T*T+1.34*(S-35.0)+0.016*depth+SoundSpeedPressureQuadCoeff*depth*depth
	return c, nil
}
func (sw Seawater) SoundSpeedGradientAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	T,_:=sw.TemperatureAtDepth(depth)
	dT,_:=sw.TemperatureGradientAtDepth(depth)
	dS,_:=sw.SalinityGradientAtDepth(depth)
	return 4.6*dT -0.11*T*dT +1.34*dS +0.016 +2.0*SoundSpeedPressureQuadCoeff*depth, nil
}
func (sw Seawater) FindSOFARAxis(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth<=0 { return 0,errors.New("maxDepth must be positive") }
	if tolerance<=0 { return 0,errors.New("tolerance must be positive") }
	N:=1000
	dz:=maxDepth/float64(N)
	bestC:=1e99
	bestIdx:=0
	zs:=make([]float64,N+1)
	cs:=make([]float64,N+1)
	for i:=0;i<=N;i++{
		z:=float64(i)*dz
		c,_:=sw.SoundSpeedAtDepth(z)
		zs[i]=z
		cs[i]=c
		if c<bestC { bestC=c; bestIdx=i }
	}
	lo:=0.0
	if bestIdx>0 { lo=zs[bestIdx-1] } else { lo=0 }
	hi:=maxDepth
	if bestIdx<N { hi=zs[bestIdx+1] } else { hi=maxDepth }
	for iter:=0; iter<100; iter++{
		if hi-lo < tolerance { break }
		m1:=lo+(hi-lo)/3.0
		m2:=hi-(hi-lo)/3.0
		c1,_:=sw.SoundSpeedAtDepth(m1)
		c2,_:=sw.SoundSpeedAtDepth(m2)
		if c1<c2 { hi=m2 } else { lo=m1 }
	}
	return (lo+hi)/2.0, nil
}
func (sw Seawater) FindPycnoclineMaxGradient(maxDepth float64, tolerance float64) (float64, error) {
	if maxDepth<=0 { return 0,errors.New("maxDepth must be positive") }
	if tolerance<=0 { return 0,errors.New("tolerance must be positive") }
	N:=1000
	dz:=maxDepth/float64(N)
	bestG:=-1e99
	bestIdx:=0
	zs:=make([]float64,N+1)
	for i:=0;i<=N;i++{
		z:=float64(i)*dz
		g,_:=sw.DensityGradientAtDepth(z)
		zs[i]=z
		if g>bestG { bestG=g; bestIdx=i }
	}
	lo:=0.0
	if bestIdx>0 { lo=zs[bestIdx-1] } else { lo=0 }
	hi:=maxDepth
	if bestIdx<N { hi=zs[bestIdx+1] } else { hi=maxDepth }
	for iter:=0; iter<100; iter++{
		if hi-lo < tolerance { break }
		m1:=lo+(hi-lo)/3.0
		m2:=hi-(hi-lo)/3.0
		g1,_:=sw.DensityGradientAtDepth(m1)
		g2,_:=sw.DensityGradientAtDepth(m2)
		if g1>g2 { hi=m2 } else { lo=m1 }
	}
	return (lo+hi)/2.0, nil
}
func (sw Seawater) PotentialDensityAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	rho,_:=sw.DensityAtDepth(depth)
	return rho - DepthDensityGradient*depth, nil
}
func (sw Seawater) PotentialTemperatureAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	T,_:=sw.TemperatureAtDepth(depth)
	P,err:=sw.PressureAtDepth(depth, StandardGravity)
	if err!=nil { return 0,err }
	x:=P/BulkModulus*1e-3
	theta:=T*(1.0 - x - ThermobaricCoeff*x*x)
	return theta, nil
}
func (sw Seawater) BuoyancyFrequencySquared(depth float64, g float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	if g<=0 { return 0,errors.New("gravity must be positive") }
	rho,err:=sw.DensityAtDepth(depth)
	if err!=nil { return 0,err }
	grad,err:=sw.DensityGradientAtDepth(depth)
	if err!=nil { return 0,err }
	return g/rho*grad, nil
}
func (sw Seawater) TurnerAngleAtDepth(depth float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	dT,_:=sw.TemperatureGradientAtDepth(depth)
	dS,_:=sw.SalinityGradientAtDepth(depth)
	num:=ThermalCouplingCoeff*dT+SalinityDensityCoeff*dS
	den:=SalinityDensityCoeff*dS-ThermalCouplingCoeff*dT
	return math.Atan2(num,den)*180.0/math.Pi, nil
}
func (sw Seawater) DoubleDiffusiveRegimeAtDepth(depth float64) (string, error) {
	if depth<0 { return "",errors.New("depth must be non-negative") }
	ta,err:=sw.TurnerAngleAtDepth(depth)
	if err!=nil { return "",err }
	if ta>45.0 { return "salt-fingering", nil }
	if ta < -45.0 { return "diffusive-convection", nil }
	return "doubly-stable", nil
}
func (sw Seawater) PressureAtDepth(depth float64, g float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	if g<=0 { return 0,errors.New("gravity must be positive") }
	exp1:=math.Exp(-depth/PycnoclineScale)
	exp2:=math.Exp(-depth/DeepPycnoclineScale)
	expMid:=math.Exp(-depth/MidPycnoclineScale)
	expH:=math.Exp(-depth/HaloclineScale)
	expT:=math.Exp(-depth/ThermoclineScale)
	inv24:=1.0/HaloclineScale+1.0/ThermoclineScale
	sMix24:=1.0/inv24
	expMix24:=math.Exp(-depth*inv24)
	inv22:=1.0/MidPycnoclineScale+1.0/HaloclineScale
	sMix22:=1.0/inv22
	expMix22:=math.Exp(-depth*inv22)
	integral:=sw.Density*depth+0.5*DepthDensityGradient*depth*depth+
		PycnoclineDelta*(depth+PycnoclineScale*exp1-PycnoclineScale)+
		DeepPycnoclineDelta*(depth+DeepPycnoclineScale*exp2-DeepPycnoclineScale)+
		MidPycnoclineDelta*(depth+MidPycnoclineScale*expMid-MidPycnoclineScale)+
		SalinityDensityCoeff*HaloclineDelta*(depth+HaloclineScale*expH-HaloclineScale)+
		ThermalCouplingCoeff*12.0*(depth+ThermoclineScale*expT-ThermoclineScale)+
		ThermalCouplingCoeff*GammaDepthFactor*12.0*(0.5*depth*depth+ThermoclineScale*depth*expT+ThermoclineScale*ThermoclineScale*expT-ThermoclineScale*ThermoclineScale)+
		CabbelingCoeff*HaloclineDelta*12.0*(depth+HaloclineScale*(expH-1.0)+ThermoclineScale*(expT-1.0)+sMix24*(1.0-expMix24))+
		CabbelingCoeff*MidPycnoclineDelta*HaloclineDelta*(depth+MidPycnoclineScale*(expMid-1.0)+HaloclineScale*(expH-1.0)+sMix22*(1.0-expMix22))
	return g*integral, nil
}
func (sw Seawater) StericHeightAtDepth(depth float64, g float64) (float64, error) {
	if err:=sw.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	if g<=0 { return 0,errors.New("gravity must be positive") }
	P,err:=sw.PressureAtDepth(depth,g)
	if err!=nil { return 0,err }
	return (P/g - sw.Density*depth)/sw.Density, nil
}
func (s Submarine) VolumeAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
	if err:=s.Validate(); err!=nil { return 0,err }
	if err:=fluid.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	if g<=0 { return 0,errors.New("gravity must be positive") }
	if depth> s.CrushDepth { return 0,errors.New("crush depth exceeded") }
	pressure,err:=fluid.PressureAtDepth(depth,g)
	if err!=nil { return 0,err }
	temp,err:=fluid.TemperatureAtDepth(depth)
	if err!=nil { return 0,err }
	factorExp:=1.0
	if s.HullCompressibility!=0 { factorExp=math.Exp(-s.HullCompressibility*pressure) }
	dT:=temp-15.0
	factorThermal:=1.0+HullThermalExpansionCoeff*dT+HullThermalExpansionQuadCoeff*dT*dT
	if factorThermal<0.1 { factorThermal=0.1 }
	vol:=s.Volume*factorExp*factorThermal
	minVol:=s.Volume*MinimumVolumeFraction
	if vol<minVol { vol=minVol }
	if vol<=0 { vol=minVol }
	_ = math.Abs(vol)
	return vol, nil
}
func (s Submarine) EffectiveDensityAtDepth(depth float64, fluid Seawater, g float64) (float64, error) {
	if err:=s.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	vol,err:=s.VolumeAtDepth(depth,fluid,g)
	if err!=nil { return 0,err }
	if vol<=0 { return 0,errors.New("volume must be positive") }
	return s.EffectiveMass()/vol, nil
}
func BuoyantForce(fluid Seawater, sub Submarine, g float64) (float64, error) {
	if err:=fluid.Validate(); err!=nil { return 0,err }
	if err:=sub.Validate(); err!=nil { return 0,err }
	if g<=0 { return 0,errors.New("gravity must be positive") }
	return fluid.Density*sub.Volume*g, nil
}
func WeightForce(sub Submarine, g float64) (float64, error) {
	if err:=sub.Validate(); err!=nil { return 0,err }
	if g<=0 { return 0,errors.New("gravity must be positive") }
	return sub.EffectiveMass()*g, nil
}
func BuoyantForceAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error) {
	if err:=sub.Validate(); err!=nil { return 0,err }
	if err:=fluid.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	if g<=0 { return 0,errors.New("gravity must be positive") }
	if depth>sub.CrushDepth { return 0,errors.New("crush depth exceeded") }
	rho,err:=fluid.DensityAtDepth(depth)
	if err!=nil { return 0,err }
	vol,err:=sub.VolumeAtDepth(depth,fluid,g)
	if err!=nil { return 0,err }
	return rho*vol*g, nil
}
func RequiredBallastForNeutral(sub Submarine, fluid Seawater) (float64, error) {
	if sub.DryMass<=0 { return 0,errors.New("dry mass must be positive") }
	if sub.Volume<=0 { return 0,errors.New("volume must be positive") }
	if sub.Length<=0 { return 0,errors.New("length must be positive") }
	if sub.BallastCapacity<=0 { return 0,errors.New("ballast capacity must be positive") }
	if sub.HullCompressibility<0 { return 0,errors.New("hull compressibility must be non-negative") }
	if sub.CrushDepth<=0 { return 0,errors.New("crush depth must be positive") }
	if sub.DragCoefficient<0 { return 0,errors.New("drag coefficient must be non-negative") }
	if err:=fluid.Validate(); err!=nil { return 0,err }
	return fluid.Density*sub.Volume - sub.DryMass, nil
}
func RequiredBallastForNeutralAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (float64, error) {
	if sub.DryMass<=0 { return 0,errors.New("dry mass must be positive") }
	if sub.Volume<=0 { return 0,errors.New("volume must be positive") }
	if sub.Length<=0 { return 0,errors.New("length must be positive") }
	if sub.BallastCapacity<=0 { return 0,errors.New("ballast capacity must be positive") }
	if sub.HullCompressibility<0 { return 0,errors.New("hull compressibility must be non-negative") }
	if sub.CrushDepth<=0 { return 0,errors.New("crush depth must be positive") }
	if sub.DragCoefficient<0 { return 0,errors.New("drag coefficient must be non-negative") }
	if err:=fluid.Validate(); err!=nil { return 0,err }
	if depth<0 { return 0,errors.New("depth must be non-negative") }
	if g<=0 { return 0,errors.New("gravity must be positive") }
	if depth>sub.CrushDepth { return 0,errors.New("crush depth exceeded") }
	rho,err:=fluid.DensityAtDepth(depth)
	if err!=nil { return 0,err }
	vol,err:=sub.VolumeAtDepth(depth,fluid,g)
	if err!=nil { return 0,err }
	return rho*vol - sub.DryMass, nil
}
func CheckSubmarineState(sub Submarine, fluid Seawater) (string, error) {
	if err:=sub.Validate(); err!=nil { return "",err }
	if err:=fluid.Validate(); err!=nil { return "",err }
	eff,err:=sub.EffectiveDensity()
	if err!=nil { return "",err }
	diff:=eff-fluid.Density
	if math.Abs(diff)<=Tolerance { return "neutral", nil }
	if diff<0 { return "float", nil }
	return "sink", nil
}
func CheckSubmarineStateAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (string, error) {
	if err:=sub.Validate(); err!=nil { return "",err }
	if err:=fluid.Validate(); err!=nil { return "",err }
	if depth<0 { return "",errors.New("depth must be non-negative") }
	if g<=0 { return "",errors.New("gravity must be positive") }
	if depth>sub.CrushDepth { return "",errors.New("crush depth exceeded") }
	eff,err:=sub.EffectiveDensityAtDepth(depth,fluid,g)
	if err!=nil { return "",err }
	rho,err:=fluid.DensityAtDepth(depth)
	if err!=nil { return "",err }
	diff:=eff-rho
	if math.Abs(diff)<=Tolerance { return "neutral", nil }
	if diff<0 { return "float", nil }
	return "sink", nil
}
func IsNeutralBuoyancyPossible(sub Submarine, fluid Seawater) (bool, error) {
	if sub.DryMass<=0 { return false,errors.New("dry mass must be positive") }
	if sub.Volume<=0 { return false,errors.New("volume must be positive") }
	if sub.Length<=0 { return false,errors.New("length must be positive") }
	if sub.BallastCapacity<=0 { return false,errors.New("ballast capacity must be positive") }
	if sub.HullCompressibility<0 { return false,errors.New("hull compressibility must be non-negative") }
	if sub.CrushDepth<=0 { return false,errors.New("crush depth must be positive") }
	if sub.DragCoefficient<0 { return false,errors.New("drag coefficient must be non-negative") }
	if err:=fluid.Validate(); err!=nil { return false,err }
	req,_:=RequiredBallastForNeutral(sub,fluid)
	return req>=0 && req<=sub.BallastCapacity, nil
}
func IsNeutralBuoyancyPossibleAtDepth(sub Submarine, fluid Seawater, depth float64, g float64) (bool, error) {
	if sub.DryMass<=0 { return false,errors.New("dry mass must be positive") }
	if sub.Volume<=0 { return false,errors.New("volume must be positive") }
	if sub.Length<=0 { return false,errors.New("length must be positive") }
	if sub.BallastCapacity<=0 { return false,errors.New("ballast capacity must be positive") }
	if sub.HullCompressibility<0 { return false,errors.New("hull compressibility must be non-negative") }
	if sub.CrushDepth<=0 { return false,errors.New("crush depth must be positive") }
	if sub.DragCoefficient<0 { return false,errors.New("drag coefficient must be non-negative") }
	if err:=fluid.Validate(); err!=nil { return false,err }
	if depth<0 { return false,errors.New("depth must be non-negative") }
	if g<=0 { return false,errors.New("gravity must be positive") }
	if depth>sub.CrushDepth { return false,errors.New("crush depth exceeded") }
	req,err:=RequiredBallastForNeutralAtDepth(sub,fluid,depth,g)
	if err!=nil { return false,err }
	return req>=0 && req<=sub.BallastCapacity, nil
}
GO
