export AbstractPlanListener
abstract type AbstractPlanListener end

export RecoPlan
mutable struct RecoPlan{T<:Union{AbstractImageReconstructionParameters, AbstractImageReconstructionAlgorithm}}
  parent::Union{Nothing, RecoPlan}
  values::Dict{Symbol, Any}
  listeners::Dict{Symbol, Vector{AbstractPlanListener}}
  setProperties::Dict{Symbol, Bool}
  function RecoPlan(::Type{T}; kwargs...) where {T<:AbstractImageReconstructionParameters}
    dict = Dict{Symbol, Any}()
    listeners = Dict{Symbol, Vector{AbstractPlanListener}}()
    setProperties = Dict{Symbol, Bool}()
    for field in filter(f -> !startswith(string(f), "_"), fieldnames(T))
      dict[field] =  missing
      listeners[field] = AbstractPlanListener[]
      setProperties[field] = false
    end
    plan = new{getfield(parentmodule(T), nameof(T))}(nothing, dict, listeners, setProperties)
    setvalues!(plan, kwargs...)
    return plan
  end
  function RecoPlan(::Type{T}) where {T<:AbstractImageReconstructionAlgorithm}
    dict = Dict{Symbol, Any}()
    listeners = Dict{Symbol, Vector{AbstractPlanListener}}()
    setProperties = Dict{Symbol, Bool}()
    dict[:parameter] = missing
    listeners[:parameter] = AbstractPlanListener[]
    setProperties[:parameter] = false
    return new{getfield(parentmodule(T), nameof(T))}(nothing, dict, listeners, setProperties)
  end
end


Base.propertynames(plan::RecoPlan{T}) where {T} = Tuple(keys(getfield(plan, :values)))
Base.getproperty(plan::RecoPlan{T}, name::Symbol) where {T} = getfield(plan, :values)[name]
Base.getindex(plan::RecoPlan{T}, name::Symbol) where {T} = Base.getproperty(plan, name)

export types, type
types(::RecoPlan{T}) where {T<:AbstractImageReconstructionParameters} = fieldtypes(T)
type(::RecoPlan{T}, name::Symbol) where {T<:AbstractImageReconstructionParameters} = fieldtype(T, name)

function type(plan::RecoPlan{T}, name::Symbol) where {T<:AbstractImageReconstructionAlgorithm}
  if name == :parameter
    return RecoPlan
  else
    error("type $(typeof(plan)) has no field $name")
  end
end
types(::RecoPlan{T}) where {T<:AbstractImageReconstructionAlgorithm} = [type(plan, name) for name in propertynames(plan)]


export ispropertyset, setvalue!
function Base.setproperty!(plan::RecoPlan{T}, name::Symbol, x::X) where {T, X}
  old = getproperty(plan, name) 
  setvalue!(plan, name, x)
  getfield(plan, :setProperties)[name] = true
  for listener in getlisteners(plan, name)
    try
      propertyupdate!(listener, plan, name, old, x)
    catch e
      @error "Exception in listener $listener " e
    end
  end
end
ispropertyset(plan::RecoPlan, name::Symbol) = getfield(plan, :setProperties)[name]
Base.setindex!(plan::RecoPlan, x, name::Symbol) = Base.setproperty!(plan, name, x)
function setvalue!(plan::RecoPlan{T}, name::Symbol, x::X) where {T, X}
  old = Base.getproperty(plan, name)
  
  if !haskey(getfield(plan, :values), name)
    error("type $T has no field $name")
  end

  t = type(plan, name)
  if validvalue(plan, t, x) 
    getfield(plan, :values)[name] = x
  else
    getfield(plan, :values)[name] = convert(t, x)
  end

  new = Base.getproperty(plan, name)
  for listener in getlisteners(plan, name)
    try
      valueupdate(listener, plan, name, old, new)
    catch e
      @error "Exception in listener $listener " e
    end
  end
  return new
end
validvalue(plan, t, value::Missing) = true
validvalue(plan, ::Type{T}, value::X) where {T, X <: T} = true
validvalue(plan, ::Type{T}, value::RecoPlan{<:T}) where T = true
# RecoPlans are stripped of parameters
validvalue(plan, t::UnionAll, ::RecoPlan{T}) where T = T <: t || T <: Base.typename(t).wrapper # Last case doesnt work for Union{...} that is a UnionAll, such as ProcessCache Unio
validvalue(plan, t::Type{Union}, value) = validvalue(plan, t.a, value) || validvalue(plan, t.b, value)
validvalue(plan, t, value) = false

#X <: t || X <: RecoPlan{<:t} || ismissing(x)

function setvalues!(plan::RecoPlan{T}; kwargs...) where {T<:AbstractImageReconstructionParameters}
  kwargs = values(kwargs)
  for field in propertynames(plan)
    if haskey(kwargs, field)
      setvalue!(plan, field, kwargs[field])
    end
  end
end

export setAll!
function setAll!(plan::RecoPlan{T}, name::Symbol, x) where {T<:AbstractImageReconstructionParameters}
  fields = getfield(plan, :values)
  nestedPlans = filter(entry -> isa(last(entry), RecoPlan), fields)
  for (key, nested) in nestedPlans
    key != name && setAll!(nested, name, x)
  end
  if hasproperty(plan, name)
    try
      plan[name] = x
    catch ex
      @warn "Could not set $name of $T with value of type $(typeof(x))"
    end
  end
end
setAll!(plan::RecoPlan{<:AbstractImageReconstructionAlgorithm}, name::Symbol, x) = setAll!(plan.parameter, name, x)
function setAll!(plan; kwargs...)
  for key in keys(kwargs)
    setAll!(plan, key, kwargs[key])
  end
end
setAll!(plan::RecoPlan, dict::Dict{Symbol, Any}) = setAll!(plan; dict...)
setAll!(plan::RecoPlan, dict::Dict{String, Any}) = setAll!(plan, Dict{Symbol, Any}(Symbol(k) => v for (k,v) in dict))

export clear!
function clear!(plan::RecoPlan{T}, preserve::Bool = true) where {T<:AbstractImageReconstructionParameters}
  dict = getfield(plan, :values)
  set = getfield(plan, :setProperties)
  for key in keys(dict)
    value = dict[key]
    if typeof(value) <: RecoPlan && preserve 
      clear!(value, preserve)
    else
      dict[key] = missing
      set[key] = false
    end
  end
  return plan
end
clear!(plan::RecoPlan{T}, preserve::Bool = true) where {T<:AbstractImageReconstructionAlgorithm} = clear!(plan.parameter, preserve)


export parent, parent!
parent(plan::RecoPlan) = getfield(plan, :parent)
parent!(plan::RecoPlan, parent::RecoPlan) = setfield!(plan, :parent, parent)
function parentfields(plan::RecoPlan)
  trace = Symbol[]
  return parentfields!(trace, plan)
end
function parentfields!(trace::Vector{Symbol}, plan::RecoPlan)
  p = parent(plan)
  if !isnothing(p)
    for property in propertynames(p)
      if getproperty(p, property) === plan
        pushfirst!(trace, property)
        return parentfields!(trace, p)
      end
    end
  end
  return trace
end

function RecoPlan(parent::RecoPlan, t::Type; kwargs...)
  plan = RecoPlan(t; kwargs...)
  parent!(plan, parent)
  return plan
end

Base.ismissing(plan::RecoPlan, name::Symbol) = ismissing(getfield(plan, :values)[name])

export build
function build(plan::RecoPlan{T}) where {T<:AbstractImageReconstructionParameters}
  fields = copy(getfield(plan, :values))
  nestedPlans = filter(entry -> isa(last(entry), RecoPlan), fields)
  for (name, nested) in nestedPlans
    fields[name] = build(nested)
  end
  fields = filter(entry -> !ismissing(last(entry)), fields)
  return T(;fields...)
end
function build(plan::RecoPlan{T}) where {T<:AbstractImageReconstructionAlgorithm}
  parameter = build(plan[:parameter])
  return T(parameter)
end

export toPlan
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
  setvalues!(plan; args...)
  return plan
end
function toPlan(parent::RecoPlan, x)
  plan = toPlan(x)
  parent!(plan, parent)
  return plan
end 
toPlan(algo::AbstractImageReconstructionAlgorithm) = toPlan(algo, parameter(algo))
toPlan(algo::AbstractImageReconstructionAlgorithm, params::AbstractImageReconstructionParameters) = toPlan(typeof(algo), params) 
function toPlan(::Type{T}, params::AbstractImageReconstructionParameters) where {T<:AbstractImageReconstructionAlgorithm}
  plan = RecoPlan(T)
  plan[:parameter] = toPlan(plan, params)
  return plan
end

include("Listeners.jl")
include("Serialization.jl")
include("Cache.jl")