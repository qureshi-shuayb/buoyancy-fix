using Test
include("/app/truss_rating.jl")
# rating factor exact
@test rating_factor(100000.0,20000.0,50000.0) ≈ (100000-20000)/50000*0.9
@test rating_factor(100000.0,20000.0,0.0) == Inf
@test rating_factor(100000.0,20000.0,-5.0) == Inf
@test rating_factor(50000.0,60000.0,10000.0) < 0
# influence test triangle truss
joints=[Dict("id"=>"A","x"=>0.0,"y"=>0.0),Dict("id"=>"B","x"=>6.0,"y"=>0.0),Dict("id"=>"C","x"=>3.0,"y"=>4.0)]
members=[Dict("id"=>"AB","i"=>"A","j"=>"B","A"=>0.01,"E"=>200e9),Dict("id"=>"AC","i"=>"A","j"=>"C","A"=>0.01,"E"=>200e9),Dict("id"=>"BC","i"=>"B","j"=>"C","A"=>0.01,"E"=>200e9)]
supports=[Dict("joint_id"=>"A","type"=>"pinned"),Dict("joint_id"=>"B","type"=>"roller")]
truss=Dict("joints"=>joints,"members"=>members,"supports"=>supports)
ic_ac = influence_coefficient("AC","C",truss)
@test isa(ic_ac, Float64)
@test isapprox(ic_ac, 0.625, atol=0.05)
ic_ab = influence_coefficient("AB","C",truss)
@test isapprox(ic_ab, 0.375, atol=0.05)
ic_bc = influence_coefficient("BC","C",truss)
@test isapprox(ic_bc, ic_ac, atol=1e-6)
@test_throws ErrorException influence_coefficient("ZZ","C",truss)
@test_throws ErrorException influence_coefficient("AC","Z",truss)
# optimize test numeric
joints2=[Dict("id"=>"P0","x"=>0.0,"y"=>0.0),Dict("id"=>"P1","x"=>5.0,"y"=>0.0),Dict("id"=>"P2","x"=>10.0,"y"=>0.0),Dict("id"=>"P3","x"=>5.0,"y"=>4.0)]
members2=[Dict("id"=>"m1","i"=>"P0","j"=>"P1","A"=>0.01,"E"=>200e9,"capacity"=>200000.0,"dead_force"=>10000.0),Dict("id"=>"m2","i"=>"P1","j"=>"P2","A"=>0.01,"E"=>200e9,"capacity"=>200000.0,"dead_force"=>10000.0),Dict("id"=>"m3","i"=>"P0","j"=>"P3","A"=>0.01,"E"=>200e9,"capacity"=>150000.0,"dead_force"=>5000.0),Dict("id"=>"m4","i"=>"P1","j"=>"P3","A"=>0.01,"E"=>200e9,"capacity"=>150000.0,"dead_force"=>5000.0),Dict("id"=>"m5","i"=>"P2","j"=>"P3","A"=>0.01,"E"=>200e9,"capacity"=>150000.0,"dead_force"=>5000.0)]
supports2=[Dict("joint_id"=>"P0","type"=>"pinned"),Dict("joint_id"=>"P2","type"=>"roller")]
truss2=Dict("joints"=>joints2,"members"=>members2,"supports"=>supports2)
vehicle=Dict("axle_weights"=>[10000.0,10000.0],"spacings"=>[4.0])
out=optimize_rating(truss2,vehicle,1.0)
@test haskey(out,"scale_factor")
@test haskey(out,"achieved_RF")
@test haskey(out,"critical_member")
@test out["scale_factor"] > 0.1 && out["scale_factor"] < 5.0
@test isapprox(out["achieved_RF"], 1.0, atol=0.02)
@test out["achieved_RF"] >= 0.98 && out["achieved_RF"] <= 1.02
@test out["critical_member"] == "m4"
# check monotonic property: strict scaling
out_high = optimize_rating(truss2, vehicle, 1.5)
@test out_high["scale_factor"] < out["scale_factor"]
out_low = optimize_rating(truss2, vehicle, 0.9)
@test out_low["scale_factor"] > out["scale_factor"]
println("ok")
