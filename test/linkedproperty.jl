export foo
foo(val) = length(val) % 2 == 0 ? 15 : 10

@testset "LinkedProperty" begin

  @testset "Observable" begin
    plan = RecoPlan(IterativeRadonAlgorithm; parameter = RecoPlan(IterativeRadonParameters;
          pre = RecoPlan(RadonPreprocessingParameters),
          reco = RecoPlan(IterativeRadonReconstructionParameters)))

    
    avg_obs = plan.parameter.pre[:numAverages]
    frame_obs = plan.parameter.pre[:frames]
    @test isempty(avg_obs.listeners)
    @test isempty(frame_obs.listeners)

    # Connect frames -> averages
    list = LinkedPropertyListener((val) -> length(val), plan.parameter.pre, :numAverages, plan.parameter.pre, :frames)
    @test !isempty(avg_obs.listeners)
    @test !isempty(frame_obs.listeners)

    # Call function
    @test ismissing(plan.parameter.pre.numAverages)
    plan.parameter.pre.frames = collect(1:5)
    @test plan.parameter.pre.numAverages == length(plan.parameter.pre.frames)

    # Deactivate when user supplies parameter
    plan.parameter.pre.numAverages = 50
    plan.parameter.pre.frames = collect(1:1)
    @test plan.parameter.pre.numAverages == 50
  end

  @testset "Serialization" begin
    plan = RecoPlan(IterativeRadonAlgorithm; parameter = RecoPlan(IterativeRadonParameters;
        pre = RecoPlan(RadonPreprocessingParameters),
        reco = RecoPlan(IterativeRadonReconstructionParameters)))

    # Connect across parameters
    list = LinkedPropertyListener(foo, plan.parameter.reco, :iterations, plan.parameter.pre, :frames)
    io = IOBuffer()
    toTOML(io, plan)

    seekstart(io)
    plan_copy = loadPlan(io, [Main, AbstractImageReconstruction, OurRadonReco])
    
    # Call function
    @test ismissing(plan.parameter.pre.numAverages)

    plan_copy.parameter.pre.frames = collect(1:5)
    @test plan_copy.parameter.reco.iterations == foo(plan_copy.parameter.pre.frames)

    # Deactivate when user supplies parameter
    plan_copy.parameter.reco.iterations = -1
    plan_copy.parameter.pre.frames = collect(1:2)
    @test plan_copy.parameter.reco.iterations == -1
  end
end