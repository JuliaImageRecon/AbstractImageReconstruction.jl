export ProcessResultCache
"""
    ProcessResultCache(params::AbstractImageReconstructionParameters; maxsize = 1, kwargs...)

Cache of size `maxsize` for the results of parameter calls:

    (params::P)(algo, inputs...)

The cache key is based on the `hash` of the algorithm (or its `type`), the wrapped parameter, and
the inputs.

The same `ProcessResultCache` instance can be shared between algorithms constructed from the
same plan. The cache is transparent with respect to the properties of the underlying
parameter. Cached entries can be invalidated by calling `empty!(params)`. (Shallow) copies a RecoPlan{ProcessCache} share a cache instance.
"""
mutable struct ProcessResultCache{P} <: AbstractUtilityReconstructionParameters{P}
  param::P
  maxsize::Int64
  const cache::LRU{UInt64, Any}
  function ProcessResultCache(; param::Union{P, AbstractUtilityReconstructionParameters{P}}, maxsize::Int64 = 1, cache::LRU{UInt64, Any} = LRU{UInt64, Any}(maxsize = maxsize)) where P
    if maxsize != cache.maxsize
      @warn "Incosistent cache size detected. Found maxsize $maxsize and cache size $(cache.maxsize). This can happen when a cache is resized. Cache will use $(cache.maxsize)"
    end
    return ProcessResultCache(cache; param)
  end
  function ProcessResultCache(maxsize::Int64; param::Union{P, AbstractUtilityReconstructionParameters{P}}) where P
    cache::LRU{UInt64, Any} = LRU{UInt64, Any}(maxsize = maxsize)
    return new{P}(param, maxsize, cache)
  end
  function ProcessResultCache(cache::LRU{UInt64, Any}; param::Union{P, AbstractUtilityReconstructionParameters{P}}) where P
    maxsize = cache.maxsize
    return new{P}(param, maxsize, cache)
  end
end
ProcessResultCache(param::AbstractImageReconstructionParameters; kwargs...) = ProcessResultCache(;param, kwargs...)
parameter(param::ProcessResultCache) = param.param

function (param::ProcessResultCache)(algo::A, inputs...) where {A <: AbstractImageReconstructionAlgorithm}
  id = hash(param.param, hash(inputs, hash(algo)))
  result = get!(param.cache, id) do 
    param.param(algo, inputs...)
  end
  return result
end
function (param::ProcessResultCache)(algoT::Type{A}, inputs...) where {A <: AbstractImageReconstructionAlgorithm}
  id = hash(param.param, hash(inputs, hash(algoT)))
  result = get!(param.cache, id) do 
    param.param(algoT, inputs...)
  end
  return result
end

function clear!(plan::RecoPlan{<:ProcessResultCache}, preserve::Bool = true)
  dict = getfield(plan, :values)
  for key in keys(dict)
    value = dict[key][]
    # Dont remove cache when clearing and preserving structure
    if typeof(value) <: RecoPlan && preserve 
      clear!(value, preserve)
    else
      dict[key] = Observable{Any}(missing)
    end
  end
  return plan
end

# Make cache transparent for property getter/setter
function Base.setproperty!(plan::RecoPlan{<:ProcessResultCache}, name::Symbol, value)
  if in(name, [:param, :cache, :maxsize])
    t = type(plan, name)
    getfield(plan, :values)[name][] = validvalue(plan, t, value) ? value : convert(t, x)
    if name == :maxsize && !ismissing(plan.cache)
      @warn "Resizing cache will affect all algorithms constructed from this plan" maxlog = 3
      resize!(plan.cache; maxsize = plan.maxsize)
    end
  else
    setproperty!(plan.param, name, value)
  end
end
function Base.getproperty(plan::RecoPlan{<:ProcessResultCache}, name::Symbol)
  if in(name, [:param, :cache, :maxsize])
    return getfield(plan, :values)[name][]
  else
    return getproperty(plan.param, name)
  end
end


function validvalue(plan, union::Type{Union{T, ProcessResultCache{<:T}}}, value::RecoPlan{ProcessResultCache}) where T
  innertype = value.param isa RecoPlan ? typeof(value.param).parameters[1] : typeof(value.param)
  return ProcessResultCache{<:innertype} <: union 
end

function validvalue(plan, union::UnionAll, value::RecoPlan{ProcessResultCache})
  innertype = value.param isa RecoPlan ? typeof(value.param).parameters[1] : typeof(value.param)
  return ProcessResultCache{<:innertype} <: union 
end

function validvalue(plan, union::UnionAll, value::RecoPlan{<:ProcessResultCache})
  innertype = value.param isa RecoPlan ? typeof(value.param).parameters[1] : typeof(value.param)
  return ProcessResultCache{<:innertype} <: union 
end

# Do not serialize cache and lock, only param
function StructUtils.lower(::RecoPlanStyle,
                           plan::RecoPlan{T}) where {T<:ProcessResultCache}
  dict = Dict{String, Any}(
    MODULE_TAG => string(parentmodule(T)),
    TYPE_TAG => "RecoPlan{ProcessResultCache}"
  )

  size = plan.maxsize
  if !ismissing(size)
    dict["maxsize"] = size
  end

  param = plan.param
  if !ismissing(param)
    dict["param"] = StructUtils.lower(PLAN_STYLE[], plan.param)
  end
  return dict
end


# When deserializing always construct cache and lock
# This means that all algorithms constructed by this plan share lock and cache
function StructUtils.make!(style::RecoPlanStyle,
                           plan::RecoPlan{T},
                           dict::Dict{String, Any}) where {T<:ProcessResultCache}
  maxsize = get(dict, "maxsize", 1)

  cache = LRU{UInt64, Any}(;maxsize)
  
  param = missing
  if haskey(dict, "param")
      param_dict = dict["param"]
      param, _ = StructUtils.make(style, RecoPlan, param_dict)
      parent!(param, plan)
  end

  setproperty!(plan, :maxsize, maxsize)
  setproperty!(plan, :cache, cache)
  setproperty!(plan, :param, param)
  return plan
end

"""
    empty!(cache::ProcessResultCache)
    empty!(plan::RecoPlan{ProcessResultCache})

Empty the cache of the `ProcessResultCache`
"""
Base.empty!(cache::Union{ProcessResultCache, RecoPlan{<:ProcessResultCache}}) = empty!(cache.cache)
"""
    resize!(cache::ProcessResultCache)

Resize the cache. This will affect all algorithms sharing the cache, i.e. all algorithms constructed from the same RecoPlan.
"""
function Base.resize!(cache::ProcessResultCache, n)
  @warn "Resizing cache will affect all algorithms sharing the cache. Resizing will not update maxsize in RecoPlan" maxlog = 3
  cache.maxsize = n
  resize!(cache.cache; maxsize = n)
  return cache
end
function Base.hash(parameter::ProcessResultCache, h::UInt64)
  return hash(typeof(parameter), hash(parameter.maxsize, hash(parameter.param, h)))
end

function Base.copy(plan::RecoPlan{T}) where {T<:ProcessResultCache}
  # Old storage
  old_vals = getfield(plan, :values)

  # New observables and empty values
  new_plan = RecoPlan(T)
  
  # Similar to normal copy, except we share the underlying cache as well
    for (name, obs) in old_vals
      v = obs[]
      new_v = if name === :cache 
        v # share cache
      elseif (v isa RecoPlan) 
        copy(v)
      elseif (v isa AbstractArray{<:AbstractRecoPlan}) 
        map(copy, v)
      else
        v  # share non-plan values
      end
      Base.setproperty!(new_plan, name, new_v)
    end
  
  return new_plan
end


function showproperty(io::IO, name, property::RecoPlan{ProcessResultCache}, indent, islast, depth)
  print(io, indent, islast ? ELBOW : TEE, name, "::$(typeof(property.param)) [Cached, $(property.maxsize)]", "\n")
  showtree(io, property.param, indent * (islast ? INDENT : PIPE), depth + 1)
end