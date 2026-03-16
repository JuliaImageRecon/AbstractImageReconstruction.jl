# # Interface
# This section introduces the abstract types we need to implement for our reconstruction package and how they relate to interface and types of AbstractImageReconstruction.jl.

# ## Abstract Types
# We start by defining the abstract types we need to implement for our reconstruction package. AbstractImageReconstruction.jl provides two abstract types:
# ```julia
# abstract type AbstractImageReconstructionAlgorithm end
# abstract type AbstractImageReconstructionParameters end
# ```
# `AbstractImageReconstructionAlgorithms` represent a given reconstruction algorithm, while `AbstractImageReconstructionParameters` represent the parameters an algorithm was constructed with.
# Once constructed, algorithms can be used to reconstruct images repeatly and idealy without unecessary recomputations. 

# For our package we extend these abstract types with our own abstract subtypes:
using AbstractImageReconstruction
export AbstractRadonAlgorithm, AbstractRadonParameters, AbstractRadonPreprocessingParameters, AbstractRadonReconstructionParameters, AbstractDirectRadonAlgorithm, AbstractIterativeRadonAlgorithm, RadonPreprocessingParameters # hide
abstract type AbstractRadonAlgorithm <: AbstractImageReconstructionAlgorithm end
abstract type AbstractRadonParameters <: AbstractImageReconstructionParameters end

# Later on we will have parameters that are shared between different algorithms and parameters for different processings steps of a reconstruction.
# In our case we will have preprocessing parameters and reconstruction parameters. For these we introduce the following abstract types:
abstract type AbstractRadonPreprocessingParameters <: AbstractRadonParameters end
abstract type AbstractRadonReconstructionParameters <: AbstractRadonParameters end

# Since we want to implement both direct and iterative methods for our reconstruction, we introduce the following abstract types:
abstract type AbstractDirectRadonAlgorithm <: AbstractRadonAlgorithm end
abstract type AbstractIterativeRadonAlgorithm <: AbstractRadonAlgorithm end

# ## Internal Interface
# Reconstruction algorithms in AbstractImageReconstruction.jl are expected to be implemented in the form of distinct processing steps, implemented in their own `process` methods.
# The `process` function takes an algorithm, parameters, and inputs and returns the result of the processing step.
# If no function is defined for an instance of an algorithm, the default implementation is called. This method tries to call the function `process` with the type of the algorithm:
# ```julia
# process(algo::AbstractImageReconstructionAlgorithm, param::AbstractImageReconstructionParameters, inputs...) = process(typeof(algo), param, inputs...)
# ```
# The implementation of reconstruction algorithms is therefore expected to either implement the `process` function for the algorithm type or for the instance. Dispatch on instances allow an instance to change its state, while dispatch on types allows for pure helper functions.

# A `process` itself can invoke other `process` functions to enable multiple processing steps and generally have arbitarry control flow. It is not required to implement a straight-foward pipeline. We will see this later when we implementd our algorithms.

# Let's define a preprocessing step that we can share between our algorithms. We want to allow the user to select certain frames from a time series and average them.
# We will use the `@kwdef` macro to provide constructor with keyword arguments and default values
using Statistics
Base.@kwdef struct RadonPreprocessingParameters <: AbstractRadonPreprocessingParameters
  frames::Vector{Int64} = []
  numAverages::Int64 = 1
end
function AbstractImageReconstruction.process(::Type{<:AbstractRadonAlgorithm}, params::RadonPreprocessingParameters, data::AbstractArray{T, 4}) where {T}
  frames = isempty(params.frames) ? (1:size(data, 4)) : params.frames
  data = data[:, :, :, frames]
  
  if params.numAverages > 1
    data = reshape(data, size(data)[1:3]..., params.numAverage, :)
    data = dropdims(mean(data, dims = 4), dims = 4)
  end

  return data
end

# ## User Interface
# A user of our package should be able to reconstruct images by calling the `reconstruct` function. This function takes an algorithm and an input and returns the reconstructed image.
# Internally, the `reconstruct` function calls the `put!` and `take!` functions of the algorithm to pass the input and retrieve the output. Algorithms must implement these functions and are expected to have FIFO behavior.