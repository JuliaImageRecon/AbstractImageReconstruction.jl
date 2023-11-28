export TransientListener, SerializableListener
abstract type TransientListener <: AbstractPlanListener end
abstract type SerializableListener <: AbstractPlanListener end

const LISTENER_TAG = "_listener"

export propertyupdate!, valueupdate 
function propertyupdate!(listener::AbstractPlanListener, origin, field, old, new)
  # NOP
end
function valueupdate(listener::AbstractPlanListener, origin, field, old, new)
  # NOP
end

export getlisteners, addListener!, removeListener!
getlisteners(plan::RecoPlan, field::Symbol) = getfield(plan, :listeners)[field]
function addListener!(plan::RecoPlan, field::Symbol, listener::AbstractPlanListener)
  listeners = getlisteners(plan, field)
  push!(listeners, listener)
end
function removeListener!(plan::RecoPlan, field::Symbol, listener::AbstractPlanListener)
  listeners = getlisteners(plan, field)
  idx = findall(x->isequal(x, listener), listeners)
  isnothing(idx) && deleteat!(listeners, idx)
end