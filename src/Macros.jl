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
    if Meta.isexpr(ex, :macrocall) && ex.args[1] == Symbol("@atomic")
      isatomic = true
      ex = ex.args[3]
    end
    
    if Meta.isexpr(ex, :const)
        isconst = true
        ex = ex.args[1]
    end
    if Meta.isexpr(ex, :(=))
        default = ex.args[2]
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

function _full_type_expr(name::Symbol, type_params)
  isempty(type_params) ? :($name) : :($name{$(type_params...)})
end

_filter_hash_fields(field_syms::Vector{Symbol}) = filter(s -> !startswith(String(s), "_"), field_syms)

function _hash_fields(spec::ReconstructionSpec)
  syms = Symbol[spec.parameter.name]
  push!(syms, (f.name for f in spec.state_fields)...)
  return _filter_hash_fields(syms)
end

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

function _hash_fields(spec::ParameterSpec)
  syms = Symbol[f.name for f in spec.fields]
  return _filter_hash_fields(syms)
end

function _hash_fields(spec::ChainSpec)
  syms = Symbol[f.name for f in spec.fields]
  return _filter_hash_fields(syms)
end


function _build_hash_method(spec)
  fields = _hash_fields(spec)

  # If there are no fields left after filtering, we still hash the type name.
  field_steps = Any[]
  for f in fields
    push!(field_steps,
      :(h = hash(x.$f, h))
    )
  end

  return :(
    function Base.hash(x::$(spec.name), h::UInt64)
      h = hash(typeof(x), h)
      $(field_steps...)
      return h
    end
  )
end

function define_algorithm(spec::ReconstructionSpec; generate_constructor::Bool=true, generate_hash::Bool=false)
  struct_fields = [
    expr(spec.parameter),
    [expr(field) for field in spec.state_fields]...,
    Expr(:const, :(_channel::Channel{Any})),
  ]
  
  # Build struct definition
  algo_name_expr = _full_type_expr(spec.name, spec.type_params)
  
  struct_def = :(
    mutable struct $(algo_name_expr) <: $(spec.abstract_base)
      $(struct_fields...)
    end
  )

  struct_def = :($Base.@__doc__ $struct_def)
  
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

  hash_method = generate_hash ? _build_hash_method(spec) : :()
  
  return quote
    $struct_def
    $ctor
    $(interface_methods...)
    $hash_method
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

function parse_algorithm_spec(head::Union{Symbol, Expr}, body::Expr; generate_constructor::Bool = true, kwargs...)
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
      elseif macro_name == Symbol("@atomic")
        # Try to parse as a field definition
        result = FieldSpec(item)
        if !isnothing(result)
          push!(state_fields, result)
        end
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
      error("Field '$(field.name)' has no default value. " *
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
    @reconstruction [constructor={true, false}] [hash={true, false}] struct AlgoName{P <: Params} <: AbstractBase
      @parameter parameter::P
      field::Type = default
      field = default
      @init hook!(algo)
    end

Define a reconstruction algorithm struct with all boilerplate automatically generated.

The `@reconstruction` macro generates:
- A mutable struct with algorithm infrastructure fields (channel for FIFO buffering)
- A simple constructor that accepts only the parameter (if `constructor=true`)
- Implementation of all interface methods: `put!`, `take!`, `isready`, `wait`, `lock`, `unlock`
- A `hash` method (if `hash=true`)

# Configuration Options

- `constructor=true` (default) - Auto-generate a simple constructor
- `constructor=false` - No constructor generated (write custom constructor)
- `hash=true` (default) - Generate a `hash` method
- `hash=false` - Do not generate a `hash` method

# Syntax

## Required
- `@parameter parameter::ParameterType` - The main parameter field (immutable)

## Optional State Fields
- `field::Type = default` - Typed field with default value
- `field = default` - Untyped field with default value

## Optional Hooks
- `@init hook!(algo)` - Custom initialization hook after construction

# Examples

```julia
# Simple algorithm with default constructor
@reconstruction mutable struct MyAlgorithm <: AbstractImageReconstructionAlgorithm
  @parameter params::MyParameters
  state::Vector{Float64} = Float64[]
  counter::Int = 0
end

# Algorithm with custom initialization
@reconstruction mutable struct AlgorithmWithInit <: CustomBase
  @parameter params::MyParameters
  cache::Dict{String, Any} = Dict()

  @init function setup!(algo::AlgorithmWithInit)
    algo.cache["initialized"] = true
  end
end

# Algorithm without auto-generated constructor
@reconstruction constructor=false mutable struct CustomConstructorAlgorithm
  @parameter params::MyParameters
  state::Vector{Float64}
end
function CustomConstructorAlgorithm(params)
  # Custom initialization logic
  state = ...
  algo = CustomConstructorAlgorithm(params, state, @reconstruction_internals CustomConstructorAlgorithm)
  # ... more setup ...
  return algo
end
```
"""
macro reconstruction(ex...)
  if isempty(ex)
    error("@reconstruction requires a struct definition")
  end
  
  generate_constructor = true
  generate_hash = true
  struct_expr = ex[end]
  
  for i in 1:(length(ex) - 1)
    if ex[i] isa Expr && ex[i].head == :(=)
      key = ex[i].args[1]
      val = ex[i].args[2]
      
      if key == :constructor && val isa Bool
        generate_constructor = val
      elseif key == :hash && val isa Bool
        generate_hash = val
      else
        error(
          "Configuration should be of form:\n" *
          "* `constructor=true` or `constructor=false`\n" *
          "* `hash=true` or `hash=false`\n" *
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
  
  spec = parse_algorithm_spec(algo_head, body_block; generate_constructor, generate_hash)
  
  return esc(define_algorithm(spec; generate_constructor, generate_hash))
end

export @reconstruction_internals
macro reconstruction_internals(type_name)
  return :((Channel{Any}(Inf),)...)
end

export @parameter
function _build_struct_definition(spec::Union{ParameterSpec, ChainSpec})
    # Build full type expr: Name or Name{T...}
  full_type_expr = _full_type_expr(spec.name, spec.type_params)

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
  validation_method = :()
  if !isnothing(spec.validate_body)
    validate_block = spec.validate_body
    # Pre-bind fields: field = params.field
    prelude = [:( $(fields.name) = params.$(fields.name) ) for fields in spec.fields]

    validation_method = :(
      function AbstractImageReconstruction.validate!(params::$(spec.name))
        $(prelude...)
        $(validate_block.args...)
        return params
      end
    )
  end
  return validation_method
end

function _build_kwarg_constructor(spec::Union{ParameterSpec, ChainSpec}; generate_constructor::Bool=true)
  if !generate_constructor
    return :()
  end

  kwargs = [kw(field) for field in spec.fields]

  # Empty fields result in stackoverflow
  if isempty(kwargs)
    return :()
  end

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

function define_parameter(spec::ParameterSpec; generate_constructor::Bool=true, generate_hash::Bool=false)
  if !generate_constructor
    fields_with_defaults = [f.name for f in spec.fields if f.default !== notspecified]
    if !isempty(fields_with_defaults)
      @warn "Fields with default values ($fields_with_defaults) will not be available " *
            "via keyword arguments when constructor=false. Handle defaults in your custom constructor."
    end
  end

  struct_def = _build_struct_definition(spec)
  validation_method = _build_validation_method(spec)
  kw_constructor = _build_kwarg_constructor(spec; generate_constructor)
  hash_method = generate_hash ? _build_hash_method(spec) : :()
  
  return quote
    $struct_def
    $kw_constructor
    $validation_method
    $hash_method
  end
end

"""
    @parameter [constructor={true,false}] [hash={true,false}] (mutable) struct Name{...} <: AbstractImageReconstructionParameters
      field1::Type1 [= default1]
      field2::Type2 [= default2]
      ...
      @validate begin
        @assert field1 >= ... "message"
        ...
      end
    end

Define a parameter struct for image reconstruction algorithms.

The `@parameter` macro generates:
- A struct with the specified fields
- A keyword constructor for easy instantiation: `Name(field1=val1, field2=val2)` with (optional) validation
- A `validate!` function for parameter validation (if `@validate` is used)

# Configuration Options

- `constructor=true` (default) - Auto-generate a keyword constructor
- `constructor=false` - No keyword constructor generated (write custom constructor)
- **Note**: When using `constructor=false` with fields that have default values (e.g., `field::Int = 10`), those defaults are NOT available via keyword arguments. Handle defaults in your custom constructor.
- **Note**: When using `constructor=false` with `@validate`, you must manually call `validate!` in your custom constructor.
- `hash=true` (default) - Generate a `hash` method for the parameter type
- `hash=false` - Do not generate a `hash` method

# Syntax

## Required
- `field::Type` - Required field with type annotation
- `field::Type = default` - Optional field with default value

## Optional Validation
- `@validate` - Block of validation assertions

# Examples

```julia
# Simple parameter with validation
@parameter struct MyParameters <: AbstractImageReconstructionParameters
  iterations::Int = 10
  tolerance::Float64 = 1e-6
  @validate begin
    @assert iterations > 0 "iterations must be positive"
    @assert tolerance > 0 "tolerance must be positive"
  end
end

# Parameter without auto-generated constructor
@parameter constructor=false struct CustomParams
  field::Int
  @validate begin
    @assert field > 0 "field must be positive"
  end
end

function CustomParams(;field::Int)
  params = CustomParams(field)
  validate!(params)  # Must call manually when constructor=false
  return params
end
```
"""
macro parameter(ex...)
  if isempty(ex)
    error("@parameter requires a struct definition")
  end
  generate_constructor = true
  generate_hash = true
  struct_expr = ex[end]

  for i in 1:(length(ex) - 1)
    if ex[i] isa Expr && ex[i].head == :(=)
      key = ex[i].args[1]
      val = ex[i].args[2]
      if key == :constructor && val isa Bool
        generate_constructor = val
      elseif key == :hash && val isa Bool
        generate_hash = val
      else
        error(
          "Configuration should be of form:\n" *
          "* `constructor=true` or `constructor=false`\n" *
          "* `hash=true` or `hash=false`\n" *
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
    error("@parameter must be applied to a struct definition")
  end

  ismutable  = struct_expr.args[1]
  head_expr  = struct_expr.args[2]
  body_block = struct_expr.args[3]

  spec = parse_parameter_spec(head_expr, body_block, ismutable)
  return esc(define_parameter(spec; generate_constructor, generate_hash))
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

function define_chain(spec::ChainSpec; generate_constructor::Bool=true, generate_hash::Bool=false)
  if !generate_constructor
    fields_with_defaults = [f.name for f in spec.fields if f.default !== notspecified]
    if !isempty(fields_with_defaults)
      @warn "Fields with default values ($fields_with_defaults) will not be available " *
            "via keyword arguments when constructor=false. Handle defaults in your custom constructor."
    end
  end

  struct_def = _build_struct_definition(spec)
  validation_method = _build_validation_method(spec)
  kw_constructor = _build_kwarg_constructor(spec; generate_constructor)
  hash_method = generate_hash ? _build_hash_method(spec) : :()

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
    $hash_method
  end
end

export @chain

"""
    @chain [constructor={true,false}] [hash={true,false}] struct Name{...} <: AbstractImageReconstructionParameters
      step1::P1 [= default1]
      step2::P2 [= default2]
      ...
      @validate @assert condition "message"
    end

Define a composite parameter type that chains multiple processing steps.

The `@chain` macro generates:
- A struct with the specified field parameters
- A keyword constructor for easy instantiation
- A `validate!` function (if `@validate` is used)
- Call methods that chain the step parameters sequentially

When called, the composite parameter executes each step in order:
```julia
result = params.step1(algo, inputs...)
result = params.step2(algo, result...)
...
return result
```

# Configuration Options

- `constructor=true` (default) - Auto-generate a keyword constructor
- `constructor=false` - No keyword constructor generated (write custom constructor)
- **Note**: When using `constructor=false` with fields that have default values (e.g., `step::Params = Params()`), those defaults are NOT available via keyword arguments. Handle defaults in your custom constructor.
- **Note**: When using `constructor=false` with `@validate`, you must manually call `validate!` in your custom constructor.
- `hash=true` (default) - Generate a `hash` method for the parameter type
- `hash=false` - Do not generate a `hash` method

# Syntax

## Required
- `step1::P1` - First processing step parameter type
- `step2::P2` - Second processing step parameter type
- Each field should be a parameter type that implements `(param, algo, inputs...)`

## Optional
- `@validate` - Block of validation assertions

# Examples

```julia
# Chain preprocessing and reconstruction steps
@chain struct CompositeParameters <: AbstractImageReconstructionParameters
  pre::RadonPreprocessingParameters
  reco::RadonBackprojectionParameters
end

# Chain without auto-generated constructor
@chain constructor=false struct CustomChain <: AbstractImageReconstructionParameters
  step1::StepParams
  @validate begin
    @assert step1.value >= 0 "step value must be non-negative"
  end
end

function CustomChain(;step1::StepParams)
  chain = CustomChain(step1)
  validate!(chain)  # Must call manually when constructor=false
  return chain
end
```
"""
macro chain(ex...)
  if isempty(ex)
    error("@chain requires a struct definition")
  end
  generate_constructor = true
  generate_hash = true
  struct_expr = ex[end]

  for i in 1:(length(ex) - 1)
    if ex[i] isa Expr && ex[i].head == :(=)
      key = ex[i].args[1]
      val = ex[i].args[2]
      if key == :constructor && val isa Bool
        generate_constructor = val
      elseif key == :hash && val isa Bool
        generate_hash = val
      else
        error(
          "Configuration should be of form:\n" *
          "* `constructor=true` or `constructor=false`\n" *
          "* `hash=true` or `hash=false`\n" *
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
    error("@chain must be applied to a struct definition")
  end

  ismutable  = struct_expr.args[1]
  head_expr  = struct_expr.args[2]
  body_block = struct_expr.args[3]

  spec = parse_chain_spec(head_expr, body_block, ismutable)
  return esc(define_chain(spec; generate_constructor, generate_hash))
end