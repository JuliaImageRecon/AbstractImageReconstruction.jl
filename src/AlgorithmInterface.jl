export AbstractImageReconstructionAlgorithm
"""
    AbstractImageReconstructionAlgorithm

Abstract type for image reconstruction algorithms. Must implement `put!` and `take!` functions. Serialization expects a constructor with a single `AbstractImageReconstructionParameters` argument.
"""
abstract type AbstractImageReconstructionAlgorithm end

export AbstractImageReconstructionParameters
"""
    AbstractImageReconstructionParameters

Abstract type for image reconstruction parameters.  An algorithm consists of one ore more `process` steps, each can have its own parameters. Parameters can be arbitrarly nested. 
"""
abstract type AbstractImageReconstructionParameters end

export AbstractUtilityReconstructionParameters
"""
    AbstractUtilityReconstructionParameters{T <: AbstractImageReconstructionParameters}

Abstract type that offer utility functions for a given reconstruction parameter and its associated `process` steps. Utility `process` steps should return the same result as `T` for the same inputs.
"""
abstract type AbstractUtilityReconstructionParameters{T <: AbstractImageReconstructionParameters} <: AbstractImageReconstructionParameters end

export put!, take!
"""
    put!(algo::AbstractImageReconstructionAlgorithm, inputs...)

Perform image reonstruction with algorithm `algo` on given `ìnputs`. Depending on the algorithm this might block. Result is stored and can be retrieved with `take!`.
"""
put!(algo::AbstractImageReconstructionAlgorithm, inputs...) = error("$(typeof(algo)) must implement put!")
"""
    take!(algo::AbstractImageReconstructionAlgorithm)

Remove and return a stored result from the algorithm `algo`. Blocks until a result is available.
"""
take!(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement take!")
"""
    isready(algo::AbstractImageReconstructionAlgorithm)

Determine if the algorithm `algo` has a result available.
"""
isready(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement isready")
"""
    wait(algo::AbstractImageReconstructionAlgorithm)

Wait for a result to be available from the specified `algo`.
"""
wait(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement wait")
"""
    lock(algo::AbstractImageReconstructionAlgorithm)

Acquire a lock on the algorithm `algo`. If the lock is already acquired, wait until it is released.

Each `lock` must be matched with a `unlock`.
"""
lock(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement lock")
"""
    unlock(algo::AbstractImageReconstructionAlgorithm)

Release a lock on the algorithm `algo`.
"""
unlock(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement unlock")
"""
    lock(fn, algo::AbstractImageReconstructionAlgorithm)

Acquire the `lock` on `algo`, execute `fn` and release the `lock` afterwards.
"""
function lock(fn, algo::AbstractImageReconstructionAlgorithm)
  lock(algo)
  try
    fn()
  finally
    unlock(algo)
  end
end

export reconstruct
"""
    reconstruct(algo::T, u) where {T<:AbstractImageReconstructionAlgorithm}

Reconstruct an image from input `u` using algorithm `algo`. The `àlgo` will be `lock`ed until the result is available or an error occurs.
"""
function reconstruct(algo::T, u) where {T<:AbstractImageReconstructionAlgorithm}
  lock(algo) do
    put!(algo, u)
    return take!(algo)
  end
end

export process
# process(algoT::Type{T}, ...) as pure helper functions
# Overwrite process(algo, ...) to mutate struct based on helper function result
"""
    process(algo::Union{A, Type{A}}, param::AbstractImageReconstructionParameters, inputs...) where A <: AbstractImageReconstructionAlgorithm

Process `inputs` with algorithm `algo` and parameters `param`. Returns the result of the processing step.
If not implemented for an instance of `algo`, the default implementation is called with the type of `algo`.
"""
function process end
process(algo::AbstractImageReconstructionAlgorithm, param::AbstractImageReconstructionParameters, inputs...) = process(typeof(algo), param, inputs...)
"""
    process(algo::Union{A, Type{A}}, param::AbstractUtilityReconstructionParameters{P}, inputs...) where {A <: AbstractImageReconstructionAlgorithm, P <: AbstractImageReconstructionParameters}

Process `inputs` with algorithm `algo` and return the result as if the arguments were given to `P`. Examples of utility `process` are processes which offer caching or remote execution. 
"""
process(::A, param::AbstractUtilityReconstructionParameters{P}, inputs...) where {A, P} = error("$(typeof(param)) must implement `process` for $A and given inputs")
"""
Enable multiple process steps by supplying a Vector of parameters
"""
function process(algo::AbstractImageReconstructionAlgorithm, params::Vector{<:AbstractImageReconstructionParameters}, inputs...)
  val = process(algo, first(params), inputs...)
  for param ∈ Iterators.drop(params, 1)
    val = process(algo, val, param)
  end
  return val
end

export parameter
"""
    parameter(algo::AbstractImageReconstructionAlgorithm)

Return the parameters of the algorithm `algo`.
"""
parameter(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement `parameter`")
"""
    parameter(param::AbstractUtilityReconstructionParameters)
  
Return the wrapped parameter. Can themselves be utility parameters again
"""
parameter(param::AbstractUtilityReconstructionParameters) = error("$(typeof(param)) must implement `parameter`")