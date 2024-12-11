# API for Solvers
This page contains documentation of the public API of the AbstractImageReconstruction. In the Julia
REPL one can access this documentation by entering the help mode with `?`

## Algorithm and Parameters
```@docs
AbstractImageReconstruction.AbstractImageReconstructionAlgorithm
AbstractImageReconstruction.reconstruct
Base.put!(::AbstractImageReconstructionAlgorithm, ::Any)
Base.take!(::AbstractImageReconstructionAlgorithm)
AbstractImageReconstruction.AbstractImageReconstructionParameters
AbstractImageReconstruction.process
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
AbstractImageReconstruction.parent!(::RecoPlan, ::RecoPlan)
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
