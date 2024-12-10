export RecoPlan
mutable struct RecoPlan{T<:Union{AbstractImageReconstructionParameters, AbstractImageReconstructionAlgorithm}}
  parent::Union{Nothing, RecoPlan}
  values::Dict{Symbol, Observable{Any}}
  function RecoPlan(::Type{T}; kwargs...) where {T<:AbstractImageReconstructionParameters}
    dict = Dict{Symbol, Observable{Any}}()
    for field in filter(f -> !startswith(string(f), "_"), fieldnames(T))
      dict[field] =  Observable{Any}(missing)
    end
    plan = new{getfield(parentmodule(T), nameof(T))}(nothing, dict)
    setAll!(plan; kwargs...)
    return plan
  end
  function RecoPlan(::Type{T}; parameter = missing) where {T<:AbstractImageReconstructionAlgorithm}
    dict = Dict{Symbol, Observable{Any}}()
    dict[:parameter] = Observable{Any}(missing)
    plan = new{getfield(parentmodule(T), nameof(T))}(nothing, dict)
    setproperty!(plan, :parameter, parameter)
    return plan
  end
end


Base.propertynames(plan::RecoPlan{T}) where {T} = Tuple(keys(getfield(plan, :values)))
Base.getproperty(plan::RecoPlan{T}, name::Symbol) where {T} = getfield(plan, :values)[name][]
Base.getindex(plan::RecoPlan{T}, name::Symbol) where {T} = getfield(plan, :values)[name]

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
ispropertyset(plan::RecoPlan, name::Symbol) = getfield(plan, :setProperties)[name]
validvalue(plan, t, value::Missing) = true
validvalue(plan, ::Type{T}, value::X) where {T, X <: T} = true
validvalue(plan, ::Type{T}, value::RecoPlan{<:T}) where T = true
# RecoPlans are stripped of parameters
validvalue(plan, t::UnionAll, ::RecoPlan{T}) where T = T <: t || T <: Base.typename(t).wrapper # Last case doesnt work for Union{...} that is a UnionAll, such as ProcessCache Unio
validvalue(plan, t::Type{Union}, value) = validvalue(plan, t.a, value) || validvalue(plan, t.b, value)
validvalue(plan, t, value) = false
validvalue(plan, ::Type{arrT}, value::AbstractArray) where {T, arrT <: AbstractArray{T}} = all(x -> validvalue(plan, T, x), value)

#X <: t || X <: RecoPlan{<:t} || ismissing(x)

export setAll!
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
setAll!(plans::AbstractArray{<:RecoPlan}, name::Symbol, x) = foreach(p -> setAll!(p, name, x), plans) 
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


export parent, parent!
parent(plan::RecoPlan) = getfield(plan, :parent)
parent!(plan::RecoPlan, parent::RecoPlan) = setfield!(plan, :parent, parent)
function parentproperties(plan::RecoPlan)
  trace = Symbol[]
  return parentproperties!(trace, plan)
end
function parentproperties!(trace::Vector{Symbol}, plan::RecoPlan)
  p = parent(plan)
  if !isnothing(p)
    for property in propertynames(p)
      if getproperty(p, property) === plan
        pushfirst!(trace, property)
        return parentproperties!(trace, p)
      end
    end
  end
  return trace
end

Base.ismissing(plan::RecoPlan, name::Symbol) = ismissing(getfield(plan, :values)[name])

export build
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
function build(plan::RecoPlan{T}) where {T<:AbstractImageReconstructionAlgorithm}
  parameter = build(getproperty(plan, :parameter))
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
  setAll!(plan; args...)
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
  Base.setproperty!(plan, :parameter, toPlan(plan, params))
  return plan
end

include("Show.jl")
include("Listeners.jl")
include("Serialization.jl")
include("Cache.jl")