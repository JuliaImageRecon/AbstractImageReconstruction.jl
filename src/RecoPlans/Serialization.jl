export plandir, planpath
function plandir(m::Module)
  if m != AbstractImageReconstruction && hasproperty(m, :plandir)
    return getproperty(m, :plandir)()
  else
    return @get_scratch!(string(m))
  end
end
function planpath(m::Module, name::AbstractString) 
  if m != AbstractImageReconstruction && hasproperty(m, :planpath)
    return getproperty(m, :planpath)(name)
  else
    return joinpath(plandir(m), string(name, ".toml"))
  end
end

export savePlan
"""
    savePlan(file::Union{AbstractString, IO}, plan::RecoPlan)

Save the `plan` to the `file` in TOML format.
See also `loadPlan`, `toTOML`, `toDict`.
"""
savePlan(file::Union{AbstractString, IO}, plan::RecoPlan) = toTOML(file, plan)
savePlan(m::Module, planname::AbstractString, plan::RecoPlan) = savePlan(planpath(m, planname), plan)

toDictModule(plan::RecoPlan{T}) where {T} = parentmodule(T)
toDictType(plan::RecoPlan{T}) where {T} = RecoPlan{getfield(parentmodule(T), nameof(T))}
"""
    toDictValue!(dict, plan::RecoPlan)

Adds the properties of `plan` to `dict` using `toDictValue` for each not missing field. Additionally, adds each listener::AbstractPlanListener to the dict.
"""
function toDictValue!(dict, value::RecoPlan)
  listenerDict = Dict{String, Any}()
  for field in propertynames(value)
    x = getproperty(value, field)
    if !ismissing(x)
      dict[string(field)] = toDictValue(type(value, field), x)
    end
    listeners = filter(l -> l isa AbstractPlanListener, last.(Observables.listeners(value[field])))
    if !isempty(listeners)
      listenerDict[string(field)] = toDictValue(typeof(listeners), listeners)
    end
  end

  if !isempty(listenerDict) 
    dict[LISTENER_TAG] = listenerDict
  end
  
  return dict
end

export loadPlan
loadPlan(m::Module, name::AbstractString, modules::Vector{Module}) = loadPlan(planpath(m, name), modules)
"""
    loadPlan(filename::Union{AbstractString, IO}, modules::Vector{Module})
  
Load a `RecoPlan` from a TOML file. The `modules` argument is a vector of modules that contain the types used in the plan.
After loading the plan, the listeners are attached to the properties using `loadListener!`.
"""
function loadPlan(filename::String, modules)
  open(filename) do io
    return loadPlan(io, modules)
  end
end
function loadPlan(filename::IO, modules::Vector{Module})
  dict = TOML.parse(filename)
  modDict = createModuleDataTypeDict(modules)
  plan = loadPlan!(dict, modDict)
  loadListeners!(plan, dict, modDict)
  return plan
end
function createModuleDataTypeDict(modules::Vector{Module})
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
  return modDict
end
function loadPlan!(dict::Dict{String, Any}, modDict)
  re = r"RecoPlan\{(.*)\}"
  m = match(re, dict[TYPE_TAG])
  if !isnothing(m)
    type = m.captures[1]
    mod = dict[MODULE_TAG]
    plan = RecoPlan(modDict[mod][type])
    loadPlan!(plan, dict, modDict)
    return plan
  else
    # Has to be parameter or algo or broken toml
    # TODO implement
    error("Not implemented yet")
  end
end
function loadPlan!(plan::RecoPlan{T}, dict::Dict{String, Any}, modDict) where {T<:AbstractImageReconstructionAlgorithm}
  temp = loadPlan!(dict["parameter"], modDict)
  parent!(temp, plan)
  setproperty!(plan, :parameter, temp)
  return plan
end
function loadPlan!(plan::RecoPlan{T}, dict::Dict{String, Any}, modDict) where {T<:AbstractImageReconstructionParameters}
  for name in propertynames(plan)
    t = type(plan, name)
    param = missing
    key = string(name)
    if haskey(dict, key)
      if t <: AbstractImageReconstructionAlgorithm || t <: AbstractImageReconstructionParameters
        param = loadPlan!(dict[key], modDict)
        parent!(param, plan)
      elseif t <: Vector{<:AbstractImageReconstructionAlgorithm} || t <: Vector{<:AbstractImageReconstructionParameters}
        param = map(x-> loadPlan!(x, modDict), dict[key])
        foreach(p -> parent!(p, plan), param)
      else
        param = loadPlanValue(T, name, t, dict[key], modDict)
      end
    end
    setproperty!(plan, name, param)
  end
  return plan
end
loadPlanValue(parent::Type{T}, field::Symbol, type, value, modDict) where T <: AbstractImageReconstructionParameters = loadPlanValue(type, value, modDict)
# Type{<:T} where {T}
function loadPlanValue(t::UnionAll, value::Dict, modDict)
  if value[TYPE_TAG] == string(Type)
    return modDict[value[MODULE_TAG]][value[VALUE_TAG]]
  else
    return fromTOML(specializeType(t, value, modDict), value)
  end
end
function loadPlanValue(::Type{Vector{<:T}}, value::Vector{Dict}, modDict) where {T}
  result = Any[]
  for val in value
    type = modDict[val[MODULE_TAG]][val[TYPE_TAG]]
    push!(result, fromTOML(type, val))
  end
  # Narrow vector
  return identity.(result)
end
uniontypes(t::Union) = Base.uniontypes(t)
#uniontypes(t::Union) = [t.a, uniontypes(t.b)...]
#uniontypes(t::DataType) = [t]
function loadPlanValue(t::Union, value::Dict, modDict)
  types = uniontypes(t)
  idx = findfirst(x-> string(x) == value[UNION_TYPE_TAG], types)
  if isnothing(idx)
    toml = tomlType(value, modDict, prefix = "union")
    idx = !isnothing(toml) ? findfirst(x-> toml <: x, types) : idx # Potentially check if more than one fits and chose most fitting
  end
  type = isnothing(idx) ? t : types[idx]
  return loadPlanValue(type, value[VALUE_TAG], modDict)
end
loadPlanValue(t::DataType, value::Dict, modDict) = fromTOML(specializeType(t, value, modDict), value)
loadPlanValue(t, value, modDict) = fromTOML(t, value)

function tomlType(dict::Dict, modDict; prefix::String = "")
  if haskey(dict, "_$(prefix)module") && haskey(dict, "_$(prefix)type")
    mod = dict["_$(prefix)module"]
    type = dict["_$(prefix)type"]
    if haskey(modDict, mod) && haskey(modDict[mod], type)
      return modDict[mod][type]
    end
  end
  return nothing
end
function specializeType(t::Union{DataType, UnionAll}, value::Dict, modDict)
  if isconcretetype(t)
    return t
  end
  type = tomlType(value, modDict)
  return !isnothing(type) && type <: t ? type : t 
end

loadListeners!(plan, dict, modDict) = loadListeners!(plan, plan, dict, modDict)
function loadListeners!(root::RecoPlan, plan::RecoPlan{T}, dict, modDict) where {T<:AbstractImageReconstructionAlgorithm}
  loadListeners!(root, plan.parameter, dict["parameter"], modDict)
end
function loadListeners!(root::RecoPlan, plan::RecoPlan{T}, dict, modDict) where {T<:AbstractImageReconstructionParameters}
  if haskey(dict, LISTENER_TAG)
    for (property, listenerDicts) in dict[LISTENER_TAG]
      for listenerDict in listenerDicts
        loadListener!(plan, Symbol(property), listenerDict, modDict)
      end
    end
  end
  for property in propertynames(plan)
    value = getproperty(plan, property)
    if value isa RecoPlan
      loadListeners!(root, value, dict[string(property)], modDict)
    end
  end
end
export loadListener
"""
    loadListener!(plan, name::Symbol, dict, modDict)

Load a listener from `dict` and attach it to property `name` of `plan`
"""
function loadListener!(plan, name::Symbol, dict, modDict)
  type = tomlType(dict, modDict)
  return loadListener!(type, plan, name, dict, modDict)
end

fromTOML(t, x) = x
function fromTOML(::Type{Nothing}, x::Dict) #where {T}
  if isempty(x)
    return nothing
  end
  error("Unexpected value $x for Nothing, expected empty Dict")
end
fromTOML(::Type{V}, x::Vector) where {T, V<:Vector{<:T}} = fromTOML.(T, x)
