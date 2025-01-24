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


function toDictValue!(dict, value::LinkedPropertyListener)
  dict["plan"] = string.(parentproperties(value.plan))
  dict["field"] = string(value.field)
  dict["fn"] = toDict(value.fn)
end

function loadListener!(::Type{LinkedPropertyListener}, target::RecoPlan, targetProp, dict, modDict)
  # Find the root plan
  root = parent(target)
  while !isnothing(parent(root))
    root = parent(root)
  end

  # From the root plan, find the source plan
  source = root
  for param in dict["plan"][1:end]
    source = getproperty(source, Symbol(param))
  end
  sourceProp = Symbol(dict["field"])

  # Retrieve the function
  fn = tomlType(dict["fn"], modDict)
  return LinkedPropertyListener(fn, target, targetProp, source, sourceProp)
end