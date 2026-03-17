include("../../literate/example/example_include_all.jl") #hide

# # Observables
# Observables from [Observables.jl](https://github.com/JuliaGizmos/Observables.jl) are containers which can invoke callbacks whenever their stored value is changed.
# Each property of a `RecoPlan` is an `Òbservable` to which functions can be attached. These function listen to changes of the Observables value.
# This can be used to store "logic" about the parameter within a plan, such as a function to update and visualize the current state of a plan or to calculate default values whenever a parameter changes.

# In this documentation we will focus on the interaction between `RecoPlans` and `Observables`. For more details on the `Observables` API we refer to the [package](https://juliagizmos.github.io/Observables.jl/stable/) and [Makie](https://docs.makie.org/stable/explanations/observables) documentation.
using Observables
plan = RecoPlan(DirectRadonAlgorithm; parameter = RecoPlan(DirectRadonParameters; 
        pre = RecoPlan(RadonPreprocessingParameters; frames = collect(1:3)), 
        reco = RecoPlan(RadonBackprojectionParameters; angles = angles)))

# You can interact with parameters as if they are "normal" properties of a nested struct, which we shown in previous examples:
length(plan.parameter.pre.frames) == 3

# Internally, these properties are stored as `Observables` to which we can attach functions:
on(plan.parameter.pre, :frames) do val
  @info "Number of frames: $(length(val))"
end
setAll!(plan, :frames, collect(1:42))

# Clearing the plan also resets the `Observables` and removes all listeners:
clear!(plan)
setAll!(plan, :frames, collect(1:3))
plan.parameter.pre.frames

# To directly access the Observable of a property you can use `getindex` on the plan with the property name:
plan.parameter.pre[:frames]

# `Observables` can also be used to connect two properties of a plan. For example, we can set the number of averages to the number of frames:
on(plan.parameter.pre, :frames) do val
  plan.parameter.pre.numAverages = length(val)
end
setAll!(plan, :frames, collect(1:42))
plan.parameter.pre.numAverages

# It is important to avoid circular dependencies when connecting Observables, as this can lead to infinite loops of callbacks.
# Also note that the connection shown above will always overwrite the number of averages even if a user has set the value manually:
plan.parameter.pre.numAverages = 5
setAll!(plan, :frames, collect(1:42))
plan.parameter.pre.numAverages

# To connect two properties without overwriting user-prvided values, we can use the `LinkedPropertyListener` provided by `AbstractImageReconstruction`:
clear!(plan)
listener = LinkedPropertyListener(plan.parameter.pre, :numAverages, plan.parameter.pre, :frames) do val
  @info "Setting default numAverages value to: $(length(val))"
  return length(val)
end
plan.parameter.pre.frames = collect(1:42)
plan.parameter.pre.numAverages = 1
plan.parameter.pre.frames = collect(1:3)

# The `LinkedPropertyListener` can also be serialized and deserialized with the plan. However, for the function to be properly serialized, it should be a named function:
clear!(plan)
defaultAverages(val) = length(val)
LinkedPropertyListener(defaultAverages, plan.parameter.pre, :numAverages, plan.parameter.pre, :frames)
plan.parameter.pre.frames = collect(1:42)
@info plan.parameter.pre.numAverages == 42
toTOML(stdout, plan)

# To serialize custom listener one can inherit from `AbstractPlanListener` and follow the serialization How-To to implement the serialization.
# Listener are deserialized after the plan is built and the parameters are set. This means that the listener can access the parameters of the plan and the plan itself.
# For deserialization the listener has to implement `loadListener!(::Type{<:AbstractPlanListener}, plan::RecoPlan, field::Symbol, dict::Dict{String, Any}, args...)`.