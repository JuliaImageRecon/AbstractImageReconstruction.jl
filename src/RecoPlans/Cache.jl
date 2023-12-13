export CachedProcessParameter
Base.@kwdef mutable struct CachedProcessParameter{P <: AbstractImageReconstructionParameters} <: AbstractImageReconstructionParameters
  param::P
  cache::LRU{UInt64, Any} = LRU{UInt64, Any}(maxsize = maxsize)
  const maxsize::Int64 = 1
end
function process(algo::AbstractImageReconstructionAlgorithm, param::CachedProcessParameter, inputs...)
  id = hash(param.param, hash(inputs, hash(algo)))
  result = get!(param.cache, id) do 
    process(algo, param.param, inputs...)
  end
  param.cache[id] = result
  return result
end
function process(algo::Type{<:AbstractImageReconstructionAlgorithm}, param::CachedProcessParameter, inputs...)
  id = hash(param.param, hash(inputs, hash(algo)))
  result = get!(param.cache, id) do 
    process(algo, param.param, inputs...)
  end
  param.cache[id] = result
  return result
end

function validvalue(plan, ::Type{T}, value::RecoPlan{<:CachedProcessParameter}) where T
  innertype = value.param isa RecoPlan ? typeof(value.param).parameters[1] : typeof(value.param)
  return CachedProcessParameter{<:innertype} <: T 
end

# Do not serialize cache and lock, only param
function addDictValue!(dict, cache::RecoPlan{<:CachedProcessParameter})
  size = cache.maxsize
  if !ismissing(size)
    dict["maxsize"] = size
  end
  dict["param"] = toDictValue(type(cache, :param), cache.param)
end

# When deserializing always construct cache and lock
# This means that all algorithms constructed by this plan share lock and cache
function loadPlan!(plan::RecoPlan{<:CachedProcessParameter}, dict::Dict{String, Any}, modDict)
  maxsize = get(dict, "maxsize", 1)
  cache = LRU{UInt64, Any}(;maxsize)
  param = missing
  if haskey(dict, "param")
    param = loadPlan!(dict["param"], modDict)
  end
  setvalues!(plan; param, cache, maxsize)
  return plan
end

Base.empty!(cache::CachedProcessParameter) = empty!(cache.cache)

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