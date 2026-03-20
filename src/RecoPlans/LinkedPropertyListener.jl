export LinkedPropertyListener
mutable struct LinkedPropertyListener{T<:AbstractImageReconstructionParameters} <: AbstractPlanListener
  plan::RecoPlan{T}
  field::Symbol
  fn::Function
  active::Bool
end

"""
    LinkedPropertyListener(fn, target::RecoPlan, targetProp, source::RecoPlan, sourceProp)

Connect two properties of `RecoPlans`. Set `target.targetProp` to `fn(source.sourceProp)` whenever `source.sourceProp` changes and `target.targetProp` was not changed outside of the listener.  
"""
function LinkedPropertyListener(fn::Function, target::RecoPlan, targetProp::Symbol, source::RecoPlan, sourceProp::Symbol)
  listener = LinkedPropertyListener(source, sourceProp, fn, true)

  # Attach the listener to the target property
  # We can serialize the listener from the target property and store the source property
  on(listener, target, targetProp)

  # Attach callback to the source property
  on(source, sourceProp) do x
    if listener.active
      setproperty!(target, targetProp, fn(x))
      # Set active to true again, because the flag is changed by the target listener
      listener.active = true
    end
  end

  return listener
end
(listener::LinkedPropertyListener)(val) = listener.active = false


function StructUtils.lower(::RecoPlanStyle, value::LinkedPropertyListener)
  T = typeof(value)
  dict = Dict{String, Any}(
    MODULE_TAG => string(parentmodule(T)),
    TYPE_TAG => string(getfield(parentmodule(T), nameof(T)))
  )
  # Path from root to the source plan, as strings
  dict["plan"] = string.(parentproperties(value.plan))
  # Source field
  dict["field"] = string(value.field)
  # Function: use existing Function lowering (MODULE_TAG/TYPE_TAG)
  dict["fn"] = StructUtils.lower(RecoPlanStyle(), value.fn)
  return dict
end

function loadListener!(::Type{LinkedPropertyListener}, target::RecoPlan, targetProp, dict::Dict{String, Any})

  # Find the root plan
  root = parent(target)
  while !isnothing(parent(root))
      root = parent(root)
  end

  # Walk the recorded path to find the source plan
  source = root
  for name_str in dict["plan"]
      source = getproperty(source, Symbol(name_str))
  end
  sourceProp = Symbol(dict["field"])

  # Reconstruct the function from MODULE_TAG/TYPE_TAG
  fn_dict = dict["fn"]
  mod_str  = fn_dict[MODULE_TAG]
  type_str = fn_dict[TYPE_TAG]
  fn = MODULE_DICT[mod_str, type_str]
  if fn === nothing
      error("Could not resolve function $(type_str) from module $(mod_str) " *
            "when loading LinkedPropertyListener")
  end
  return LinkedPropertyListener(fn, target, targetProp, source, sourceProp)
end