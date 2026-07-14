<?php
require '/app/vehicle_envelope.php';
function assert_close($a,$b,$tol,$msg){ if(abs($a-$b)>$tol){ echo "FAIL $msg $a vs $b\n"; exit(1);} }
function assert_close_rel($a,$b,$rel,$abs,$msg){ $diff=abs($a-$b); $tol=max($abs, abs($b)*$rel); if($diff>$tol){ echo "FAIL $msg $a vs $b diff $diff tol $tol\n"; exit(1);} }
$panel=[0,5,10,15]; $out=place_vehicle(5,[10000],[],5,$panel); $span=15;$I=1+15/($span+38); assert_close($out['P1'],-10000*$I,1e-3,'pv1'); assert_close($out['P0'],0,1e-6,'pv0');
$out2=place_vehicle(5,[1000],[],10,[0,10]); $span2=10;$I2=1+15/($span2+38); assert_close($out2['P0'],-500*$I2,1e-3,'pv2a'); assert_close($out2['P1'],-500*$I2,1e-3,'pv2b');
$out3=place_vehicle(-5,[5000],[],5,$panel); assert_close($out3['P0']+ $out3['P1']+$out3['P2']+$out3['P3'],0,1e-6,'outside ignored');
$out4=place_vehicle(2.5,[8000,8000],[5],5,[0,5,10]); // two axles at 2.5 and -2.5 => only front axle inside between 0 and 5 => split 4000 each *I, rear ignored outside range
$span3=10;$I3=1+15/($span3+38); assert_close($out4['P0'],-4000*$I3,1e-3,'two axle'); assert_close($out4['P1'],-4000*$I3,1e-3,'two axle2');
// spacing direction test: front at 10, rear at 5 with spacing 5, both on panel points, no interpolation ambiguity
$panel2=[0,5,10]; $out5=place_vehicle(10,[7000,7000],[5],5,$panel2); $span4=10;$I4=1+15/($span4+38); assert_close($out5['P2'],-7000*$I4,1e-2,'spacing dir front'); assert_close($out5['P1'],-7000*$I4,1e-2,'spacing dir rear'); assert_close($out5['P0'],0,1e-2,'spacing dir zero');
// envelope test 2-panel Pratt truss with interior deck panel ensuring non-zero forces
$joints=[['id'=>'P0','x'=>0,'y'=>0],['id'=>'P1','x'=>5,'y'=>0],['id'=>'P2','x'=>10,'y'=>0],['id'=>'P3','x'=>5,'y'=>5]];
$members=[['id'=>'B0','i'=>'P0','j'=>'P1','A'=>0.01,'E'=>200e9],['id'=>'B1','i'=>'P1','j'=>'P2','A'=>0.01,'E'=>200e9],['id'=>'V0','i'=>'P1','j'=>'P3','A'=>0.01,'E'=>200e9],['id'=>'D0','i'=>'P0','j'=>'P3','A'=>0.01,'E'=>200e9],['id'=>'D1','i'=>'P2','j'=>'P3','A'=>0.01,'E'=>200e9]];
$supports=[['joint_id'=>'P0','type'=>'pinned'],['joint_id'=>'P2','type'=>'roller']];
$truss=['joints'=>$joints,'members'=>$members,'supports'=>$supports];
$vehicle=['axle_weights'=>[10000],'spacings'=>[]];
$outE=envelope($truss,$vehicle,2.5); if(count($outE)!=5){echo "fail env count\n"; exit(1);} foreach($outE as $mid=>$v){ if(!isset($v['max_tension'])||!isset($v['max_compression'])){echo "fail keys $mid\n"; exit(1);} }
// reference values computed from reference solution within 1% relative tolerance as promised in spec
assert_close_rel($outE['B0']['max_tension'],6562.5,0.01,1e-3,'B0 tension');
assert_close_rel($outE['B0']['max_compression'],0.0,0.01,1e-3,'B0 compression');
assert_close_rel($outE['B1']['max_tension'],6562.5,0.01,1e-3,'B1 tension');
assert_close_rel($outE['B1']['max_compression'],0.0,0.01,1e-3,'B1 compression');
assert_close_rel($outE['V0']['max_tension'],13125.0,0.01,1e-3,'V0 tension');
assert_close_rel($outE['V0']['max_compression'],0.0,0.01,1e-3,'V0 compression');
assert_close_rel($outE['D0']['max_tension'],0.0,0.01,1e-3,'D0 tension');
assert_close_rel($outE['D0']['max_compression'],-9280.7765030734,0.01,1e-3,'D0 compression');
assert_close_rel($outE['D1']['max_tension'],0.0,0.01,1e-3,'D1 tension');
assert_close_rel($outE['D1']['max_compression'],-9280.7765030734,0.01,1e-3,'D1 compression');
// second fixture to prevent hardcode cheat — different topology 3-panel truss with 2 moving axles
$joints2b=[['id'=>'Q0','x'=>0,'y'=>0],['id'=>'Q1','x'=>4,'y'=>0],['id'=>'Q2','x'=>8,'y'=>0],['id'=>'Q3','x'=>12,'y'=>0],['id'=>'Q4','x'=>4,'y'=>3],['id'=>'Q5','x'=>8,'y'=>3]];
$members2b=[['id'=>'B0','i'=>'Q0','j'=>'Q1','A'=>0.01,'E'=>200e9],['id'=>'B1','i'=>'Q1','j'=>'Q2','A'=>0.01,'E'=>200e9],['id'=>'B2','i'=>'Q2','j'=>'Q3','A'=>0.01,'E'=>200e9],['id'=>'V1','i'=>'Q1','j'=>'Q4','A'=>0.01,'E'=>200e9],['id'=>'V2','i'=>'Q2','j'=>'Q5','A'=>0.01,'E'=>200e9],['id'=>'D0','i'=>'Q0','j'=>'Q4','A'=>0.01,'E'=>200e9],['id'=>'D1','i'=>'Q4','j'=>'Q5','A'=>0.01,'E'=>200e9],['id'=>'D2','i'=>'Q4','j'=>'Q2','A'=>0.01,'E'=>200e9],['id'=>'D3','i'=>'Q5','j'=>'Q3','A'=>0.01,'E'=>200e9]];
$supports2b=[['joint_id'=>'Q0','type'=>'pinned'],['joint_id'=>'Q3','type'=>'roller']];
$truss2b=['joints'=>$joints2b,'members'=>$members2b,'supports'=>$supports2b];
$vehicle2b=['axle_weights'=>[8000,8000],'spacings'=>[3.5]];
$outE2=envelope($truss2b,$vehicle2b,3.0); if(count($outE2)!=9){echo "fail env2 count\n"; exit(1);} foreach($outE2 as $mid=>$v){ if(!isset($v['max_tension'])||!isset($v['max_compression'])){echo "fail keys2 $mid\n"; exit(1);} }
// second fixture reference values from reference solution with 5% tolerance to prevent hardcode of single fixture
assert_close_rel($outE2['B0']['max_tension'],12711,0.05,50,'B0_2 tension');
assert_close_rel($outE2['B1']['max_tension'],12711,0.05,50,'B1_2 tension');
assert_close_rel($outE2['B2']['max_tension'],13289,0.05,50,'B2_2 tension');
assert_close_rel($outE2['V1']['max_tension'],11700,0.05,50,'V1_2 tension');
assert_close_rel($outE2['V2']['max_tension'],9967,0.05,50,'V2_2 tension');
assert_close_rel($outE2['D0']['max_compression'],-15889,0.05,50,'D0_2 compression');
assert_close_rel($outE2['D3']['max_compression'],-16611,0.05,50,'D3_2 compression');
// invalid input tests to satisfy spec requirement Raise Exception on invalid inputs
$bad=['joints'=>[],'members'=>[],'supports'=>[]]; $caught=false; try{ envelope($bad,$vehicle,1.0); } catch(Exception $e){ $caught=true; } if(!$caught){ echo "fail invalid empty truss not raising\n"; exit(1); }
$bad2=['joints'=>[['id'=>'A','x'=>0,'y'=>0]],'members'=>[],'supports'=>[['joint_id'=>'A','type'=>'invalid_type']]]; $caught2=false; try{ envelope($bad2,$vehicle,1.0); } catch(Exception $e){ $caught2=true; } if(!$caught2){ echo "fail invalid support type not raising\n"; exit(1); }
$bad3=['joints'=>[['id'=>'A','x'=>0,'y'=>0],['id'=>'B','x'=>0,'y'=>0]],'members'=>[['id'=>'M','i'=>'A','j'=>'B','A'=>0.01,'E'=>200e9]],'supports'=>[['joint_id'=>'A','type'=>'pinned'],['joint_id'=>'B','type'=>'roller']]]; $caught3=false; try{ envelope($bad3,$vehicle,1.0); } catch(Exception $e){ $caught3=true; } if(!$caught3){ echo "fail zero length not raising\n"; exit(1); }
echo "ok\n"; exit(0);
?>
