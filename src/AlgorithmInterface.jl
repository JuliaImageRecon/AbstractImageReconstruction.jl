export AbstractImageReconstructionAlgorithm
"""
    AbstractImageReconstructionAlgorithm

Abstract type for image reconstruction algorithms. Must implement `put!` and `take!` functions. Serialization expects a constructor with a single `AbstractImageReconstructionParameters` argument.
"""
abstract type AbstractImageReconstructionAlgorithm end

export AbstractImageReconstructionParameters
"""
    AbstractImageReconstructionParameters

Abstract type for image reconstruction parameters.  An algorithm consists of one ore more `process` steps, each can have its own parameters. Parameters can be arbitrarly nested. 
"""
abstract type AbstractImageReconstructionParameters end

export AbstractUtilityReconstructionParameters
"""
    AbstractUtilityReconstructionParameters{T <: AbstractImageReconstructionParameters}

Abstract type that offer utility functions for a given reconstruction parameter and its associated `process` steps. Utility `process` steps should return the same result as `T` for the same inputs.
"""
abstract type AbstractUtilityReconstructionParameters{T <: AbstractImageReconstructionParameters} <: AbstractImageReconstructionParameters end

export put!, take!
"""
    put!(algo::AbstractImageReconstructionAlgorithm, inputs...)

Perform image reonstruction with algorithm `algo` on given `ìnputs`. Depending on the algorithm this might block. Result is stored and can be retrieved with `take!`.
"""
put!(algo::AbstractImageReconstructionAlgorithm, inputs...) = error("$(typeof(algo)) must implement put!")
"""
    take!(algo::AbstractImageReconstructionAlgorithm)

Remove and return a stored result from the algorithm `algo`. Blocks until a result is available.
"""
take!(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement take!")
"""
    isready(algo::AbstractImageReconstructionAlgorithm)

Determine if the algorithm `algo` has a result available.
"""
isready(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement isready")
"""
    wait(algo::AbstractImageReconstructionAlgorithm)

Wait for a result to be available from the specified `algo`.
"""
wait(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement wait")
"""
    lock(algo::AbstractImageReconstructionAlgorithm)

Acquire a lock on the algorithm `algo`. If the lock is already acquired, wait until it is released.

Each `lock` must be matched with a `unlock`.
"""
lock(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement lock")
"""
    unlock(algo::AbstractImageReconstructionAlgorithm)

Release a lock on the algorithm `algo`.
"""
unlock(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement unlock")
"""
    lock(fn, algo::AbstractImageReconstructionAlgorithm)

Acquire the `lock` on `algo`, execute `fn` and release the `lock` afterwards.
"""
function lock(fn, algo::AbstractImageReconstructionAlgorithm)
  lock(algo)
  try
    fn()
  finally
    unlock(algo)
  end
end

export reconstruct
"""
    reconstruct(algo::T, u) where {T<:AbstractImageReconstructionAlgorithm}

Reconstruct an image from input `u` using algorithm `algo`. The `àlgo` will be `lock`ed until the result is available or an error occurs.
"""
function reconstruct(algo::T, u) where {T<:AbstractImageReconstructionAlgorithm}
  lock(algo) do
    put!(algo, u)
    return take!(algo)
  end
end

export process
# process(algoT::Type{T}, ...) as pure helper functions
# Overwrite process(algo, ...) to mutate struct based on helper function result
"""
    process(algo::Union{A, Type{A}}, param::AbstractImageReconstructionParameters, inputs...) where A <: AbstractImageReconstructionAlgorithm

Process `inputs` with algorithm `algo` and parameters `param`. Returns the result of the processing step.
If not implemented for an instance of `algo`, the default implementation is called with the type of `algo`.
"""
function process end
process(algo::AbstractImageReconstructionAlgorithm, param::AbstractImageReconstructionParameters, inputs...) = process(typeof(algo), param, inputs...)
"""
    process(algo::Union{A, Type{A}}, param::AbstractUtilityReconstructionParameters{P}, inputs...) where {A <: AbstractImageReconstructionAlgorithm, P <: AbstractImageReconstructionParameters}

Process `inputs` with algorithm `algo` and return the result as if the arguments were given to `P`. Examples of utility `process` are processes which offer caching or remote execution. 
"""
process(::A, param::AbstractUtilityReconstructionParameters{P}, inputs...) where {A, P} = error("$(typeof(param)) must implement `process` for $A and given inputs")
"""
Enable multiple process steps by supplying a Vector of parameters
"""
function process(algo::AbstractImageReconstructionAlgorithm, params::Vector{<:AbstractImageReconstructionParameters}, inputs...)
  val = process(algo, first(params), inputs...)
  for param ∈ Iterators.drop(params, 1)
    val = process(algo, val, param)
  end
  return val
end

export parameter
"""
    parameter(algo::AbstractImageReconstructionAlgorithm)

Return the parameters of the algorithm `algo`.
"""
parameter(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement `parameter`")
"""
    parameter(param::AbstractUtilityReconstructionParameters)
  
Return the wrapped parameter. Can themselves be utility parameters again
"""
parameter(param::AbstractUtilityReconstructionParameters) = error("$(typeof(param)) must implement `parameter`")


# Macro constructor
export @reconstruction
"""
    ReconstructionSpec

Internal specification for algorithm definition. Can be created manually or via macro.
"""
struct ReconstructionSpec
  name::Symbol
  type_params::Vector
  abstract_base::Symbol
  parameter_type::Union{Symbol, Nothing}
  parameter_name::Union{Symbol, Nothing}
  state_fields::Vector{Tuple{Symbol, Symbol, Any}}  # (name, type, default)
end

function define_algorithm(spec::ReconstructionSpec)
  # Build struct fields: parameter + state + infrastructure
  struct_fields = [
    :($(spec.parameter_name)::$(spec.parameter_type)),
    [:($(field[1])::$(field[2])) for field in spec.state_fields]...,
    :(_channel::Channel{Any}),
  ]
  
  # Build struct definition
  algo_name_expr = if isempty(spec.type_params)
    :($(spec.name))
  else
    :($(spec.name){$(spec.type_params...)})
  end
  
  struct_def = :(
    mutable struct $(algo_name_expr) <: $(spec.abstract_base)
      $(struct_fields...)
    end
  )
  
  # Build constructor
  field_defaults = [field[3] for field in spec.state_fields]
  
  ctor_init = :(
    algo = $(spec.name)(
      parameter,
      $(field_defaults...),
      Channel{Any}(Inf))
  )
    
  ctor = :(
    function $(spec.name)(parameter)
      $ctor_init
      return algo
    end
  )
  
  # Build interface methods
  interface_methods = [
    _build_put_method(spec),
    _build_take_method(spec),
    _build_isready_method(spec),
    _build_wait_method(spec),
    _build_lock_method(spec),
    _build_unlock_method(spec),
    _build_parameter_accessor(spec),
  ]
  
  # Combine all definitions
  return quote
    $struct_def
    $ctor
    $(interface_methods...)
  end
end

function _build_put_method(spec::ReconstructionSpec)
  algo_type = spec.name
  param_name = spec.parameter_name

  
  put_body = quote
    lock(algo) do
      # Execute the algorithm
      result = process(algo, algo.$param_name, inputs...)      
      put!(algo._channel, result)
    end
  end
  
  return :(
    function Base.put!(algo::$(algo_type), inputs...)
      $put_body
    end
  )
end


function _build_take_method(spec::ReconstructionSpec)
  algo_type = spec.name
  
  take_body = :(return Base.take!(algo._channel))
  
  return :(
    function Base.take!(algo::$(algo_type))
      $take_body
    end
  )
end

function _build_isready_method(spec::ReconstructionSpec)
  algo_type = spec.name
  return :(
    Base.isready(algo::$(algo_type)) = isready(algo._channel)
  )
end

function _build_wait_method(spec::ReconstructionSpec)
  algo_type = spec.name
  return :(
    Base.wait(algo::$(algo_type)) = wait(algo._channel)
  )
end

function _build_lock_method(spec::ReconstructionSpec)
  algo_type = spec.name
  return :(
    Base.lock(algo::$(algo_type)) = lock(algo._channel)
  )
end

function _build_unlock_method(spec::ReconstructionSpec)
  algo_type = spec.name
  return :(
    Base.unlock(algo::$(algo_type)) = unlock(algo._channel)
  )
end

function _build_parameter_accessor(spec::ReconstructionSpec)
  algo_type = spec.name
  param_name = spec.parameter_name
  return :(
    AbstractImageReconstruction.parameter(algo::$(algo_type)) = algo.$param_name
  )
end

function parse_algorithm_spec(head::Expr, body::Expr)
  # Check if there's an explicit base type
  if Meta.isexpr(head, :<:)
    algo_head = head.args[1]  # AlgoName{D <: ...}
    abstract_base = head.args[2]
  else
    # No base type specified, use default
    algo_head = head
    abstract_base = :(AbstractImageReconstructionAlgorithm)
  end
  
  # Extract algorithm name and type parameters
  if Meta.isexpr(algo_head, :curly)
    name = Symbol(algo_head.args[1])
    type_params = algo_head.args[2:end]
  else
    name = Symbol(algo_head)
    type_params = []
  end
  
  # Parse body
  parameter_type = nothing
  parameter_name = nothing
  state_fields = Tuple{Symbol, Symbol, Any}[]
  
  for item in body.args
    if Meta.isexpr(item, :macrocall)
      macro_name = item.args[1]
      
      if macro_name == Symbol("@parameter")
        # @parameter parameter::D
        param_spec = item.args[3]
        parameter_name = Symbol(param_spec.args[1])
        parameter_type = param_spec.args[2]
      else
        @warn "Unexpected macro call $macro_name"
      end
    
    elseif Meta.isexpr(item, :(::))
      # Field with type: state::Type or state::Type = default
      field_name = Symbol(item.args[1])
      
      if Meta.isexpr(item.args[2], :(=))
        # state::Type = default
        field_type = item.args[2].args[1]
        field_default = item.args[2].args[2]
      else
        # state::Type
        field_type = item.args[2]
        field_default = nothing
      end
      
      push!(state_fields, (field_name, field_type, field_default))
    end
  end
  
  if parameter_type === nothing || parameter_name === nothing
    error("@parameter required in @algorithm")
  end
  
  return ReconstructionSpec(
    name,
    type_params,
    abstract_base,
    parameter_type,
    parameter_name,
    state_fields)
end

"""
    @reconstruction struct AlgoName{P <: Params} <: AbstractBase
      @parameter parameter::P
      field::Type = default
      # ...
      @validate hook!(algo, inputs...)
      @finalize hook!(algo, result)
    end

Define a stateful algorithm with boilerplate automatically generated.
Supports both `struct` and `mutable struct`.
"""
macro reconstruction(expr)
  # Check if this is a struct definition
  if !Meta.isexpr(expr, :struct)
    error("@reconstruction must be applied to a struct definition (struct or mutable struct)")
  end
  
  is_mutable = expr.args[1]  # true for mutable struct, false for struct
  algo_head = expr.args[2]    # AlgoName{P <: Params} <: AbstractBase
  body_block = expr.args[3]   # The struct body as Expr(:block, ...)
  
  # Parse the spec using the existing parser
  spec = parse_algorithm_spec(algo_head, body_block)

  # Generate and return the algorithm definition
  return esc(define_algorithm(spec))
end