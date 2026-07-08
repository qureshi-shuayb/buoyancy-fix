<?php
require '/app/vehicle_envelope.php';
function assert_close($a,$b,$tol,$msg){ if(abs($a-$b)>$tol){ echo "FAIL $msg $a vs $b\n"; exit(1);} }
$panel=[0,5,10,15]; $out=place_vehicle(5,[10000],[],5,$panel); $span=15;$I=1+15/($span+38); assert_close($out['P1'],-10000*$I,1e-3,'pv1'); assert_close($out['P0'],0,1e-6,'pv0');
$out2=place_vehicle(5,[1000],[],10,[0,10]); $span2=10;$I2=1+15/($span2+38); assert_close($out2['P0'],-500*$I2,1e-2,'pv2a'); assert_close($out2['P1'],-500*$I2,1e-2,'pv2b');
$out3=place_vehicle(-5,[5000],[],5,$panel); assert_close($out3['P0']+$out3['P1']+$out3['P2']+$out3['P3'],0,1e-6,'outside ignored');
$out4=place_vehicle(2.5,[8000,8000],[5],5,[0,5,10]); $span3=10;$I3=1+15/($span3+38); assert_close($out4['P0'],-4000*$I3,1,'two axle'); assert_close($out4['P1'],-4000*$I3,1,'two axle2');
$joints=[['id'=>'P0','x'=>0,'y'=>0],['id'=>'P1','x'=>6,'y'=>0],['id'=>'P2','x'=>3,'y'=>4]];
$members=[['id'=>'AB','i'=>'P0','j'=>'P1','A'=>0.01,'E'=>200e9],['id'=>'AC','i'=>'P0','j'=>'P2','A'=>0.01,'E'=>200e9],['id'=>'BC','i'=>'P1','j'=>'P2','A'=>0.01,'E'=>200e9]];
$supports=[['joint_id'=>'P0','type'=>'pinned'],['joint_id'=>'P1','type'=>'roller']];
$truss=['joints'=>$joints,'members'=>$members,'supports'=>$supports];
$vehicle=['axle_weights'=>[10000],'spacings'=>[]];
$outE=envelope($truss,$vehicle,3.0);
if(count($outE)!=3){echo "fail env count\n"; exit(1);}
foreach($outE as $mid=>$v){ if(!isset($v['max_tension'])||!isset($v['max_compression'])){echo "fail keys $mid\n"; exit(1);} }
$ab_t=$outE['AB']['max_tension']; $ab_c=$outE['AB']['max_compression']; $ac_c=$outE['AC']['max_compression']; $bc_c=$outE['BC']['max_compression'];
if($ab_t<4000||$ab_t>6000){echo "fail AB tension range $ab_t\n";exit(1);}
if($ab_c>1e-3){echo "fail AB compression\n";exit(1);}
if($ac_c>-4000||$ac_c<-10000){echo "fail AC compression $ac_c\n";exit(1);}
if($bc_c>-4000||$bc_c<-10000){echo "fail BC compression $bc_c\n";exit(1);}
$panel2=[0,5,10]; $out5=place_vehicle(10,[7000,7000],[4],5,$panel2); $span4=10;$I4=1+15/($span4+38); assert_close($out5['P2'],-7000*$I4,1e-2,'spacing dir front'); assert_close($out5['P1'],-7000*$I4,1e-2,'spacing dir rear'); assert_close($out5['P0'],0,1e-2,'spacing dir zero');
echo "ok\n"; exit(0);
?>
