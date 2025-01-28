export AbstractRecoPlan, RecoPlan
abstract type AbstractRecoPlan{T<:Union{AbstractImageReconstructionParameters, AbstractImageReconstructionAlgorithm}} end
"""
    RecoPlan{T <: Union{AbstractImageReconstructionParameters, AbstractImageReconstructionAlgorithm}}

Configuration template for an image reconstruction algorithm or paremeters of type `T`. 
A `RecoPlan{T}` has the same properties with type checking as `T` with the exception that properties can be missing and nested algorithms and parameters can again be `RecoPlan`s.

Plans can be nested and form a tree. A parent plan can be accessed with `parent` and set with `parent!`. Algorithms and parameters can be converted to a plan with `toPlan`.

Plans feature serialization with `toTOML`, `toPlan` and `loadPlan` and the ability to attach callbacks to property changes with `Òbservables` and `on`.
"""
mutable struct RecoPlan{T} <: AbstractRecoPlan{T}
  parent::Union{Nothing, AbstractRecoPlan}
  values::Dict{Symbol, Observable{Any}}
  """
      RecoPlan(::Type{T}; kwargs...) where {T<:AbstractImageReconstructionParameters}

  Construct a RecoPlan of type `T` and set the properties with the given keyword arguments.
  """
  function RecoPlan(::Type{T}; kwargs...) where {T<:AbstractImageReconstructionParameters}
    dict = Dict{Symbol, Observable{Any}}()
    for field in filter(f -> !startswith(string(f), "_"), fieldnames(T))
      dict[field] =  Observable{Any}(missing)
    end
    plan = new{getfield(parentmodule(T), nameof(T))}(nothing, dict)
    setAll!(plan; kwargs...)
    return plan
  end
  """
      RecoPlan(::Type{T}; parameter = missing) where {T<:AbstractImageReconstructionAlgorithm}
  
  Construct a RecoPlan of type `T` and set the main parameter of the algorithm.
  """
  function RecoPlan(::Type{T}; parameter = missing) where {T<:AbstractImageReconstructionAlgorithm}
    dict = Dict{Symbol, Observable{Any}}()
    dict[:parameter] = Observable{Any}(missing)
    plan = new{getfield(parentmodule(T), nameof(T))}(nothing, dict)
    setproperty!(plan, :parameter, parameter)
    return plan
  end
end

"""
    propertynames(plan::RecoPlan{T}) where {T}

Return a tupel of configurable properties of `T`. Unlike `propertynames(T)` this does not include properties starting with `_`.
"""
Base.propertynames(plan::RecoPlan{T}) where {T} = Tuple(keys(getfield(plan, :values)))
"""
    getproperty(plan::RecoPlan{T}, name::Symbol) where {T}

Get the property `name` of `plan`. Equivalent to `plan.name`.
"""
Base.getproperty(plan::RecoPlan{T}, name::Symbol) where {T} = getfield(plan, :values)[name][]
"""
    getindex(plan::RecoPlan{T}, name::Symbol) where {T}

Return the `Observable` for the `name` property of `plan`. Equivalent to `plan[name]`.
"""
Base.getindex(plan::RecoPlan{T}, name::Symbol) where {T} = getfield(plan, :values)[name]

# Tree Interface
"""
    parent(plan::RecoPlan)

Return the parent of `plan`.
"""
AbstractTrees.parent(plan::RecoPlan) = getfield(plan, :parent)
AbstractTrees.ParentLinks(::Type{<:RecoPlan}) = AbstractTrees.StoredParents()
function AbstractTrees.children(plan::RecoPlan)
  result = Vector{RecoPlan}()
  for prop in propertynames(plan)
    if getproperty(plan, prop) isa RecoPlan
      push!(result, getproperty(plan, prop))
    end
  end
  return result
end

export types, type
types(::AbstractRecoPlan{T}) where {T<:AbstractImageReconstructionParameters} = fieldtypes(T)
type(::AbstractRecoPlan{T}, name::Symbol) where {T<:AbstractImageReconstructionParameters} = fieldtype(T, name)

function type(plan::AbstractRecoPlan{T}, name::Symbol) where {T<:AbstractImageReconstructionAlgorithm}
  if name == :parameter
    return RecoPlan
  else
    error("type $(typeof(plan)) has no field $name")
  end
end
types(::AbstractRecoPlan{T}) where {T<:AbstractImageReconstructionAlgorithm} = [type(plan, name) for name in propertynames(plan)]

"""
    setproperty!(plan::RecoPlan{T}, name::Symbol, x::X) where {T, X}
  
Set the property `name` of `plan` to `x`. Equivalent to `plan.name = x`. Triggers callbacks attached to the property.
"""
function Base.setproperty!(plan::RecoPlan{T}, name::Symbol, x::X) where {T, X}  
  if !haskey(getfield(plan, :values), name)
    error("type $T has no field $name")
  end

  t = type(plan, name)
  if validvalue(plan, t, x) 
    getfield(plan, :values)[name][] = x
  else
    getfield(plan, :values)[name][] = convert(t, x)
  end

  if x isa RecoPlan
    parent!(x, plan)
  end

  return Base.getproperty(plan, name)
end
validvalue(plan, t, value::Missing) = true
validvalue(plan, ::Type{T}, value::X) where {T, X <: T} = true
validvalue(plan, ::Type{T}, value::AbstractRecoPlan{<:T}) where T = true
# RecoPlans are stripped of parameters
validvalue(plan, t::UnionAll, ::AbstractRecoPlan{T}) where T = T <: t || T <: Base.typename(t).wrapper # Last case doesnt work for Union{...} that is a UnionAll, such as ProcessCache Unio
validvalue(plan, t::Type{Union}, value) = validvalue(plan, t.a, value) || validvalue(plan, t.b, value)
validvalue(plan, t, value) = false
validvalue(plan, ::Type{arrT}, value::AbstractArray) where {T, arrT <: AbstractArray{T}} = all(x -> validvalue(plan, T, x), value)

#X <: t || X <: RecoPlan{<:t} || ismissing(x)

export setAll!
"""
    setAll!(plan::RecoPlan{T}, name::Symbol, x) where {T<:AbstractImageReconstructionParameters}

Recursively set the property `name` of each nested `RecoPlan` of `plan` to `x`.
"""
function setAll!(plan::RecoPlan{T}, name::Symbol, x) where {T<:AbstractImageReconstructionParameters}
  fields = getfield(plan, :values)
  
  # Filter out nested plans
  nestedPlans = filter(entry -> begin 
    val = Observables.to_value(last(entry))
    return isa(val, RecoPlan) || isa(val, AbstractArray{<:RecoPlan})
  end, fields)

  # Recursively call setAll! on nested plans
  for (key, nested) in nestedPlans
    key != name && setAll!(Observables.to_value(nested), name, x)
  end

  # Set the value of the field
  if hasproperty(plan, name)
    try
      Base.setproperty!(plan, name, x)
    catch ex
      @error ex
      @warn "Could not set $name of $T with value of type $(typeof(x))"
    end
  end
end
setAll!(plans::AbstractArray{<:AbstractRecoPlan}, name::Symbol, x) = foreach(p -> setAll!(p, name, x), plans) 
setAll!(plan::RecoPlan{<:AbstractImageReconstructionAlgorithm}, name::Symbol, x) = setAll!(plan.parameter, name, x)
"""
    setAll!(plan::AbstractRecoPlan; kwargs...)

Call `setAll!` with each given keyword argument.
"""
function setAll!(plan::AbstractRecoPlan; kwargs...)
  for key in keys(kwargs)
    setAll!(plan, key, kwargs[key])
  end
end
"""
    setAll!(plan::AbstractRecoPlan, dict::Union{Dict{Symbol, Any}, Dict{String, Any}})

Call `setAll!` with each entries of the dict.
"""
setAll!(plan::AbstractRecoPlan, dict::Dict{Symbol, Any}) = setAll!(plan; dict...)
setAll!(plan::AbstractRecoPlan, dict::Dict{String, Any}) = setAll!(plan, Dict{Symbol, Any}(Symbol(k) => v for (k,v) in dict))

export clear!
"""
    clear!(plan::RecoPlan{T}, preserve::Bool = true) where {T<:AbstractImageReconstructionParameters}

Clear all properties of `plan`. If `preserve` is `true`, nested `RecoPlan`s are preserved.
"""
function clear!(plan::RecoPlan{T}, preserve::Bool = true) where {T<:AbstractImageReconstructionParameters}
  dict = getfield(plan, :values)
  for key in keys(dict)
    value = dict[key][]
    if typeof(value) <: RecoPlan && preserve 
      clear!(value, preserve)
    else
      value = missing
    end
    dict[key] = Observable{Any}(value)
  end
  return plan
end
clear!(plan::RecoPlan{T}, preserve::Bool = true) where {T<:AbstractImageReconstructionAlgorithm} = clear!(plan.parameter, preserve)


export parent!, parentproperty, parentproperties
"""
    parent!(plan::RecoPlan, parent::RecoPlan)

Set the parent of `plan` to `parent`.
"""
parent!(plan::RecoPlan, parent::RecoPlan) = setfield!(plan, :parent, parent)
"""
    parentproperties(plan::RecoPlan)

Return a vector of property names of `plan` in its parent, s.t. `getproperty(parent(plan), last(parentproperties(plan))) === plan`. Return an empty vector if `plan` has no parent.
"""
function parentproperties(plan::AbstractRecoPlan)
  trace = Symbol[]
  return parentproperties!(trace, plan)
end
"""
    parentproperty(plan::RecoPlan)

Return the property name of `plan` in its parent, s.t. `getproperty(parent(plan), parentproperty(plan)) === plan`. Return `nothing` if `plan` has no parent.
"""
function parentproperty(plan::AbstractRecoPlan)
  p = parent(plan)
  if !isnothing(p)
    for property in propertynames(p)
      if getproperty(p, property) === plan
        return property
      end
    end
  end
  return nothing
end
function parentproperties!(trace::Vector{Symbol}, plan::AbstractRecoPlan)
  p = parent(plan)
  parentprop = parentproperty(plan)
  if !isnothing(p) && !isnothing(parentprop)
    pushfirst!(trace, parentprop)
    return parentproperties!(trace, p)
  end
  return trace
end

"""
    ismissing(plan::RecoPlan, name::Symbol)
Indicate if the property `name` of `plan` is missing.
"""
Base.ismissing(plan::RecoPlan, name::Symbol) = ismissing(getfield(plan, :values)[name])

export build
"""
    build(plan::RecoPlan{T}) where {T}

Recursively build a plan from a `RecoPlan` by converting all properties to their actual values using keyword argument constructors.
"""
function build(plan::RecoPlan{T}) where {T<:AbstractImageReconstructionParameters}
  fields = Dict{Symbol, Any}()
  # Retrieve key-value (property-value) pairs of the plan
  for (k, v) in getfield(plan, :values)
    fields[k] = Observables.to_value(v)
  end

  # Recursively build nested plans
  nestedPlans = filter(entry -> isa(last(entry), RecoPlan) || isa(last(entry), AbstractArray{<:RecoPlan}), fields)
  for (name, nested) in nestedPlans
    fields[name] = build(nested)
  end

  # Remove missing values
  fields = filter(entry -> !ismissing(last(entry)), fields)
  
  return T(;fields...)
end
build(plans::AbstractArray{<:RecoPlan}) = map(build, plans)
function build(plan::AbstractRecoPlan{T}) where {T<:AbstractImageReconstructionAlgorithm}
  parameter = build(getproperty(plan, :parameter))
  return T(parameter)
end

export toPlan
"""
    toPlan(param::Union{AbstractImageReconstructionParameters, AbstractImageReconstructionAlgorithm})
  
Convert an `AbstractImageReconstructionParameters` or `AbstractImageReconstructionAlgorithm` to a (nested) `RecoPlan`.
"""
function toPlan(param::AbstractImageReconstructionParameters)
  args = Dict{Symbol, Any}()
  plan = RecoPlan(typeof(param))
  for field in fieldnames(typeof(param))
    value = getproperty(param, field)
    if typeof(value) <: AbstractImageReconstructionParameters || typeof(value) <: AbstractImageReconstructionAlgorithm
      args[field] = toPlan(plan, value)
    else
      args[field] = value
    end
  end
  setAll!(plan; args...)
  return plan
end
function toPlan(parent::AbstractRecoPlan, x)
  plan = toPlan(x)
  parent!(plan, parent)
  return plan
end 
toPlan(algo::AbstractImageReconstructionAlgorithm) = toPlan(algo, parameter(algo))
toPlan(algo::AbstractImageReconstructionAlgorithm, params::AbstractImageReconstructionParameters) = toPlan(typeof(algo), params) 
function toPlan(::Type{T}, params::AbstractImageReconstructionParameters) where {T<:AbstractImageReconstructionAlgorithm}
  plan = RecoPlan(T)
  Base.setproperty!(plan, :parameter, toPlan(plan, params))
  return plan
end

include("Show.jl")
include("Listeners.jl")
include("Serialization.jl")
include("Cache.jl")