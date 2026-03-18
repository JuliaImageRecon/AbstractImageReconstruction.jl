# API for Solvers
This page contains documentation of the public API of the AbstractImageReconstruction. In the Julia
REPL one can access this documentation by entering the help mode with `?`

## Algorithm and Parameters
```@docs
AbstractImageReconstruction.AbstractImageReconstructionAlgorithm
AbstractImageReconstruction.@reconstruction
AbstractImageReconstruction.reconstruct
AbstractImageReconstruction.AbstractImageReconstructionParameters
AbstractImageReconstruction.@parameter
AbstractImageReconstruction.validate!
```

The above functions are all that is required to implement when using the provided macros.
For custom structs without the macros, it's also necessary to implement the following functions:

```@docs
Base.put!(::AbstractImageReconstructionAlgorithm, ::Any)
Base.take!(::AbstractImageReconstructionAlgorithm)
Base.lock(::AbstractImageReconstructionAlgorithm)
Base.unlock(::AbstractImageReconstructionAlgorithm)
Base.isready(::AbstractImageReconstructionAlgorithm)
Base.wait(::AbstractImageReconstructionAlgorithm)
AbstractImageReconstruction.parameter
```

## RecoPlan
```@docs
AbstractImageReconstruction.RecoPlan
Base.propertynames(::RecoPlan)
Base.getproperty(::RecoPlan, ::Symbol)
Base.getindex(::RecoPlan, ::Symbol)
Base.setproperty!(::RecoPlan, ::Symbol, ::Any)
AbstractImageReconstruction.setAll!
AbstractImageReconstruction.clear!
Base.ismissing(::RecoPlan, ::Symbol)
Observables.on(::Any, ::RecoPlan, ::Symbol)
Observables.off(::RecoPlan, ::Symbol, ::Any)
AbstractImageReconstruction.build
AbstractImageReconstruction.toPlan
AbstractImageReconstruction.savePlan
AbstractImageReconstruction.loadPlan
AbstractImageReconstruction.loadListener!
AbstractImageReconstruction.parent(::RecoPlan)
AbstractImageReconstruction.parent!(::RecoPlan, ::AbstractRecoPlan)
AbstractImageReconstruction.parentproperty
AbstractImageReconstruction.parentproperties
```

## Miscellaneous
```@docs
AbstractImageReconstruction.LinkedPropertyListener
AbstractImageReconstruction.ProcessResultCache
Base.hash(::AbstractImageReconstructionParameters, ::UInt64)
AbstractImageReconstruction.toKwargs(::AbstractImageReconstructionParameters)
AbstractImageReconstruction.fromKwargs
AbstractImageReconstruction.toDict
AbstractImageReconstruction.toDict!
AbstractImageReconstruction.toDictValue
AbstractImageReconstruction.toDictValue!
```
