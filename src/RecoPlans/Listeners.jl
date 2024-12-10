export AbstractPlanListener
abstract type AbstractPlanListener end

const LISTENER_TAG = "_listener"

Observables.on(f, plan::RecoPlan, field::Symbol; kwargs...) = on(f, getfield(plan, :values)[field]; kwargs...)
Observables.off(plan::RecoPlan, field::Symbol, f) = off(f, getfield(plan, :values)[field])

include("LinkedPropertyListener.jl")