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



@testset "@reconstruction" begin

  Base.@kwdef struct TestParameters <: AbstractTestParameters
    value::Float64 = 1.0
    iterations::Int64 = 100
  end

  Base.@kwdef struct AnotherParameters <: AbstractTestParameters
    name::String = "test"
  end

  @testset "Basic algorithm definition" begin
    @reconstruction mutable struct SimpleAlgorithm <: AbstractTestBase
      @parameter parameter::TestParameters
    end
    
    # Check struct exists
    @test @isdefined SimpleAlgorithm
    
    # Check constructor works
    params = TestParameters(value=2.0)
    algo = SimpleAlgorithm(params)
    
    # Check fields exist
    @test hasfield(SimpleAlgorithm, :parameter)
    @test hasfield(SimpleAlgorithm, :_channel)
    @test algo.parameter === params
  end

  @testset "Nested Parametric algorithm definition" begin
    abstract type ParametricBase{P} <: AbstractTestBase end
    @reconstruction struct ParametricAlgo{P} <: ParametricBase{P}
      @parameter parameter::P
    end
    @test @isdefined ParametricBase

    params = TestParameters(value=2.0)
    algo = ParametricAlgo(params)
    @test algo.parameter === params
  end

  @testset "No supertype" begin
    @reconstruction mutable struct NoBaseAlgorithm
      @parameter parameter::TestParameters
    end

    @test @isdefined NoBaseAlgorithm
    
    # Check constructor works
    params = TestParameters(value=2.0)
    algo = NoBaseAlgorithm(params)
    @test algo isa AbstractImageReconstructionAlgorithm
  end

  @testset "State fields with defaults and different types" begin
    @reconstruction mutable struct AlgoWithDefaults <: AbstractTestBase
      @parameter parameter::TestParameters
      cache::Dict{String, Any} = Dict()
      optional_state::Int = 42
      name::String = "algorithm"
    end
    
    params = TestParameters()
    algo = AlgoWithDefaults(params)
    
    @test algo.cache == Dict()
    @test algo.optional_state == 42
    @test algo.name == "algorithm"
  end

  @testset "@init" begin
    @reconstruction mutable struct AlgoWithInit <: AbstractTestBase
      @parameter parameter::TestParameters
      value::Union{Nothing, Int64} = nothing

      @init function foo(algo::AlgoWithInit)
        algo.value = 42
      end
    end
    
    params = TestParameters()
    algo = AlgoWithInit(params)
    @test algo.value == 42
  end

  @testset "Generic algorithm with type parameter" begin
    @reconstruction struct GenericAlgorithm{P <: AbstractTestParameters} <: AbstractTestBase
      @parameter parameter::P
    end
    
    @test @isdefined GenericAlgorithm
    
    # Can construct with different parameter types
    params1 = TestParameters(value=1.0)
    algo1 = GenericAlgorithm(params1)
    @test algo1.parameter === params1
    
    params2 = AnotherParameters(name="test")
    algo2 = GenericAlgorithm(params2)
    @test algo2.parameter === params2
  end

  @testset "put! and take! interface" begin
    @reconstruction mutable struct InterfaceAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
    end
    
    # Define a simple process method
    function process(algo::InterfaceAlgo, params::TestParameters, input)
      return input * params.value
    end
    
    params = TestParameters(value=2.0)
    algo = InterfaceAlgo(params)
    
    # put! should work
    @test_nowarn put!(algo, 5.0)
    
    # take! should retrieve the result
    result = take!(algo)
    @test result == 10.0
  end

  @testset "isready and wait" begin
    @reconstruction mutable struct SyncAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
    end
    
    function process(algo::SyncAlgo, params::TestParameters, input)
      return input + params.value
    end
    
    params = TestParameters(value=1.0)
    algo = SyncAlgo(params)
    
    @test !isready(algo)
    
    put!(algo, 5.0)
    @test isready(algo)
    
    take!(algo)
    @test !isready(algo)
  end

  @testset "lock and unlock" begin
    @reconstruction mutable struct LockAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
    end
    
    function process(algo::LockAlgo, params::TestParameters, inputs...)
      return inputs[1]
    end
    
    params = TestParameters()
    algo = LockAlgo(params)
    
    # lock/unlock should work
    @test_nowarn lock(algo)
    @test_nowarn unlock(algo)
    
    # lock with function
    result = Ref(0)
    lock(algo) do
      result[] = 42
    end
    @test result[] == 42
  end

  @testset "parameter accessor" begin
    @reconstruction mutable struct ParamAccessAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
    end
    
    params = TestParameters(value=3.14)
    algo = ParamAccessAlgo(params)
    
    retrieved_params = parameter(algo)
    @test retrieved_params === params
    @test retrieved_params.value == 3.14
  end

  @testset "Channel FIFO behavior" begin
    @reconstruction mutable struct FIFOAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
    end
    
    function process(algo::FIFOAlgo, params::TestParameters, input)
      return input
    end
    
    params = TestParameters()
    algo = FIFOAlgo(params)
    
    # Queue multiple items
    put!(algo, 1)
    put!(algo, 2)
    put!(algo, 3)
    
    # Should retrieve in FIFO order
    @test take!(algo) == 1
    @test take!(algo) == 2
    @test take!(algo) == 3
  end

  @testset "Algorithm with many state fields" begin
    @reconstruction mutable struct ComplexAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
      cache::Dict = Dict()
      vector::Vector{Int} = Int[]
      flag::Bool = false
      count::Int = 0
      name::String = "complex"
    end
    
    params = TestParameters()
    algo = ComplexAlgo(params)
    
    @test algo.cache == Dict()
    @test algo.vector == Int[]
    @test algo.flag == false
    @test algo.count == 0
    @test algo.name == "complex"
  end

  @testset "Process with multiple inputs" begin
    @reconstruction struct MultiInputAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
    end
    
    function process(algo::MultiInputAlgo, params::TestParameters, x, y, z)
      return x + y + z + params.value
    end
    
    params = TestParameters(value=10.0)
    algo = MultiInputAlgo(params)
    
    put!(algo, 1, 2, 3)
    result = take!(algo)
    @test result == 16.0
  end

  @testset "Error: process not defined" begin
    @reconstruction struct NoProcessAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
    end
    
    params = TestParameters()
    algo = NoProcessAlgo(params)
    
    # put! should error if process is not defined
    @test_throws MethodError put!(algo, 5.0)
  end

  @testset "Algorithm fields are mutable" begin
    @reconstruction mutable struct MutableAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
      state::Dict = Dict()
    end
    
    params = TestParameters()
    algo = MutableAlgo(params)
    
    # Should be able to mutate state
    algo.state["key"] = "value"
    @test algo.state["key"] == "value"
    
    # Should be able to update reference fields
    algo.state = Dict("new" => "dict")
    @test algo.state == Dict("new" => "dict")
  end

  @testset "reconstruct() with algorithm" begin
    @reconstruction mutable struct ReconstructAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
    end
    
    function process(algo::ReconstructAlgo, params::TestParameters, inputs...)
      return inputs[1] + params.value
    end
    
    params = TestParameters(value=5.0)
    algo = ReconstructAlgo(params)
    
    result = reconstruct(algo, 10.0)
    @test result == 15.0
  end

  @testset "reconstruct() is thread-safe" begin
    @reconstruction struct ThreadAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
    end
    
    function process(algo::ThreadAlgo, params::TestParameters, inputs...)
      return inputs[1] * params.value
    end
    
    params = TestParameters(value=2.0)
    algo = ThreadAlgo(params)
    
    # Multiple concurrent reconstructs should work
    results = []
    @sync for i in 1:10
      @async push!(results, reconstruct(algo, Float64(i)))
    end
    
    @test length(results) == 10
    @test sort(results) == 2.0 .* (1:10)
  end

  @testset "Custom constructor with @reconstruction_internals" begin
    @reconstruction constructor = false mutable struct CustomConstructorAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
      computed_value::Float64
      derived_state::Int
    end

    function CustomConstructorAlgo(parameter::TestParameters, extra::Int)
      computed = parameter.value * 2
      derived = parameter.iterations + extra
      return CustomConstructorAlgo(parameter, computed, derived, @reconstruction_internals CustomConstructorAlgo)
    end

    params = TestParameters(value=5.0, iterations=100)
    algo = CustomConstructorAlgo(params, 50)

    @test algo.parameter === params
    @test algo.computed_value == 10.0
    @test algo.derived_state == 150
    @test hasfield(typeof(algo), :_channel)
  end

  @testset "Custom constructor with complex type parameters" begin
    @reconstruction constructor = false struct ComplexTypeAlgo{P,T} <: AbstractTestBase
      @parameter parameter::P
      data::T
    end

    function ComplexTypeAlgo(params::TestParameters, data::Vector{Float64})
      return ComplexTypeAlgo{typeof(params),typeof(data)}(params, data, @reconstruction_internals ComplexTypeAlgo)
    end

    params = TestParameters(value=1.0)
    data = [1.0, 2.0, 3.0]
    algo = ComplexTypeAlgo(params, data)

    @test algo.parameter === params
    @test algo.data === data
  end

  @testset "@init hook with state initialization" begin
    @reconstruction mutable struct InitHookAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
      initialized::Bool = false
      init_value::Float64 = 0.0

      @init function setup_algo(algo::InitHookAlgo)
        algo.initialized = true
        algo.init_value = algo.parameter.value * 10
      end
    end

    params = TestParameters(value=3.0)
    algo = InitHookAlgo(params)

    @test algo.initialized == true
    @test algo.init_value == 30.0
  end

  @testset "@init hook receives correct algorithm state" begin
    @reconstruction mutable struct InitStateCheckAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
      state::Dict{String,Any} = Dict()

      @init function populate_state(algo::InitStateCheckAlgo)
        algo.state["param_value"] = algo.parameter.value
        algo.state["param_iterations"] = algo.parameter.iterations
      end
    end

    params = TestParameters(value=42.0, iterations=200)
    algo = InitStateCheckAlgo(params)

    @test algo.state["param_value"] == 42.0
    @test algo.state["param_iterations"] == 200
  end

  @testset "Constructor generation can be disabled" begin
    @reconstruction constructor = false struct NoAutoConstructorAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
    end

    @test_throws MethodError NoAutoConstructorAlgo(TestParameters())

    function NoAutoConstructorAlgo(parameter::TestParameters)
      return NoAutoConstructorAlgo(parameter, @reconstruction_internals NoAutoConstructorAlgo)
    end

    params = TestParameters()
    algo = NoAutoConstructorAlgo(params)
    @test algo.parameter === params
  end

  @testset "Custom constructor with manual initialization" begin
    @reconstruction constructor = false mutable struct CustomInitAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
      setup_complete::Bool = false
    end

    function CustomInitAlgo(params::TestParameters)
      algo = CustomInitAlgo(params, false, @reconstruction_internals CustomInitAlgo)
      algo.setup_complete = true
      return algo
    end

    params = TestParameters()
    algo = CustomInitAlgo(params)

    @test algo.setup_complete == true
    @test algo.parameter === params
  end

  @testset "Custom constructor with process interface" begin
    @reconstruction constructor = false struct CustomProcAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
      multiplier::Float64
    end

    function CustomProcAlgo(params::TestParameters)
      return CustomProcAlgo(params, params.value * 2.0, @reconstruction_internals CustomProcAlgo)
    end

    function process(algo::CustomProcAlgo, params::TestParameters, input)
      return input * algo.multiplier
    end

    params = TestParameters(value=3.0)
    algo = CustomProcAlgo(params)

    put!(algo, 5.0)
    result = take!(algo)

    @test algo.multiplier == 6.0
    @test result == 30.0
  end

  @testset "@init with multiple state fields" begin
    @reconstruction mutable struct MultiStateInitAlgo <: AbstractTestBase
      @parameter parameter::TestParameters
      cache::Dict{String,Any} = Dict()
      history::Vector{Float64} = Float64[]
      counter::Int = 0

      @init function init_multi_state(algo::MultiStateInitAlgo)
        algo.cache["threshold"] = algo.parameter.value
        algo.history = [algo.parameter.value]
        algo.counter = algo.parameter.iterations
      end
    end

    params = TestParameters(value=7.5, iterations=42)
    algo = MultiStateInitAlgo(params)

    @test algo.cache["threshold"] == 7.5
    @test algo.history == [7.5]
    @test algo.counter == 42
  end

end
