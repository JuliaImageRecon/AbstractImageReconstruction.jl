struct NotSpecified end
const notspecified = NotSpecified()

# Inspired by StructUtils.jl
struct FieldSpec
  isconst::Bool
  isatomic::Bool
  name::Symbol
  type::Any # something or notspecified
  default::Any # something or notspecified
end

function FieldSpec(ex; name = notspecified, type = notspecified, isconst = false, isatomic = false, default = notspecified)
    if Meta.isexpr(ex, :const)
        isconst = true
        ex = ex.args[1]
    end
    if Meta.isexpr(ex, :(=))
        default = ex.args[2]
        ex = ex.args[1]
    end
    if Meta.isexpr(ex, :atomic)
        isatomic = true
        ex = ex.args[1]
    end
    if ex isa Symbol
        name = ex
    elseif Meta.isexpr(ex, :(::))
        name, type = ex.args
    else
        return nothing
    end
    name = Meta.isexpr(name, :escape) ? name.args[1] : name
    return FieldSpec(isconst, isatomic, name, type, default)
end


function expr(spec::FieldSpec)
  field = spec.type === notspecified ? spec.name : :($(spec.name)::$(spec.type))
  if spec.isconst
    return Expr(:const, field)
  elseif spec.isatomic
    return :(@atomic($field))
  else
    return field
  end
end

function kw(spec::FieldSpec)
  return spec.default === notspecified ? spec.name : Expr(:kw, spec.name, spec.default)
end

# Macro constructor
export @reconstruction
"""
    ReconstructionSpec

Internal specification for algorithm definition. Can be created manually or via macro.
"""
struct ReconstructionSpec
  name::Symbol
  type_params::Vector
  abstract_base::Union{Symbol, Expr}
  parameter::FieldSpec
  state_fields::Vector{FieldSpec}
  init_hook::Union{Expr, Nothing}
end

function define_algorithm(spec::ReconstructionSpec, generate_constructor::Bool=true)
  struct_fields = [
    expr(spec.parameter),
    [expr(field) for field in spec.state_fields]...,
    Expr(:const, :(_channel::Channel{Any})),
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
  
  ctor = if generate_constructor
    field_defaults = [field.default for field in spec.state_fields]
    
    ctor_init = :(
      algo = $(spec.name)(
        parameter,
        $(field_defaults...),
        Channel{Any}(Inf))
    )
    
    init_call = if spec.init_hook !== nothing
      :($(spec.init_hook)(algo))
    else
      :()
    end

    :(
      function $(spec.name)(parameter)
        $ctor_init
        $init_call
        return algo
      end
    )
  else
    :()
  end
  
  interface_methods = [
    _build_put_method(spec),
    _build_take_method(spec),
    _build_isready_method(spec),
    _build_wait_method(spec),
    _build_lock_method(spec),
    _build_unlock_method(spec),
    _build_parameter_accessor(spec),
  ]
  
  return quote
    $struct_def
    $ctor
    $(interface_methods...)
  end
end

function _build_put_method(spec::ReconstructionSpec)
  algo_type = spec.name
  param_name = spec.parameter.name

  
  put_body = quote
    lock(algo) do
      # Execute the algorithm
      result = algo.$param_name(algo, inputs...)      
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
  param_name = spec.parameter.name
  return :(
    AbstractImageReconstruction.parameter(algo::$(algo_type)) = algo.$param_name
  )
end

function parse_algorithm_spec(head::Union{Symbol, Expr}, body::Expr, generate_constructor::Bool)
  # Check if there's an explicit base type
  if Meta.isexpr(head, :<:)
    algo_head = head.args[1]
    abstract_base = head.args[2]
  else
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
  parameter = nothing
  state_fields = FieldSpec[]
  init_hook = nothing

  for item in body.args
    item isa LineNumberNode && continue

    if Meta.isexpr(item, :macrocall)
      macro_name = item.args[1]

      if macro_name == Symbol("@parameter")
        param_spec = item.args[3]
        parameter = FieldSpec(param_spec; isconst = true)
      elseif macro_name == Symbol("@init")
        init_hook = item.args[3]
      else
        @warn "Unexpected macro call $macro_name"
      end
    elseif item isa Symbol || item isa Expr
      # Try to parse as a field definition
      result = FieldSpec(item)
      if !isnothing(result)
        push!(state_fields, result)
      end
    end
  end

  if isnothing(parameter)
    error("@parameter required in @algorithm")
  end

  for field in state_fields
    if field.default === notspecified && generate_constructor
      error("Field '$(field[1])' has no default value. " *
            "Provide a default and use @init for custom initialization or provide a custom constructor.")
    end
  end
  
  return ReconstructionSpec(
    name,
    type_params,
    abstract_base,
    parameter,
    state_fields, 
    init_hook)
end

"""
    @reconstruction [constructor={true, false}] struct AlgoName{P <: Params} <: AbstractBase
      @parameter parameter::P
      field::Type = default
      field = default
      @init hook!(algo)
    end

Define a stateful algorithm struct with boilerplate automatically generated.

# Features
- Automatically generates a mutable struct with infrastructure fields
- Supports custom abstract base types (defaults to `AbstractImageReconstructionAlgorithm`)
- Implements interface methods: `Base.put!`, `Base.take!`, `Base.isready`, `Base.wait`, `Base.lock`, `Base.unlock`
- Optionally generates a simple constructor or allows custom constructor implementation
- Requires a `@parameter` field

# Configuration Options

- `constructor={true, false}` (default: `true`) — Whether to auto-generate a simple constructor that accepts only the parameter.

  Set to `false` to write a custom constructor (use `@reconstruction_internals` helper).

# Syntax

## Required
- `@parameter parameter::ParameterType` — Required parameter field

## Optional State Fields
- `field::Type = default` — Typed field with default value
- `field = default` — Untyped field (type inferred from default) with default value

## Optional Hooks
## Optional Hooks
- `@init hook!(algo)` — Custom initialization hook called after struct construction (receives the new algorithm instance).
  Only available with default constructor generation.

# Supported Type Syntax

# Examples

```julia
@reconstruction mutable struct MyAlgorithm <: CustomBase
  @parameter params::MyParams
  state::Vector{Float64} = Float64[]
  counter::Int = 0
  cache::Dict{String, Any} = Dict()
  @init initialize_algo!(algo)
end

function initialize_algo!(algo::MyAlgorithm)
  ### Custom setup logic
  algo.cache["initialized"] = true
end
```
The macro supports both struct and mutable struct definitions.
"""
macro reconstruction(ex...)
  if isempty(ex)
    error("@reconstruction requires a struct definition")
  end
  
  generate_constructor = true
  struct_expr = ex[end]
  
  for i in 1:(length(ex) - 1)
    if ex[i] isa Expr && ex[i].head == :(=)
      key = ex[i].args[1]
      val = ex[i].args[2]
      
      if key == :constructor && val isa Bool
        generate_constructor = val
      else
        error(
          "Configuration should be of form:\n" *
          "* `constructor=true`\n" *
          "* `constructor=false`\n" *
          "got `", ex[i], "`",
        )
      end
    else
      error(
        "Configuration should be of form: `key=value`\n" *
        "got `", ex[i], "`",
      )
    end
  end
  
  if !Meta.isexpr(struct_expr, :struct)
    error("@reconstruction must be applied to a struct definition")
  end
  
  algo_head = struct_expr.args[2]
  body_block = struct_expr.args[3]
  
  spec = parse_algorithm_spec(algo_head, body_block, generate_constructor)
  
  return esc(define_algorithm(spec, generate_constructor))
end


export @reconstruction_internals
macro reconstruction_internals(type_name)
  return :((Channel{Any}(Inf),)...)
end



export @parameter

struct ParameterSpec
  name::Symbol
  type_params::Vector
  abstract_base::Union{Symbol, Expr}
  ismutable::Bool
  fields::Vector{FieldSpec}
  validate_body::Union{Expr, Nothing}
end

struct ChainSpec
  name::Symbol
  type_params::Vector{Any}
  abstract_base::Union{Symbol, Expr}
  ismutable::Bool
  fields::Vector{FieldSpec}
  validate_body::Union{Expr, Nothing}
end

function _build_struct_definition(spec::Union{ParameterSpec, ChainSpec})
    # Build full type expr: Name or Name{T...}
  full_type_expr = isempty(spec.type_params) ?
                   :($(spec.name)) :
                   :($(spec.name){$(spec.type_params...)})

  # Struct head: Name{...} <: AbstractImageReconstructionParameters (or custom base)
  struct_head = :( $full_type_expr <: $(spec.abstract_base) )

  # Struct definition
  struct_def = if spec.ismutable 
    :(
      mutable struct $struct_head
        $(expr.(spec.fields)...)
      end
    )
  else
    :(
      struct $struct_head
        $(expr.(spec.fields)...)
      end
    )
  end

  # Make docstrings work (magically?), based on Base.@kwdef
  return :($Base.@__doc__ $struct_def)
end

function _build_validation_method(spec::Union{ParameterSpec, ChainSpec})
  # Build full type expr: Name or Name{T...}
  full_type_expr = isempty(spec.type_params) ?
                   :($(spec.name)) :
                   :($(spec.name){$(spec.type_params...)})

  
  validation_method = :()
  if !isnothing(spec.validate_body)
    validate_block = spec.validate_body
    # Pre-bind fields: field = params.field
    prelude = [:( $(fields.name) = params.$(fields.name) ) for fields in spec.fields]

    validation_method = :(
      function AbstractImageReconstruction.validate!(params::$(full_type_expr))
        $(prelude...)
        $(validate_block.args...)
        return params
      end
    )
  end
  return validation_method
end

function _build_kwarg_constructor(spec::Union{ParameterSpec, ChainSpec})  
  kwargs = [kw(field) for field in spec.fields]
  kw_constructor = :(
    function $(spec.name)(;$(kwargs...))
      _param = $(spec.name)($((f.name for f in spec.fields)...))
      validate!(_param)
      return _param
    end
  )  
  return kw_constructor
end

function parse_parameter_spec(head::Union{Symbol, Expr},
                              body::Expr,
                              ismutable::Bool)
  # Head: Name{...} or Name{...} <: Base
  if Meta.isexpr(head, :<:)
    type_head    = head.args[1]
    abstract_base = head.args[2]
  else
    type_head    = head
    abstract_base = :(AbstractImageReconstructionParameters)
  end

  # Name + type params
  if Meta.isexpr(type_head, :curly)
    name        = Symbol(type_head.args[1])
    type_params = type_head.args[2:end]
  else
    name        = Symbol(type_head)
    type_params = Any[]
  end

  # Split body into fields + optional @validate
  fields   = FieldSpec[]
  validate_body = nothing

  for item in body.args
    item isa LineNumberNode && continue
    if Meta.isexpr(item, :macrocall) 
      macro_name = item.args[1]
      if macro_name == Symbol("@validate")
        validate_body = item.args[3]
      else
        @warn "Unexpected macro call $macro_name"
      end
    elseif item isa Symbol || item isa Expr
      result = FieldSpec(item)
      if !isnothing(result)
        push!(fields, result)
      end
    end
  end

  return ParameterSpec(
    name,
    type_params,
    abstract_base,
    ismutable,
    fields,
    validate_body,
  )
end

function define_parameter(spec::ParameterSpec)
  struct_def = _build_struct_definition(spec)

  validation_method = _build_validation_method(spec)

  kw_constructor = _build_kwarg_constructor(spec)
  
  return quote
    $struct_def
    $kw_constructor
    $validation_method
  end
end

macro parameter(struct_expr)
  if !Meta.isexpr(struct_expr, :struct)
    error("@parameter must be applied to a struct definition")
  end
  ismutable  = struct_expr.args[1]
  head_expr  = struct_expr.args[2]
  body_block = struct_expr.args[3]

  spec = parse_parameter_spec(head_expr, body_block, ismutable)
  return esc(define_parameter(spec))
end

function parse_chain_spec(head::Union{Symbol, Expr},
                          body::Expr,
                          ismutable::Bool)
  # Head: Name{...} or Name{...} <: Base
  if Meta.isexpr(head, :<:)
    type_head    = head.args[1]
    abstract_base = head.args[2]
  else
    type_head    = head
    abstract_base = :(AbstractImageReconstructionParameters)
  end

  # Name + type params
  if Meta.isexpr(type_head, :curly)
    name        = Symbol(type_head.args[1])
    type_params = type_head.args[2:end]
  else
    name        = Symbol(type_head)
    type_params = Any[]
  end

  fields   = FieldSpec[]
  validate_body = nothing

  for item in body.args
    item isa LineNumberNode && continue
    if Meta.isexpr(item, :macrocall) 
      macro_name = item.args[1]
      if macro_name == Symbol("@validate")
        validate_body = item.args[3]
      else
        @warn "Unexpected macro call $macro_name"
      end
    elseif item isa Symbol || item isa Expr
      result = FieldSpec(item)
      if !isnothing(result)
        push!(fields, result)
      end
    end
  end

  return ChainSpec(
    name,
    type_params,
    abstract_base,
    ismutable,
    fields,
    validate_body
  )
end

function define_chain(spec::ChainSpec)
  struct_def = _build_struct_definition(spec)

  validation_method = _build_validation_method(spec)

  kw_constructor = _build_kwarg_constructor(spec)

  chain_method = :(
    function (param::$(spec.name))(algo::AbstractImageReconstructionAlgorithm, inputs...)
      result = param.$(first(spec.fields).name)(algo, inputs...)
      $((:(result = param.$(field.name)(algo, result)) for field in spec.fields[2:end])...)
      return result
    end
  )

  chain_method_pure = :(
    function (param::$(spec.name))(algo::Type{<:AbstractImageReconstructionAlgorithm}, inputs...)
      result = param.$(first(spec.fields).name)(algo, inputs...)
      $((:(result = param.$(field.name)(algo, result)) for field in spec.fields[2:end])...)
      return result
    end
  )

  
  return quote
    $struct_def
    $kw_constructor
    $validation_method
    $chain_method
    $chain_method_pure
  end

end

export @chain
"""
    @chain struct Name{...} <: AbstractImageReconstructionParameters
        step1::P1 [= default1]
        step2::P2 [= default2]
        ...
    end

Define a composite parameter type whose call chains its fields as processing steps.

`@chain` expands the given struct definition into:

  * A plain `struct` (or `mutable struct`) with the same fields.
  * A keyword constructor

        Name(; step1, step2, ...)

    where fields with `= default` become optional keywords, and fields without
    defaults are required.
  * An optional validation step, similar to @parameter
  * Two call method

        (params::Name)(algo::AbstractImageReconstructionAlgorithm, inputs...)
        (params::Name)(algo::Type{<:AbstractImageReconstructionAlgorithm}, inputs...)

    that execute:

        result = params.step1(algo, inputs...)
        result = params.step2(algo, result...)
        ...
        return result

Each field is assumed to be a parameter-like object that is callable with
`(algo, ...)`. The composite type is a subtype of `AbstractImageReconstructionParameters` by default; a different
abstract base can be specified explicitly
"""
macro chain(struct_expr)
  if !Meta.isexpr(struct_expr, :struct)
    error("@chain must be applied to a struct definition")
  end
  ismutable  = struct_expr.args[1]
  head_expr  = struct_expr.args[2]
  body_block = struct_expr.args[3]

  spec = parse_chain_spec(head_expr, body_block, ismutable)
  return esc(define_chain(spec))
end