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
# In AbstractImageReconstruction.jl, reconstruction algorithms are driven by *parameters*. Parameters are callable objects that implement individual processing steps.
# A parameter type `MyParams` is expected to implement one of:
# ```julia
#   (param::MyParams)(::Type{<:MyAlgorithm}, inputs...)
#   (param::MyParams)(algo::MyAlgorithm,      inputs...)
# ```
# The type-based variant is preferred for pure functions; the instance-based variant allows mutation of the algorithm state. The default implementation of
# ```julia
#   (param::AbstractImageReconstructionParameters)(algo::AbstractImageReconstructionAlgorithm, inputs...) = param(algo, inputs...) → param(typeof(algo), inputs...)
# ```
# simply forwards to the type-based method.

# A reconstruction algorithm typically stores a *main* parameter. Multiple processing steps can be encoded by
# composing parameter calls; there is no requirement to implement a strict linear pipeline.

# To extend an exisiting algorithm with new behaviour, it's enough to implement new parameters or potentially add an algorithm.
# Later one, we will see more infrastructure of the package which focuses on parameters and their Configuration.

# Let's define a preprocessing step that we can share between our algorithms. We want to
# allow the user to select certain frames from a time series and average them. We will use
# the `@parameter` macro. This is similar to `Base.@kwdef` and allows us to provide a constructor with keyword arguments and default values.
# It also allows us to validate the values of our parameters:
using Statistics
@parameter struct RadonPreprocessingParameters <: AbstractRadonPreprocessingParameters
  frames::Vector{Int64} = []
  numAverages::Int64 = 1

  @validate begin
    @assert numAverages >= 0 "Averages must be a positive integer"
  end
end
function (params::RadonPreprocessingParameters)(::Type{<:AbstractRadonAlgorithm}, data::AbstractArray{T, 4}) where {T}
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
# However, much of this boilerplate can be created via macros, as we will see in this example.