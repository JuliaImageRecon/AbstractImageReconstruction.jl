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

export reconstruct
"""
    reconstruct(algo::T, u) where {T<:AbstractImageReconstructionAlgorithm}

Reconstruct an image from input `u` using algorithm `algo`.
"""
function reconstruct(algo::T, u) where {T<:AbstractImageReconstructionAlgorithm}
  put!(algo, u)
  return take!(algo)
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
parameter(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement parameter")