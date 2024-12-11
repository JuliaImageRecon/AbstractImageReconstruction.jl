export AbstractPlanListener
"""
    AbstractPlanListener

Abstract type for listeners that can be attached to `RecoPlans` and are serialized together with the plan.
Structs implementing this type must be function-like-objects that take a single argument for the `Observable` callback.
"""
abstract type AbstractPlanListener end

const LISTENER_TAG = "_listener"

"""
    on(f, plan::RecoPlan, property::Symbol; kwargs...)
  
Adds function `f` as listener to `property` of `plan`. The function is called whenever the property is changed with `setproperty!`.
"""
Observables.on(f, plan::RecoPlan, property::Symbol; kwargs...) = on(f, plan[property]; kwargs...)
"""
    off(plan::RecoPlan, property::Symbol, f)

Remove `f` from the listeners of `property` of `plan`.
"""
Observables.off(plan::RecoPlan, property::Symbol, f) = off(f, plan[property])

include("LinkedPropertyListener.jl")