export toKwargs, toKwargs!, fromKwargs

function toKwargs(value; kwargs...)
  dict = Dict{Symbol, Any}()
  return toKwargs!(dict, value; kwargs...)
end

function toKwargs(values::Vector; kwargs...)
  dict = Dict{Symbol, Any}()
  foreach(i-> toKwargs!(dict, i; kwargs...), values)
  return dict
end

function toKwargs!(dict, value; flatten::Vector{DataType} = DataType[], ignore::Vector{Symbol} = Symbol[], default::Dict{Symbol, Any} = Dict{Symbol, Any}(), overwrite::Dict{Symbol, Any} = Dict{Symbol, Any}())
  for field in propertynames(value)
    prop = getproperty(value, field)
    if in(field, ignore)
      # NOP
    elseif any(i -> prop isa i, flatten)
      toKwargs!(dict, prop, flatten = flatten, ignore = ignore, default = default)
    elseif (isnothing(prop) || ismissing(prop)) && haskey(default, field)
      dict[field] = default[field]
    else
      dict[field] = prop
    end
  end
  for key in keys(overwrite)
    dict[key] = overwrite[key] 
  end
  return dict
end

"""
    toKwargs(value::AbstractImageReconstructionParameters; kwargs...)

Convert a `AbstractImageReconstructionParameters` to a `Dict{Symbol, Any}` of each property.

Optional keyword arguments:
* flatten::Vector{DataType}: Types to flatten, per default only `AbstractImageReconstructionParameters` are flattened.
* ignore::Vector{Symbol}: Properties to ignore.
* default::Dict{Symbol, Any}: Default values for properties that are missing.
* overwrite::Dict{Symbol, Any}: Overwrite values for properties.
"""
function toKwargs(v::AbstractImageReconstructionParameters; flatten::Union{Vector{DataType}, Nothing} = nothing, kwargs...)
  dict = Dict{Symbol, Any}()
  return toKwargs!(dict, v; flatten = isnothing(flatten) ? [AbstractImageReconstructionParameters] : flatten, kwargs...)
end
function toKwargs(v::Vector{<:AbstractImageReconstructionParameters}; flatten::Union{Vector{DataType}, Nothing} = nothing, kwargs...)
  dict = Dict{Symbol, Any}()
  flatten = isnothing(flatten) ? [AbstractImageReconstructionParameters] : flatten
  foreach(i-> toKwargs!(dict, i; flatten = flatten, kwargs...), v)
  return dict
end

"""
    fromKwargs(type::Type{T}; kwargs...) where {T}

Create a new instance of `type` from the keyword arguments. Only properties that are part of `type` are considered.
"""
function fromKwargs(type::Type{T}; kwargs...) where {T}
  args = Dict{Symbol, Any}()
  dict = values(kwargs)
  for field in fieldnames(type)
    if haskey(dict, field)
      args[field] = getproperty(dict, field)
    end
  end
  return type(;args...)
end