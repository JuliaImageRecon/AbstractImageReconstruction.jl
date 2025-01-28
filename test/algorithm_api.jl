@testset "API" begin
  # Partially testing if radon example is constructed correctly
  # These things are mostly covered by Literate.jl examples
  pre = RadonPreprocessingParameters(frames = collect(1:3))
  back_reco = RadonBackprojectionParameters(;angles)
  algo = DirectRadonAlgorithm(DirectRadonParameters(pre, back_reco))

  @test parameter(algo) isa DirectRadonParameters

  # High-level reco
  @test isready(algo) == false
  reco_1 = reconstruct(algo, sinograms)
  @test isready(algo) == false

  # Put!/take!
  put!(algo, sinograms)
  @test isready(algo)
  reco_2 = take!(algo)
  @test isapprox(reco_1, reco_2)
end