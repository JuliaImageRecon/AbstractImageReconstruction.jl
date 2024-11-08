export ProcessResultCache
Base.@kwdef mutable struct ProcessResultCache{P <: AbstractImageReconstructionParameters} <: AbstractImageReconstructionParameters
  param::P
  const maxsize::Int64 = 1
  cache::LRU{UInt64, Any} = LRU{UInt64, Any}(maxsize = maxsize)
end
function process(algo::Union{A, Type{<:A}}, param::ProcessResultCache, inputs...) where {A<:AbstractImageReconstructionAlgorithm}
  id = hash(param.param, hash(inputs, hash(algo)))
  result = get!(param.cache, id) do 
    process(algo, param.param, inputs...)
  end
  param.cache[id] = result
  return result
end

function clear!(plan::RecoPlan{<:ProcessResultCache}, preserve::Bool = true)
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

function validvalue(plan, ::Type{T}, value::RecoPlan{<:ProcessResultCache}) where T
  innertype = value.param isa RecoPlan ? typeof(value.param).parameters[1] : typeof(value.param)
  return ProcessResultCache{<:innertype} <: T 
end

# Do not serialize cache and lock, only param
function addDictValue!(dict, cache::RecoPlan{<:ProcessResultCache})
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
  setvalues!(plan; param, cache, maxsize)
  return plan
end

Base.empty!(cache::ProcessResultCache) = empty!(cache.cache)

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


function showproperty(io::IO, name, property::RecoPlan{ProcessResultCache}, indent, islast, depth)
  print(io, indent, islast ? ELBOW : TEE, name, "::$(typeof(property.param)) [Cached, $(property.maxsize)]", "\n")
  showtree(io, property.param, indent * (islast ? INDENT : PIPE), depth + 1)
end