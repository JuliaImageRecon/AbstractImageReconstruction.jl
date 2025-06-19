export ProcessResultCache
"""
    ProcessResultCache(params::AbstractImageReconstructionParameters; maxsize = 1, kwargs...)

Cache of size `maxsize` for the result of `process` methods. The cache is based on the `hash` of the inputs of the `process` function. Cache is shared between all algorithms constructed from the same plan.
The cache is transparent for properties of the underlying parameter. Cache can be invalidated by calling `empty!` on the cache.
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
process(algo::A, param::ProcessResultCache, inputs...) where {A <: AbstractImageReconstructionAlgorithm} = hashed_process(algo, param, inputs...)
process(algoT::Type{<:A}, param::ProcessResultCache, inputs...) where {A <: AbstractImageReconstructionAlgorithm} = hashed_process(algoT, param, inputs...)
parameter(param::ProcessResultCache) = param.param

function hashed_process(algo, param::ProcessResultCache, inputs...)
  id = hash(param.param, hash(inputs, hash(algo)))
  result = get!(param.cache, id) do 
    process(algo, param.param, inputs...)
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
function toDictValue!(dict, cache::RecoPlan{<:ProcessResultCache})
  size = cache.maxsize
  if !ismissing(size)
    dict["maxsize"] = size
  end
  dict["param"] = toDictValue(type(cache, :param), cache.param)
end

# When deserializing always construct cache and lock
# This means that all algorithms constructed by this plan share lock and cache
function loadPlan!(plan::RecoPlan{<:ProcessResultCache}, dict::Dict{String, Any}, modDict)
  maxsize = get(dict, "maxsize", 1)
  cache = LRU{UInt64, Any}(;maxsize)
  param = missing
  if haskey(dict, "param")
    param = loadPlan!(dict["param"], modDict)
    parent!(param, plan)
  end
  setproperty!(plan, :maxsize, maxsize)
  setproperty!(plan, :cache, cache)
  setproperty!(plan, :param, param)
  return plan
end

"""
    empty!(cache::ProcessResultCache)

Empty the cache of the `ProcessResultCache`
"""
Base.empty!(cache::ProcessResultCache) = empty!(cache.cache)
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
"""
    hash(parameter::AbstractImageReconstructionParameters, h)

Default hash function for image reconstruction paramters. Uses `nameof` the parameter and all fields not starting with `_` to compute the hash.
"""
function Base.hash(parameter::T, h::UInt64) where T <: AbstractImageReconstructionParameters
  h = hash(nameof(T), h)
  for field in filter(f -> !startswith(string(f), "_"), fieldnames(T))
    h = hash(hash(getproperty(parameter, field)), h)
  end
  return h
end
function Base.hash(parameter::ProcessResultCache, h::UInt64)
  return hash(typeof(parameter), hash(parameter.maxsize, hash(parameter.param, h)))
end


function showproperty(io::IO, name, property::RecoPlan{ProcessResultCache}, indent, islast, depth)
  print(io, indent, islast ? ELBOW : TEE, name, "::$(typeof(property.param)) [Cached, $(property.maxsize)]", "\n")
  showtree(io, property.param, indent * (islast ? INDENT : PIPE), depth + 1)
end