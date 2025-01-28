@testset "Serialization" begin
  pre = RadonPreprocessingParameters(frames = collect(1:3))
  filter_reco = RadonFilteredBackprojectionParameters(;angles)
  algo = DirectRadonAlgorithm(DirectRadonParameters(pre, filter_reco))
  
  plan = toPlan(algo)

  io = IOBuffer()
  savePlan(io, plan)
  seekstart(io)
  plan_copy = loadPlan(io, [Main, AbstractImageReconstruction, RegularizedLeastSquares, OurRadonReco])
  @test hash(parameter(build(plan))) == hash(parameter(build(plan_copy)))
end