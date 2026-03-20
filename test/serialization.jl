@testset "Serialization" begin
  # Helper parameters for testing
  @parameter struct SerTestParams <: AbstractTestParameters
    value::Float64 = 1.0
    iterations::Int64 = 100
  end

  @testset "Basic save and load" begin
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

  @testset "RecoPlan lower - basic" begin
    plan = RecoPlan(SerTestParams)
    setproperty!(plan, :value, 2.0)
    
    dict = StructUtils.lower(RecoPlanStyle(), plan)
    
    @test haskey(dict, AbstractImageReconstruction.MODULE_TAG)
    @test haskey(dict, AbstractImageReconstruction.TYPE_TAG)
    @test haskey(dict, "value")
    @test dict["value"] == 2.0
    @test startswith(dict[AbstractImageReconstruction.TYPE_TAG], "RecoPlan{")
  end

  @testset "RecoPlan lower - all fields" begin
    plan = RecoPlan(SerTestParams)
    setproperty!(plan, :value, 3.14)
    setproperty!(plan, :iterations, 200)
    
    dict = StructUtils.lower(RecoPlanStyle(), plan)
    
    @test dict["value"] == 3.14
    @test dict["iterations"] == 200
  end

  @testset "RecoPlan lower - missing values" begin
    plan = RecoPlan(SerTestParams)
    # Don't set any values
    
    dict = StructUtils.lower(RecoPlanStyle(), plan)
    
    @test !haskey(dict, "value")
    @test !haskey(dict, "iterations")
    @test haskey(dict, AbstractImageReconstruction.MODULE_TAG)
    @test haskey(dict, AbstractImageReconstruction.TYPE_TAG)
  end

  @testset "Nested RecoPlan serialization" begin
    @chain struct NestedChain <: AbstractTestParameters
      first::SerTestParams
      second::SerTestParams
    end
    
    plan = RecoPlan(NestedChain)
    plan.first = RecoPlan(SerTestParams; value=1.0)
    plan.second = RecoPlan(SerTestParams; value=2.0)
    
    dict = StructUtils.lower(RecoPlanStyle(), plan)
    
    @test haskey(dict, "first")
    @test haskey(dict, "second")
    @test dict["first"] isa Dict
    @test dict["second"] isa Dict
    @test dict["first"]["value"] == 1.0
    @test dict["second"]["value"] == 2.0
  end

  @testset "Lower primitive types" begin
    @test StructUtils.lower(RecoPlanStyle(), 42) == 42
    @test StructUtils.lower(RecoPlanStyle(), 3.14) == 3.14
    @test StructUtils.lower(RecoPlanStyle(), "hello") == "hello"
    @test StructUtils.lower(RecoPlanStyle(), true) == true
  end

  @testset "Lower special types" begin
    # Symbol
    result = StructUtils.lower(RecoPlanStyle(), :mysymbol)
    @test result == "mysymbol"
    # Module
    result = StructUtils.lower(RecoPlanStyle(), Main)
    @test result == "Main"
    # Nothing
    result = StructUtils.lower(RecoPlanStyle(), nothing)
    @test result == Dict()
    # Type
    dict = StructUtils.lower(RecoPlanStyle(), Float64)
    @test dict isa Dict
    @test dict[AbstractImageReconstruction.TYPE_TAG] == "Type"
    @test dict[AbstractImageReconstruction.AbstractImageReconstruction.VALUE_TAG] == "Float64"
    @test haskey(dict, AbstractImageReconstruction.MODULE_TAG)
    # Functions
    dict = StructUtils.lower(RecoPlanStyle(), sin)
    @test dict isa Dict
    @test dict[AbstractImageReconstruction.TYPE_TAG] == "sin"
    @test haskey(dict, AbstractImageReconstruction.MODULE_TAG)
  end

  @testset "Lower arrays" begin
    arr = [1, 2, 3]
    result = StructUtils.lower(RecoPlanStyle(), arr)
    @test result == [1, 2, 3]
    
    arr_float = [1.0, 2.0, 3.0]
    result = StructUtils.lower(RecoPlanStyle(), arr_float)
    @test result == [1.0, 2.0, 3.0]
  end

  @testset "Lower tuples" begin
    tup = (1, 2, 3)
    result = StructUtils.lower(RecoPlanStyle(), tup)
    @test result == [1, 2, 3]
    
    tup_mixed = (1, 2.0, "three")
    result = StructUtils.lower(RecoPlanStyle(), tup_mixed)
    @test result == [1, 2.0, "three"]
  end

  @testset "Lower complex numbers" begin
    c = 3.0 + 4.0im
    result = StructUtils.lower(RecoPlanStyle(), c)
    @test result isa String
    @test occursin("3.0", result)
    @test occursin("4.0", result)
  end

  @testset "Lower array of RecoPlan" begin
    @parameter struct ArrayContainer <: AbstractTestParameters
      items::Vector{SerTestParams}
    end
    
    plan = RecoPlan(ArrayContainer)
    plan.items = [
      RecoPlan(SerTestParams; value=1.0),
      RecoPlan(SerTestParams; value=2.0)
    ]
    
    dict = StructUtils.lower(RecoPlanStyle(), plan)
    
    @test haskey(dict, "items")
    @test dict["items"] isa Vector
    @test length(dict["items"]) == 2
    @test all(item -> item isa Dict, dict["items"])
  end

  @testset "Lift primitive types" begin
    src = 42
    val, _ = StructUtils.lift(RecoPlanStyle(), Int, src)
    @test val == src

    src = 42
    val, _ = StructUtils.lift(RecoPlanStyle(), Int, src)
    @test val == src
  end

  @testset "Lift Symbol" begin
    val, _ = StructUtils.lift(RecoPlanStyle(), Symbol, "test")
    @test val == :test
  end

  @testset "Lift Type" begin
    dict = Dict{String, Any}(
      AbstractImageReconstruction.MODULE_TAG => "Core",
      AbstractImageReconstruction.TYPE_TAG => "Type",
      AbstractImageReconstruction.AbstractImageReconstruction.VALUE_TAG => "Float64"
      )
    
    with(MODULE_DICT => AbstractImageReconstruction.AbstractImageReconstruction.ModuleDict([Main, Core])) do
      lifted, src = StructUtils.lift(RecoPlanStyle(), Type, dict)
      @test lifted == Float64
      @test src == dict
    end
  end

  @testset "Lift Nothing" begin
    source = Dict{String, Any}()
    lifted, src = StructUtils.lift(RecoPlanStyle(), Nothing, source)
    @test lifted === nothing
    @test src == source
  end

  @testset "Lift arrays" begin
    source = [1, 2, 3]
    lifted, src = StructUtils.lift(RecoPlanStyle(), AbstractArray{Int}, source)
    @test lifted == [1, 2, 3]
    @test src == source
  end

  @testset "Lift tuples" begin
    source = [1, 2, 3]
    lifted, src = StructUtils.lift(RecoPlanStyle(), NTuple{3, Int}, source)
    @test lifted == (1, 2, 3)
    @test src == source
  end

  @testset "Make RecoPlan - basic" begin
    dict = Dict{String, Any}(
      AbstractImageReconstruction.MODULE_TAG => string(parentmodule(SerTestParams)),
      AbstractImageReconstruction.TYPE_TAG => "RecoPlan{SerTestParams}",
      "value" => 5.0
    )
    
    with(MODULE_DICT => AbstractImageReconstruction.ModuleDict([Main])) do
      plan, returned_dict = StructUtils.make(RecoPlanStyle(), RecoPlan, dict)
      @test plan isa RecoPlan{SerTestParams}
      @test getproperty(plan, :value) == 5.0
      @test returned_dict == dict
    end
  end

  @testset "Make RecoPlan - all fields" begin
    dict = Dict{String, Any}(
      AbstractImageReconstruction.MODULE_TAG => string(parentmodule(SerTestParams)),
      AbstractImageReconstruction.TYPE_TAG => "RecoPlan{SerTestParams}",
      "value" => 2.5,
      "iterations" => 50
    )
    
    with(MODULE_DICT => AbstractImageReconstruction.ModuleDict([Main])) do
      plan, _ = StructUtils.make(RecoPlanStyle(), RecoPlan, dict)
      @test plan isa RecoPlan{SerTestParams}
      @test getproperty(plan, :value) == 2.5
      @test getproperty(plan, :iterations) == 50
    end
  end

  @testset "Make RecoPlan for algorithm" begin
    @reconstruction struct SerTestAlgo <: AbstractTestBase
      @parameter parameter::SerTestParams
    end
    
    param_dict = Dict{String, Any}(
      AbstractImageReconstruction.MODULE_TAG => string(parentmodule(SerTestParams)),
      AbstractImageReconstruction.TYPE_TAG => "RecoPlan{SerTestParams}",
      "value" => 2.0
    )
    
    algo_dict = Dict{String, Any}(
      AbstractImageReconstruction.MODULE_TAG => string(parentmodule(SerTestAlgo)),
      AbstractImageReconstruction.TYPE_TAG => "RecoPlan{SerTestAlgo}",
      "parameter" => param_dict
    )
    
    with(MODULE_DICT => AbstractImageReconstruction.ModuleDict([Main])) do
      plan, _ = StructUtils.make(RecoPlanStyle(), RecoPlan, algo_dict)
      @test plan isa RecoPlan{SerTestAlgo}
      @test plan.parameter isa RecoPlan{SerTestParams}
      @test plan.parameter.value == 2.0
    end
  end

  @testset "Round-trip with IOBuffer" begin
    plan = RecoPlan(SerTestParams)
    setproperty!(plan, :value, 7.5)
    setproperty!(plan, :iterations, 200)
    
    io = IOBuffer()
    savePlan(io, plan)
    seekstart(io)
    
    loaded = loadPlan(io, [Main])
    
    @test loaded isa RecoPlan{SerTestParams}
    @test getproperty(loaded, :value) == 7.5
    @test getproperty(loaded, :iterations) == 200
  end

  @testset "Round-trip with file" begin
    plan = RecoPlan(SerTestParams)
    setproperty!(plan, :value, 9.9)
    setproperty!(plan, :iterations, 300)
    
    mktempdir() do dir
      filepath = joinpath(dir, "test_plan.toml")
      savePlan(filepath, plan)
      
      @test isfile(filepath)
      
      loaded = loadPlan(filepath, [Main])
      @test loaded isa RecoPlan{SerTestParams}
      @test getproperty(loaded, :value) == 9.9
      @test getproperty(loaded, :iterations) == 300
    end
  end

  @testset "Round-trip with nested plans" begin
    @chain struct NestedChain <: AbstractTestParameters
      step1::SerTestParams
      step2::SerTestParams
    end
    
    outer = RecoPlan(NestedChain)
    outer.step1 = RecoPlan(SerTestParams; value=1.5, iterations=50)
    outer.step2 = RecoPlan(SerTestParams; value=2.5, iterations=100)
    
    io = IOBuffer()
    savePlan(io, outer)
    seekstart(io)
    
    loaded = loadPlan(io, [Main])
    
    @test loaded isa RecoPlan{NestedChain}
    @test loaded.step1 isa RecoPlan{SerTestParams}
    @test loaded.step2 isa RecoPlan{SerTestParams}
    @test loaded.step1.value == 1.5
    @test loaded.step1.iterations == 50
    @test loaded.step2.value == 2.5
    @test loaded.step2.iterations == 100
  end

  @testset "Round-trip with array of plans" begin
    @parameter struct ArrayContainer <: AbstractTestParameters
      items::Vector{SerTestParams}
    end
    
    plan = RecoPlan(ArrayContainer)
    plan.items = [
      RecoPlan(SerTestParams; value=1.0, iterations=10),
      RecoPlan(SerTestParams; value=2.0, iterations=20)
    ]
    
    io = IOBuffer()
    savePlan(io, plan)
    seekstart(io)
    
    loaded = loadPlan(io, [Main])
    
    @test loaded isa RecoPlan{ArrayContainer}
    @test loaded.items isa Vector
    @test length(loaded.items) == 2
    @test all(item -> item isa RecoPlan{SerTestParams}, loaded.items)
    @test loaded.items[1].value == 1.0
    @test loaded.items[2].value == 2.0
  end

  @testset "Empty plan round-trip" begin
    plan = RecoPlan(SerTestParams)
    # Don't set any fields
    
    io = IOBuffer()
    savePlan(io, plan)
    seekstart(io)
    
    loaded = loadPlan(io, [Main])
    
    @test loaded isa RecoPlan{SerTestParams}
    @test ismissing(loaded.value)
    @test ismissing(loaded.iterations)
  end

  @testset "Custom style - lower override" begin
    struct TestCustomStyle <: CustomPlanStyle end
    
    # Override lower for Float64
    StructUtils.lower(::TestCustomStyle, x::Float64) = round(x, digits=1)
    
    plan = RecoPlan(SerTestParams)
    plan.value = 3.14159
    
    io = IOBuffer()
    savePlan(io, plan, field_style=TestCustomStyle())
    seekstart(io)
    
    dict = TOML.parse(io)
    @test dict["value"] == 3.1
  end

  @testset "Custom style - fallback behavior" begin
    struct MinimalCustomStyle <: CustomPlanStyle end
    # Don't override anything - should fallback to RecoPlanStyle
    
    plan = RecoPlan(SerTestParams)
    plan.value = 5.0
    
    dict = StructUtils.lower(MinimalCustomStyle(), plan)
    
    @test haskey(dict, "value")
    @test dict["value"] == 5.0
  end

  @testset "Parent relationships after load" begin
    @chain struct ParentChain <: AbstractTestParameters
      child::SerTestParams
    end
    
    plan = RecoPlan(ParentChain)
    child_plan = RecoPlan(SerTestParams; value=5.0)
    plan.child = child_plan
    
    # Check parent is set before save
    @test AbstractTrees.parent(child_plan) === plan
    
    io = IOBuffer()
    savePlan(io, plan)
    seekstart(io)
    
    loaded = loadPlan(io, [Main])
    
    # Parent should be restored after load
    @test AbstractTrees.parent(loaded.child) === loaded
  end

  @testset "AbstractImageReconstruction.ModuleDict construction" begin
    modDict = AbstractImageReconstruction.ModuleDict([Main, Core])
    
    @test modDict.dict isa Dict
    @test haskey(modDict.dict, "Main")
    @test haskey(modDict.dict, "Core")
  end

  @testset "AbstractImageReconstruction.ModuleDict getindex" begin
    modDict = AbstractImageReconstruction.ModuleDict([Main])
    
    result = modDict["Main", "SerTestParams"]
    @test result !== nothing
    @test result == SerTestParams
  end

  @testset "AbstractImageReconstruction.ModuleDict - nonexistent type" begin
    modDict = AbstractImageReconstruction.ModuleDict([Main])
    
    result = modDict["Main", "NonexistentType"]
    @test result === nothing
    
    result = modDict["NonexistentModule", "SomeType"]
    @test result === nothing
  end

  @testset "Scoped MODULE_DICT" begin
    modDict = AbstractImageReconstruction.ModuleDict([Main])
    
    with(MODULE_DICT => modDict) do
      result = MODULE_DICT["Main", "SerTestParams"]
      @test result == SerTestParams
    end
  end

  @testset "Build after load preserves structure" begin
    pre = RadonPreprocessingParameters(frames = collect(1:3))
    filter_reco = RadonFilteredBackprojectionParameters(;angles)
    algo = DirectRadonAlgorithm(DirectRadonParameters(pre, filter_reco))
    
    plan = toPlan(algo)
    
    io = IOBuffer()
    savePlan(io, plan)
    seekstart(io)
    
    loaded_plan = loadPlan(io, [Main, AbstractImageReconstruction, RegularizedLeastSquares, OurRadonReco])
    
    built_original = build(plan)
    built_loaded = build(loaded_plan)
    
    @test typeof(built_original) == typeof(built_loaded)
    @test typeof(parameter(built_original)) == typeof(parameter(built_loaded))
  end

  @testset "Parametric types serialization" begin
    @parameter struct ParametricSerParams{T} <: AbstractTestParameters
      data::T
      count::Int = 0
    end
    
    plan = RecoPlan(ParametricSerParams{Float64})
    plan.data = 3.14
    plan.count = 5
    
    io = IOBuffer()
    savePlan(io, plan)
    seekstart(io)
    
    loaded = loadPlan(io, [Main])
    
    @test loaded isa RecoPlan
    @test getproperty(loaded, :data) == 3.14
    @test getproperty(loaded, :count) == 5
  end

  @testset "Error - invalid AbstractImageReconstruction.TYPE_TAG" begin
    dict = Dict{String, Any}(
      AbstractImageReconstruction.MODULE_TAG => "Main",
      AbstractImageReconstruction.TYPE_TAG => "InvalidFormat"  # Missing RecoPlan{...}
    )
    
    with(MODULE_DICT => AbstractImageReconstruction.ModuleDict([Main])) do
      @test_throws ErrorException StructUtils.make(RecoPlanStyle(), RecoPlan, dict)
    end
  end

  @testset "Error - missing module in AbstractImageReconstruction.ModuleDict" begin
    dict = Dict{String, Any}(
      AbstractImageReconstruction.MODULE_TAG => "NonexistentModule",
      AbstractImageReconstruction.TYPE_TAG => "RecoPlan{SomeType}"
    )
    
    io = IOBuffer()
    TOML.print(io, dict)
    seekstart(io)
    
    # Should error when trying to find the type
    @test_throws Exception loadPlan(io, [Main])
  end


  @testset "Enum serialization" begin
    # Define test enum
    @enum TestStatus begin
      STATUS_IDLE = 1
      STATUS_RUNNING = 2
      STATUS_COMPLETE = 3
      STATUS_ERROR = 4
    end

    @parameter struct EnumParams <: AbstractTestParameters
      status::TestStatus = STATUS_IDLE
      priority::TestStatus = STATUS_COMPLETE
    end

    @testset "Lower enum to string" begin
      result = StructUtils.lower(RecoPlanStyle(), STATUS_RUNNING)
      @test result == "STATUS_RUNNING"

      result = StructUtils.lower(RecoPlanStyle(), STATUS_ERROR)
      @test result == "STATUS_ERROR"
    end

    @testset "Lower enum in parameter" begin
      params = EnumParams(status = STATUS_RUNNING, priority = STATUS_COMPLETE)
      plan = toPlan(params)

      dict = StructUtils.lower(RecoPlanStyle(), plan)

      @test dict["status"] == "STATUS_RUNNING"
      @test dict["priority"] == "STATUS_COMPLETE"
    end

    @testset "Lift string to enum" begin
      lifted, src = StructUtils.lift(RecoPlanStyle(), TestStatus, "STATUS_RUNNING")
      @test lifted == STATUS_RUNNING
      @test src == "STATUS_RUNNING"

      lifted, src = StructUtils.lift(RecoPlanStyle(), TestStatus, "STATUS_ERROR")
      @test lifted == STATUS_ERROR
      @test src == "STATUS_ERROR"
    end

    @testset "Round-trip enum parameter" begin
      plan = RecoPlan(EnumParams)
      plan.status = STATUS_RUNNING
      plan.priority = STATUS_COMPLETE

      io = IOBuffer()
      savePlan(io, plan)
      seekstart(io)

      loaded = loadPlan(io, [Main])

      @test loaded isa RecoPlan{EnumParams}
      @test getproperty(loaded, :status) == STATUS_RUNNING
      @test getproperty(loaded, :priority) == STATUS_COMPLETE
    end

    @testset "Array of enums" begin
      @parameter struct MultiEnumParams <: AbstractTestParameters
        statuses::Vector{TestStatus} = [STATUS_IDLE]
      end

      plan = RecoPlan(MultiEnumParams)
      plan.statuses = [STATUS_IDLE, STATUS_RUNNING, STATUS_COMPLETE]

      dict = StructUtils.lower(RecoPlanStyle(), plan)

      @test dict["statuses"] == ["STATUS_IDLE", "STATUS_RUNNING", "STATUS_COMPLETE"]

      # Round-trip test
      io = IOBuffer()
      savePlan(io, plan)
      seekstart(io)

      loaded = loadPlan(io, [Main])

      @test loaded isa RecoPlan{MultiEnumParams}
      @test getproperty(loaded, :statuses) == [STATUS_IDLE, STATUS_RUNNING, STATUS_COMPLETE]
    end

    @testset "Enum with different underlying types" begin
      @enum IntEnum::Int64 begin
        SMALL = 1
        MEDIUM = 2
        LARGE = 3
      end

      @parameter struct IntEnumParams <: AbstractTestParameters
        size::IntEnum = SMALL
      end

      plan = RecoPlan(IntEnumParams)
      plan.size = LARGE

      io = IOBuffer()
      savePlan(io, plan)
      seekstart(io)

      loaded = loadPlan(io, [Main])

      @test loaded isa RecoPlan{IntEnumParams}
      @test getproperty(loaded, :size) == LARGE
      @test typeof(getproperty(loaded, :size)) == IntEnum
    end

    @testset "Enum default values" begin
      plan = RecoPlan(EnumParams)
      # Don't set values - use defaults

      io = IOBuffer()
      savePlan(io, plan)
      seekstart(io)

      loaded = loadPlan(io, [Main])
      built = build(loaded)

      # Should use the defaults defined in the struct
      @test built.status == STATUS_IDLE
      @test built.priority == STATUS_COMPLETE
    end

    @testset "Enum in nested parameters" begin
      @chain struct ChainWithEnum <: AbstractTestParameters
        step1::EnumParams
        step2::EnumParams
      end

      outer = RecoPlan(ChainWithEnum)
      outer.step1 = RecoPlan(EnumParams; status=STATUS_RUNNING)
      outer.step2 = RecoPlan(EnumParams; status=STATUS_ERROR)

      io = IOBuffer()
      savePlan(io, outer)
      seekstart(io)

      loaded = loadPlan(io, [Main])

      @test loaded.step1.status == STATUS_RUNNING
      @test loaded.step2.status == STATUS_ERROR
    end

    @testset "Invalid enum value error" begin
      # Manually create a dict with invalid enum value
      dict = Dict{String, Any}(
        MODULE_TAG => string(parentmodule(EnumParams)),
        TYPE_TAG => "RecoPlan{EnumParams}",
        "status" => "INVALID_STATUS"
      )

      io = IOBuffer()
      TOML.print(io, dict)
      seekstart(io)

      # Should error when trying to parse invalid enum value
      @test_throws Exception loadPlan(io, [Main])
    end
  end

  @testset "Union field serialization" begin
    @parameter struct UnionParams <: AbstractTestParameters
      value::Union{Float64, Int64, String} = 1.0
      optional::Union{Nothing, Vector{Float64}} = nothing
    end

    @testset "Basic Union" begin
      plan = RecoPlan(UnionParams)

      # Float
      plan.value = 3.14
      dict = StructUtils.lower(RecoPlanStyle(), plan)
      @test haskey(dict, "value")
      @test dict["value"] isa Dict
      @test dict["value"][AbstractImageReconstruction.UNION_TYPE_TAG] == "Float64"
      @test dict["value"][AbstractImageReconstruction.VALUE_TAG] == 3.14
      
      # Integer
      plan.value = 42
      dict = StructUtils.lower(RecoPlanStyle(), plan)
      @test dict["value"][AbstractImageReconstruction.UNION_TYPE_TAG] == "Int64"
      @test dict["value"][AbstractImageReconstruction.VALUE_TAG] == 42

      # String
      plan.value = "hello"
      dict = StructUtils.lower(RecoPlanStyle(), plan)
      @test dict["value"][AbstractImageReconstruction.UNION_TYPE_TAG] == "String"
      @test dict["value"][AbstractImageReconstruction.VALUE_TAG] == "hello"
      
      # Nothing
      plan = RecoPlan(UnionParams)
      plan.optional = nothing
      dict = StructUtils.lower(RecoPlanStyle(), plan)
      @test haskey(dict, "optional")
      @test dict["optional"][AbstractImageReconstruction.UNION_TYPE_TAG] == "Nothing"
    end

    @testset "Union round-trip" begin
      plan = RecoPlan(UnionParams)
      plan.value = 99
      plan.optional = [1.0, 2.0, 3.0]

      io = IOBuffer()
      savePlan(io, plan)
      seekstart(io)

      loaded = loadPlan(io, [Main])

      @test loaded isa RecoPlan{UnionParams}
      @test getproperty(loaded, :value) == 99
      @test getproperty(loaded, :value) isa Int64  # Verify correct type was inferred
      @test getproperty(loaded, :optional) == [1.0, 2.0, 3.0]
    end

    @testset "Union with parametric type" begin
      @parameter struct ParametricUnionParams <: AbstractTestParameters
        data::Union{Vector{Float64}, Vector{Int64}} = Float64[]
      end

      plan = RecoPlan(ParametricUnionParams)
      plan.data = [1.0, 2.0, 3.0]

      dict = StructUtils.lower(RecoPlanStyle(), plan)

      @test dict["data"][AbstractImageReconstruction.UNION_TYPE_TAG] == "Vector{Float64}"

      # Round-trip
      io = IOBuffer()
      savePlan(io, plan)
      seekstart(io)

      loaded = loadPlan(io, [Main])
      @test getproperty(loaded, :data) == [1.0, 2.0, 3.0]
      @test eltype(getproperty(loaded, :data)) == Float64  # Correct type inferred
    end

    @testset "Union ambiguity resolution" begin
      # Test that the deserializer correctly picks the right type
      # when multiple members could technically hold the data
      plan = RecoPlan(UnionParams)

      # Integer value should deserialize as Int64, not Float64
      plan.value = 42
      io = IOBuffer()
      savePlan(io, plan)
      seekstart(io)
      loaded = loadPlan(io, [Main])
      @test getproperty(loaded, :value) isa Int64

      # Float value should deserialize as Float64
      plan.value = 3.14
      io = IOBuffer()
      savePlan(io, plan)
      seekstart(io)
      loaded = loadPlan(io, [Main])
      @test getproperty(loaded, :value) isa Float64
    end
  end


end