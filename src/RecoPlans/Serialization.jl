export MODULE_TAG, TYPE_TAG
const MODULE_TAG = "_module"
const TYPE_TAG = "_type"
const VALUE_TAG = "_value"
const UNION_TYPE_TAG = "_uniontype"
const UNION_MODULE_TAG = "_unionmodule"

struct ModuleDict
  dict::Dict{String, Dict{String, Union{DataType, UnionAll, Function}}}
  ModuleDict(mod::Module) = ModuleDict([mod])
  function ModuleDict(modules::Vector{Module})
    if !(in(Core, modules))
      push!(modules, Core)
    end
    if !(in(Base, modules))
      push!(modules, Base)
    end

    modDict = Dict{String, Dict{String, Union{DataType, UnionAll, Function}}}()
    for mod in modules
      typeDict = Dict{String, Union{DataType, UnionAll, Function}}()
      for field in names(mod)
        try
          t = getfield(mod, field)
          if t isa DataType || t isa UnionAll || t isa Function
            typeDict[string(field)] = t
          end
        catch
        end
      end
      modDict[string(mod)] = typeDict
    end
    return new(modDict)
  end
end
function getindex(modDict::ModuleDict, mod::String, type::String)
  if haskey(modDict.dict, mod)
    moduleTypes = modDict.dict[mod]
    if haskey(moduleTypes, type)
      return moduleTypes[type]
    end
  end
  return nothing
end

export MODULE_DICT
const MODULE_DICT = ScopedValue{Union{Nothing, ModuleDict}}(nothing)
getindex(modDict::ScopedValue{Union{Nothing, ModuleDict}}, mod::String, type::String) = modDict[][mod, type]
getindex(modDict::ScopedValue{Union{Nothing, ModuleDict}}, mod, type) = modDict[string(mod), string(type)] 

export RecoPlanStyle
export CustomPlanStyle
struct RecoPlanStyle <: StructUtils.StructStyle end
const PLAN_STYLE = ScopedValue{StructUtils.StructStyle}(RecoPlanStyle())
const FIELD_STYLE = ScopedValue{StructUtils.StructStyle}(RecoPlanStyle())
StructUtils.dictlike(::Type{RecoPlan}) = true

abstract type CustomPlanStyle <: StructUtils.StructStyle end
StructUtils.lower(::CustomPlanStyle, x) = StructUtils.lower(RecoPlanStyle(), x)

export savePlan
"""
    savePlan(file::Union{AbstractString, IO}, plan::RecoPlan)

Save the `plan` to the `file` in TOML format.
See also `loadPlan`, `toTOML`, `toDict`.
"""
function savePlan(filename::String, plan::RecoPlan; kwargs...)
  open(filename, "w") do io
      savePlan(io, plan; kwargs...)
  end
end

function savePlan(io::IO, plan::RecoPlan; plan_style = RecoPlanStyle(), field_style = RecoPlanStyle())
  with(PLAN_STYLE => plan_style, FIELD_STYLE => field_style) do
    dict = StructUtils.lower(RecoPlanStyle(), plan)
    TOML.print(io, dict)
  end
end

function StructUtils.lower(::RecoPlanStyle, plan::RecoPlan{T}) where T
  dict = Dict{String, Any}(
    MODULE_TAG => string(parentmodule(T)),
    TYPE_TAG => "RecoPlan{$(getfield(parentmodule(T), nameof(T)))}"
  )

  listenerDict = Dict{String, Any}()
  for field in propertynames(plan)
    value = getproperty(plan, field)
    if !ismissing(value)
      if value isa RecoPlan
        dict[string(field)] = StructUtils.lower(PLAN_STYLE[], value)
      elseif value isa AbstractArray{<:RecoPlan}
        dict[string(field)] = map(v -> StructUtils.lower(PLAN_STYLE[], v), value)
      else
        fieldvalue = StructUtils.lower(FIELD_STYLE[], value)
        # In case of a union we need to store the union + actual field value:
        if type(plan, field) isa Union
          union = Dict{String, Any}()
          union[VALUE_TAG] = fieldvalue
          union[UNION_TYPE_TAG] = string(typeof(value))
          union[UNION_MODULE_TAG] = string(parentmodule(typeof(value)))
          fieldvalue = union
        end
        dict[string(field)] = fieldvalue
      end
    end
    listeners = filter(l -> l isa AbstractPlanListener, last.(Observables.listeners(plan[field])))
    if !isempty(listeners)
      listenerDict[string(field)] = map(l -> StructUtils.lower(PLAN_STYLE[], l), listeners)
    end
  end

  if !isempty(listenerDict) 
    dict[LISTENER_TAG] = listenerDict
  end
  return dict
end

StructUtils.lower(::RecoPlanStyle, x::Module) = string(x)
StructUtils.lower(::RecoPlanStyle, x::Symbol) = string(x)
StructUtils.lower(::RecoPlanStyle, x::T) where {T<:Enum} = string(x)
StructUtils.lower(style::RecoPlanStyle, x::AbstractArray) = map(v -> StructUtils.lower(style, v), x)
StructUtils.lower(::RecoPlanStyle, x::Nothing) = Dict()
StructUtils.lower(style::RecoPlanStyle, x::Tuple) = StructUtils.lower(style, collect(x))
StructUtils.lower(::RecoPlanStyle, value) = value
StructUtils.lower(::RecoPlanStyle, x::Complex{T}) where T = string(x)

function StructUtils.lower(::RecoPlanStyle, ::Type{T}) where {T}
  return Dict{String, Any}(
      MODULE_TAG => string(parentmodule(T)),
      TYPE_TAG => "Type",
      VALUE_TAG => string(nameof(T))
  )
end

function StructUtils.lower(::RecoPlanStyle, f::Function)
  return Dict{String, Any}(
      MODULE_TAG => string(parentmodule(f)),
      TYPE_TAG => string(nameof(f))
  )
end

export loadPlan
"""
    loadPlan(filename::Union{AbstractString, IO}, modules::Vector{Module})
  
Load a `RecoPlan` from a TOML file. The `modules` argument is a vector of modules that contain the types used in the plan.
After loading the plan, the listeners are attached to the properties using `loadListener!`.
"""
function loadPlan(filename::String, modules; kwargs...)
  open(filename) do io
    return loadPlan(io, modules)
  end
end
function loadPlan(filename::IO, modules::Vector{Module}; plan_style=RecoPlanStyle(), field_style=RecoPlanStyle())
  dict = TOML.parse(filename)
  plan = with(MODULE_DICT => ModuleDict(modules), 
        PLAN_STYLE => plan_style,
        FIELD_STYLE => field_style) do
    plan, _ = StructUtils.make(plan_style, RecoPlan, dict)
    #loadListeners!(plan, dict)
    return plan
  end
  return plan
end
function StructUtils.make(style::RecoPlanStyle, ::Type{RecoPlan}, dict::Dict{String, Any})
  re = r"RecoPlan\{(.*)\}"
  m = match(re, dict[TYPE_TAG])
  if !isnothing(m)
    type = m.captures[1]
    mod = dict[MODULE_TAG]
    plan = RecoPlan(MODULE_DICT[mod, type])
    StructUtils.make!(style, plan, dict)
    return plan, dict
  else
    # Has to be parameter or algo or broken toml
    # TODO implement
    error("Not implemented yet")
  end
end
function StructUtils.make!(style::RecoPlanStyle, plan::RecoPlan{T}, dict::Dict{String, Any}) where {T<:AbstractImageReconstructionAlgorithm}
  temp, _ = StructUtils.make(style, RecoPlan, dict["parameter"])
  parent!(temp, plan)
  setproperty!(plan, :parameter, temp)
  return plan
end
function StructUtils.make!(style::RecoPlanStyle, plan::RecoPlan{T}, dict::Dict{String, Any}) where {T<:AbstractImageReconstructionParameters}
  for name in propertynames(plan)
    t = type(plan, name)
    param = missing
    key = string(name)
    if haskey(dict, key)
      if t <: AbstractImageReconstructionAlgorithm || t <: AbstractImageReconstructionParameters
        param, _ = StructUtils.make(style, RecoPlan, dict[key])
        parent!(param, plan)
      elseif t <: Vector{<:AbstractImageReconstructionAlgorithm} || t <: Vector{<:AbstractImageReconstructionParameters}
        param = map(x-> first(StructUtils.make(style, RecoPlan, x)), dict[key])
        foreach(p -> parent!(p, plan), param)
      elseif t isa Union
        param = deserializeUnion(t, dict[key])
      else
        lifted = StructUtils.lift(FIELD_STYLE[], t, dict[key])
        if !(lifted isa Tuple)
          @warn "Type $t with style $(FIELD_STYLE[]) did not return a tuple. This is likely caused by an incorrect lift method. Returned value will be used as is"
          param = lifted
        else
          param = first(lifted)
        end          
      end
    end

    setproperty!(plan, name, param)
  end
  return plan
end

function deserializeUnion(union_type::Union, union_dict)  
  value_data = union_dict[VALUE_TAG]
  type_str   = union_dict[UNION_TYPE_TAG]
  module_str = union_dict[UNION_MODULE_TAG]

  # 1. Try lifting with the union type itself (user may have defined a custom lift)
  try
    lifted = StructUtils.lift(FIELD_STYLE[], union_type, value_data)
    return lifted isa Tuple ? first(lifted) : lifted
  catch
    # If this fails, fall through to trying each union member
  end

  # 2. Try lifting with each union member
  successes = Tuple{Any,Any}[]  # (member_type, value)
  for member in Base.uniontypes(union_type)
    try
      lifted = StructUtils.lift(FIELD_STYLE[], member, value_data)
      val = lifted isa Tuple ? first(lifted) : lifted
      push!(successes, (member, val))
    catch
      # This member cannot handle the data; skip
    end
  end

  if isempty(successes)
    error("Could not deserialize union field of type $union_type from stored value $(value_data). " *
          "Consider defining `StructUtils.lift(::$(FIELD_STYLE[]), ::Type{$union_type}, ...)` " *
          "or for the individual member types.")
  elseif length(successes) == 1
    # Only one member can represent the value -> unambiguous
    return successes[1][2]
  end

  # 3. Multiple members succeeded – disambiguate using metadata
  matches = [(m, v) for (m, v) in successes
             if string(typeof(v)) == type_str &&
                string(parentmodule(typeof(v))) == module_str]

  if length(matches) == 1
    # Exactly one result matches the stored type metadata
    return matches[1][2]
  elseif isempty(matches)
    error("Ambiguous union deserialization for type $union_type: multiple union members " *
          "can represent the stored value $(value_data). Define a more specific `StructUtils.lift` for this union field.")
  else
    error("Ambiguous union deserialization for type $union_type: multiple candidates " *
          "produce values whose type matches the stored metadata $module_str.$type_str. " *
          "Define a more specific `StructUtils.lift` for this union.")
  end
end


StructUtils.lift(::RecoPlanStyle, ::Type{T}, source) where T = convert(T, source), source
StructUtils.lift(::RecoPlanStyle, ::Type{Symbol}, source::AbstractString) = Symbol(source), source
function StructUtils.lift(::RecoPlanStyle, ::Type{T}, source::AbstractString) where {T<:Enum}
  sym = Symbol(source)
  for (k, v) in Base.Enums.namemap(T)
      v === sym && return T(k), source
  end
  error("Unexpected value $source for enum $(T), expected value in $(Base.Enums.namemap(T))")
end
StructUtils.lift(style::RecoPlanStyle, ::Type{<:AbstractArray{T}}, source) where T = map(v -> first(StructUtils.lift(style, T, v)), source), source
function StructUtils.lift(::RecoPlanStyle, T::Type{<:Type}, source::Dict)
  return MODULE_DICT[source[MODULE_TAG], source[VALUE_TAG]], source
end
function StructUtils.lift(::RecoPlanStyle, ::Type{Nothing}, source::Dict) 
  if isempty(source)
    return nothing, source
  end
  error("Unexpected value $source for Nothing, expected empty Dict")
end
StructUtils.lift(style::RecoPlanStyle, ::Type{NTuple{N, T}}, source) where {N,T} = Tuple(map(v -> first(StructUtils.lift(style, T, v)), source)), source
StructUtils.lift(::RecoPlanStyle, ::Type{Complex{T}}, source) where T = string(x), source