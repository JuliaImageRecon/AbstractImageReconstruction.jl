export CachedProcessParameter
Base.@kwdef mutable struct CachedProcessParameter{P <: AbstractImageReconstructionParameters} <: AbstractImageReconstructionParameters
  param::P
  cache::Dict{UInt64, Any} = Dict{UInt64, Any}()
  lock::ReentrantLock = ReentrantLock()
end
function process(algo, param::CachedProcessParameter, inputs...)
  lock(param.lock) do 
    id = hash(param, hash(inputs))
    result = get(param.cache, id, process(algo, param.param, inputs...))
    param.cache[id] = result
    return result
  end
end

function validvalue(plan, ::Type{T}, value::RecoPlan{<:CachedProcessParameter}) where T
  innertype = value.param isa RecoPlan ? typeof(value.param).parameters[1] : typeof(value.param)
  return CachedProcessParameter{<:innertype} <: T 
end

# Do not serialize cache and lock, only param
addDictValue!(dict, cache::RecoPlan{<:CachedProcessParameter}) = dict["param"] = toDictValue(type(cache, :param), cache.param)

# When deserializing always construct cache and lock
# This means that all algorithms constructed by this plan share lock and cache
function loadPlan!(plan::RecoPlan{<:CachedProcessParameter}, dict::Dict{String, Any}, modDict)
  cache = Dict{UInt64, Any}()
  lock = ReentrantLock()
  param = missing
  if haskey(dict, "param")
    param = loadPlan!(dict["param"], modDict)
  end
  setvalues!(plan; param, cache, lock)
  return plan
end

function Base.empty!(cache::CachedProcessParameter)
  lock(cache.lock) do
    empty!(cache.cache)
  end
end