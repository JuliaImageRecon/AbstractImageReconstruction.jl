# # Custom Algorithm Construction and Initialization

# The `@reconstruction` macro provides two mechanisms for customizing how algorithms are constructed:

# - The `@init` hook for simple initialization after struct creation
# - Custom constructors for complex type-parameter resolution

# ## Using @init for Simple Initialization

# The `@init` hook allows you to perform custom setup after the algorithm struct is constructed.

# This is useful when you need to initialize fields based on parameter values but don't need custom type resolution.

@parameter struct SimpleProcessingParameters <: AbstractImageReconstructionParameters
  threshold::Float64 = 0.5
  cache_size::Int = 100
end

@reconstruction mutable struct SimpleProcessingAlgorithm <: AbstractImageReconstructionAlgorithm
  @parameter params::SimpleProcessingParameters
  cache::Dict{String, Vector{Float64}} = Dict()
  statistics::NamedTuple = (calls=0, cache_hits=0)
  
  @init function setup_algorithm(algo::SimpleProcessingAlgorithm)
    # Pre-allocate cache entries based on parameter
    for i in 1:algo.params.cache_size
      algo.cache["buffer_$i"] = Float64[]
    end
    @info "Initialized algorithm with $(length(algo.cache)) cache buffers"
  end
end

# When we construct the algorithm, the `@init` hook is automatically called:

params = SimpleProcessingParameters(threshold=0.8, cache_size=50)
algo = SimpleProcessingAlgorithm(params)
length(algo.cache) == 50

# ## Using @init for validation

# The `@init` hook can also be used to perform validation or logging:

@parameter struct ValidationParameters <: AbstractImageReconstructionParameters
  min_value::Float64 = 0.0
  max_value::Float64 = 1.0
end

@reconstruction mutable struct ValidatingAlgorithm <: AbstractImageReconstructionAlgorithm
  @parameter params::ValidationParameters
  is_valid::Bool = false
  error_count::Int = 0
  
  @init function validate_config(algo::ValidatingAlgorithm)
    if algo.params.max_value <= algo.params.min_value
      algo.is_valid = false
      algo.error_count += 1
      @warn "Invalid range: max_value must be greater than min_value"
    else
      algo.is_valid = true
      @info "Algorithm configuration is valid"
    end
  end
end

params = ValidationParameters(min_value=0.0, max_value=1.0)
algo = ValidatingAlgorithm(params)

# Invalid parameters are caught by the @init hook, which could throw an error during:

params_invalid = ValidationParameters(min_value=1.0, max_value=0.5)
algo_invalid = ValidatingAlgorithm(params_invalid)

# ## Using Custom Constructor for Type-Dependent Initialization

# When the struct's type parameters depend on runtime values, we need a custom constructor.

# This is common when generic types need to be resolved based on the parameters.

@parameter struct MatrixProcessingParameters <: AbstractImageReconstructionParameters
  rows::Int = 10
  cols::Int = 10
  use_float32::Bool = false
end

# We need to disable the custom constructor and instead provide our own one:
@reconstruction constructor = false struct MatrixProcessingAlgorithm{T, MT <: AbstractMatrix{T}} <: AbstractImageReconstructionAlgorithm
  @parameter params::MatrixProcessingParameters
  workspace::MT
  element_type::Type{T}
end

# Since `@reconstruction` adds fields to our struct, we need to use the `@reconstruction_internals` macro to add those fields to the end in our custom constructor:
function MatrixProcessingAlgorithm(params::MatrixProcessingParameters)
  T = params.use_float32 ? Float32 : Float64
  MT = Matrix{T}
  
  workspace = zeros(T, params.rows, params.cols)
  
  return MatrixProcessingAlgorithm{T, MT}(
    params, 
    workspace, 
    T, 
    @reconstruction_internals MatrixProcessingAlgorithm
  )
end

params = MatrixProcessingParameters(rows=20, cols=30, use_float32=true)
algo = MatrixProcessingAlgorithm(params)
typeof(algo)