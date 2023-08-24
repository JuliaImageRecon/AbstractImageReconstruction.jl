export AbstractImageReconstructionAlgorithm
abstract type AbstractImageReconstructionAlgorithm end

export AbstractImageReconstructionParameters
abstract type AbstractImageReconstructionParameters end

export put!, take!
put!(algo::AbstractImageReconstructionAlgorithm, data) = error("$(typeof(algo)) must implement put!")
take!(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement take!")

export reconstruct
function reconstruct(algo::T, u) where {T<:AbstractImageReconstructionAlgorithm}
  put!(algo, u)
  return take!(algo)
end

export process
# process(algoT::Type{T}, ...) as pure helper functions
# Overwrite process(algo, ...) to mutate struct based on helper function result
process(algoT::Type{T}, data, param::AbstractImageReconstructionParameters) where {T<:AbstractImageReconstructionAlgorithm} = error("No processing defined for algorithm $T with parameter $(typeof(param))")
process(algo::AbstractImageReconstructionAlgorithm, data, param::AbstractImageReconstructionParameters) = process(typeof(algo), data, param)

"""
Enable multiple process steps by supplying a Vector of parameters
"""
function process(algo::AbstractImageReconstructionAlgorithm, data, params::Vector{<:AbstractImageReconstructionParameters})
  val = process(algo, data, first(params))
  for param ∈ Iterators.drop(params, 1)
    val = process(algo, val, param)
  end
  return val
end

export parameter
parameter(algo::AbstractImageReconstructionAlgorithm) = error("$(typeof(algo)) must implement parameter")