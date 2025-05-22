@testset "RecoPlan" begin
  pre = RadonPreprocessingParameters(frames = collect(1:3))
  reco = IterativeRadonReconstructionParameters(; shape = size(images)[1:3], angles = angles, iterations = 1, reg = [L2Regularization(0.001), PositiveRegularization()], solver = CGNR);
  algo = IterativeRadonAlgorithm(IterativeRadonParameters(pre, reco))

  
  @testset "Construction" begin
    # From algorithm
    plan_fromAlgo = toPlan(algo)

    # With kwarg constructor
    plan_fromKwargs = RecoPlan(IterativeRadonAlgorithm; parameter = RecoPlan(IterativeRadonParameters; pre = RecoPlan(RadonPreprocessingParameters; frames = collect(1:3)), 
      reco = RecoPlan(IterativeRadonReconstructionParameters; shape = size(images)[1:3], angles = angles, iterations = 1, reg = [L2Regularization(0.001), PositiveRegularization()], solver = CGNR)))

    # Individually with setproperty!
    plan_pre = RecoPlan(RadonPreprocessingParameters)
    plan_pre.frames = collect(1:3)
    @test build(plan_pre).frames == collect(1:3)
    @test build(plan_pre) isa RadonPreprocessingParameters

    plan_reco = RecoPlan(IterativeRadonReconstructionParameters)
    plan_reco.shape = size(images)[1:3]
    plan_reco.angles = angles
    plan_reco.iterations = 1
    plan_reco.reg = [L2Regularization(0.001), PositiveRegularization()]
    plan_reco.solver = CGNR
    @test build(plan_reco).solver == plan_reco.solver
    @test build(plan_reco) isa IterativeRadonReconstructionParameters

    plan_params = RecoPlan(IterativeRadonParameters)
    plan_params.pre = plan_pre
    plan_params.reco = plan_reco

    plan_set = RecoPlan(IterativeRadonAlgorithm)
    plan_set.parameter = plan_params

    algo_1 = build(plan_fromAlgo)
    algo_2 = build(plan_fromKwargs)
    algo_3 = build(plan_set)
    # Not the best, but the types dont define proper equals, so we use our default hash method
    @test hash(algo_1.parameter.pre) == hash(algo_2.parameter.pre)
    @test hash(algo_2.parameter.pre) == hash(algo_3.parameter.pre)
    @test hash(algo_1.parameter.reco) == hash(algo_2.parameter.reco)
    @test hash(algo_2.parameter.reco) == hash(algo_3.parameter.reco)
  end

  @testset "Properties" begin
    # Test parameter with union property type
    plan = RecoPlan(RadonFilteredBackprojectionParameters)
    instance = nothing
    
    @testset "Setter/Getter" begin
      # Init missing
      @test ismissing(plan.angles)
      @test ismissing(plan.filter)

      # Set/get
      plan.angles = angles
      @test plan.angles == angles
      @test_throws Exception plan.doesntExist = 42

      # Type checking
      plan.filter = nothing
      @test isnothing(plan.filter)
      @test_throws Exception plan.filter = "Test"
      @test isnothing(plan.filter)
      plan.filter = missing
      @test ismissing(plan.filter)
      plan.filter = [0.2]
      @test plan.filter == [0.2]

      # Clearing
      clear!(plan)
      @test ismissing(plan.angles)
      @test ismissing(plan.filter)
      
      # Used during construction
      plan.angles = angles
      instance = build(plan)
      @test instance.angles == angles
      @test isnothing(instance.filter) # Default kwarg
    end

    outer = RecoPlan(DirectRadonParameters)
    incorrect = RecoPlan(RadonPreprocessingParameters)
    @testset "Nested Plans" begin
      # Type checking
      @test_throws Exception outer.reco = incorrect
      outer.reco = instance
      @test outer.reco == instance
      outer.reco = plan
      @test outer.reco == plan
      # Clearing
      plan.angles = angles
      @test !ismissing(outer.reco.angles)
      clear!(outer)
      @test ismissing(outer.reco.angles)
      clear!(outer, false)
      @test ismissing(outer.reco)
    end

    @testset "SetAll!" begin
      # setAll! variants
      clear!(plan)
      # Kwargs
      setAll!(plan; angles = angles, filter = nothing, doesntExist = 42)
      @test plan.angles == angles
      @test isnothing(plan.filter)
      clear!(plan)
      # Dict{Symbol}
      setAll!(plan, Dict{Symbol, Any}(:angles => angles, :filter => nothing, :doesntExist => 42))
      @test plan.angles == angles
      @test isnothing(plan.filter)
      clear!(plan)
      # Dict{String}
      setAll!(plan, Dict{String, Any}("angles" => angles, "filter" => nothing, "doesntExist" => 42))
      @test plan.angles == angles
      @test isnothing(plan.filter)
      clear!(plan)
      # Nested plan
      outer.reco = plan
      setAll!(plan; angles = angles, filter = nothing)
      @test plan.angles == angles
      @test isnothing(plan.filter)
      clear!(plan)
    end

    @testset "Property names" begin
      # Property names and filtering
      struct TestParameters <: AbstractImageReconstructionParameters
        a::Int64
        b::Float64
        _c::String
      end
      test = RecoPlan(TestParameters)
      @test in(:a, collect(propertynames(test)))
      @test in(:b, collect(propertynames(test)))
      @test !in(:c, collect(propertynames(test)))
    end
  end

  @testset "Observables" begin
    plan = RecoPlan(RadonFilteredBackprojectionParameters)
    observed = Ref{Bool}()
    fun = (val) -> observed[] = true
    on(fun, plan, :angles)
    plan.angles = angles
    @test observed[]
    observed[] = false
    try 
      plan.angles = "Test"
    catch e
    end
    @test !(observed[])

    off(plan, :angles, fun)
    plan.angles = angles
    @test !(observed[])

    obsv = plan[:angles]
    @test obsv isa Observable

    on(fun, plan, :angles)
    clear!(plan)
    plan.angles = angles
    @test !(observed[])
  end

  @testset "Traversal" begin
    plan = toPlan(algo)

    parameter = plan.parameter
    @test parameter isa RecoPlan
    @test parameter == first(children(plan))
    @test plan === AbstractTrees.parent(parameter)

    pre_plan = parameter.pre
    reco_plan = parameter.reco
    param_children = children(parameter)
    @test length(param_children) == 2
    for child in [pre_plan, reco_plan]
      @test child isa RecoPlan
      @test parameter == AbstractTrees.parent(child)
      @test in(child, param_children)
    end

  end

end