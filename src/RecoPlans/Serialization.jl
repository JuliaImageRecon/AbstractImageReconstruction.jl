export plandir, planpath
function plandir(m::Module)
  if m != AbstractImageReconstruction && hasproperty(m, :plandir)
    return getproperty(m, :plandir)()
  else
    return @get_scratch!(string(m))
  end
end
planpath(m::Module, name::AbstractString) = joinpath(plandir(m), string(name, ".toml"))

export savePlan
savePlan(filename::AbstractString, plan::RecoPlan) = toTOML(filename, plan)
savePlan(m::Module, planname::AbstractString, plan::RecoPlan) = savePlan(planpath(m, planname), plan)

toDictModule(plan::RecoPlan{T}) where {T} = parentmodule(T)
toDictType(plan::RecoPlan{T}) where {T} = RecoPlan{getfield(parentmodule(T), nameof(T))}
function addDictValue!(dict, value::RecoPlan)
  for field in propertynames(value)
    x = getproperty(value, field)
    if !ismissing(x)
      dict[string(field)] = toDictValue(type(value, field), x)
    end
  end
  listeners = filter(x-> !isempty(last(x)), getfield(value, :listeners))
  if !isempty(listeners)
    listenerDict = Dict{String, Any}()
    for (field, l) in listeners
      serializable = filter(x-> x isa SerializableListener, l)
      if !isempty(serializable)
        listenerDict[string(field)] = toDictValue(typeof(l), l)
      end
    end
    if !isempty(listenerDict) 
      dict[LISTENER_TAG] = listenerDict
    end
  end
  return dict
end

export loadPlan
loadPlan(m::Module, name::AbstractString, modules::Vector{Module}) = loadPlan(planpath(m, name), modules)
function loadPlan(filename::AbstractString, modules::Vector{Module})
  dict = TOML.parsefile(filename)
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
          typeDict[string(t)] = t
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
  setvalue!(plan, :parameter, temp)
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
      else
        param = loadPlanValue(T, name, t, dict[key], modDict)
      end
    end
    setvalue!(plan, name, param)
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
function loadPlanValue(::Type{Vector{<:T}}, value::Vector, modDict) where {T}
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
  if haskey(dict, ".listener")
    for (property, listenerDicts) in dict[".listener"]
      for listenerDict in listenerDicts
        listener = loadListener(root, listenerDict, modDict)
        addListener!(plan, Symbol(property), listener)
      end
    end
  end
  for property in propertynames(plan)
    value = plan[property]
    if value isa RecoPlan
      loadListeners!(root, value, dict[string(property)], modDict)
    end
  end
end
export loadListener
function loadListener(root, dict, modDict)
  type = tomlType(dict, modDict)
  return loadListener(type, root, dict, modDict)
end

fromTOML(t, x) = x
function fromTOML(::Type{Nothing}, x::Dict) #where {T}
  if isempty(x)
    return nothing
  end
  error("Unexpected value $x for Nothing, expected empty Dict")
end
fromTOML(::Type{V}, x::Vector) where {T, V<:Vector{<:T}} = fromTOML.(T, x)
