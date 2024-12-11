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

export toTOML, toDict, toDict!, toDictValue, toDictValue!
# TODO adapt tomlType
const MODULE_TAG = "_module"
const TYPE_TAG = "_type"
const VALUE_TAG = "_value"
const UNION_TYPE_TAG = "_uniontype"
const UNION_MODULE_TAG = "_unionmodule"


function toTOML(fileName::AbstractString, value)
  open(fileName, "w") do io
    toTOML(io, value)
  end
end

function toTOML(io::IO, value)
  dict = toDict(value)
  TOML.print(io, dict) do x
    toTOML(x)
  end
end

toTOML(x::Module) = string(x)
toTOML(x::Symbol) = string(x)
toTOML(x::T) where {T<:Enum} = string(x)
toTOML(x::Array) = toTOML.(x)
toTOML(x::Type{T}) where T = string(x)
toTOML(x::Nothing) = Dict()

"""
    toDict(value)

Recursively convert `value` to a `Dict{String, Any}` using `toDict!`.
"""
function toDict(value)
  dict = Dict{String, Any}()
  return toDict!(dict, value)
end

"""
    toDict!(dict, value)

Extracts metadata such as the module and type name from `value` and adds it to `dict`. The value-representation of `value` is added using `toDictValue!`.
"""
function toDict!(dict, value)
  dict[MODULE_TAG] = toDictModule(value)
  dict[TYPE_TAG] = toDictType(value)
  toDictValue!(dict, value)
  return dict
end
toDictModule(value) = parentmodule(typeof(value))
toDictType(value) = nameof(typeof(value))
"""
    toDictValue!(dict, value)

Extracts the value-representation of `value` and adds it to `dict`. The default implementation for structs with fields adds each field of the argument as a key-value pair with the value being provided by the `toDictValue` function.
"""
function toDictValue!(dict, value)
  for field in fieldnames(typeof(value))
    dict[string(field)] = toDictValue(fieldtype(typeof(value), field), getfield(value, field))
  end
end

toDictType(value::Function) = nameof(value)
function toDictValue!(dict, value::Function)
  # NOP
end

"""
    toDictValue(value)

Transform `value` to a value-representation in a dict that can later be serialized as a TOML file.
"""
toDictValue(type, value) = toDictValue(value)
function toDictValue(x)
  if fieldcount(typeof(x)) > 0
    return toDict(x)
  else
    return x
  end
end
toDictValue(x::Array) = toDictValue.(x)
toDictValue(x::Type{T}) where T = toDict(x)
function toDict!(dict, ::Type{T}) where T
  dict[MODULE_TAG] = parentmodule(T)
  dict[TYPE_TAG] = Type
  dict[VALUE_TAG] = T
  return dict
end

function toDictValue(type::Union, value)
  dict = Dict{String, Any}()
  dict[MODULE_TAG] = toDictModule(type)
  dict[TYPE_TAG] = toDictType(type)
  dict[VALUE_TAG] = toDictValue(value)
  dict[UNION_TYPE_TAG] = typeof(value) # directly type to not remove parametric fields
  dict[UNION_MODULE_TAG] = toDictModule(typeof(value))
  return dict
end
