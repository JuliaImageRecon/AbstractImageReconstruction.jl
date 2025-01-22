include("../../literate/example/1_interface.jl") #hide
using RadonKA #hide
export AbstractDirectRadonReconstructionParameters, RadonFilteredBackprojectionParameters, RadonBackprojectionParameters, DirectRadonParameters, DirectRadonAlgorithm #hide

# # Direct Reconstruction
# To implement our direct reconstruction algorithms we need to define a few more methods and types. We will start by defining the parameters for the backprojection and for the filtered backprojection. Afterwards we can implement the algorithm itself.

# ## Parameters and Processing
# For convenience we first introduce a new abstract type for the direct reconstruction paramters:
abstract type AbstractDirectRadonReconstructionParameters <: AbstractRadonReconstructionParameters end
# The backprojection parameters are simple and only contain the number of angles:
Base.@kwdef struct RadonBackprojectionParameters <: AbstractDirectRadonReconstructionParameters
  angles::Vector{Float64}
end

# The filtered backprojection parameters are more complex and contain the number of angles and optionally the filter which should be used:
Base.@kwdef struct RadonFilteredBackprojectionParameters <: AbstractDirectRadonReconstructionParameters
  angles::Vector{Float64}
  filter::Union{Nothing, Vector{Float64}} = nothing
end
# Since we have defined no default values for the angles, they are required to be set by the user. A more advanced implementation would also allow for the geometry to be set.

# Next we will implement the process steps for both of our backprojection variants. Since RadonKA.jl expects 2D or 3D arrays we have to transform our time series accordingly.
function AbstractImageReconstruction.process(algoT::Type{<:AbstractDirectRadonAlgorithm}, params::AbstractDirectRadonReconstructionParameters, data::AbstractArray{T, 4}) where {T}
  result = []
  for i = 1:size(data, 4)
    push!(result, process(algoT, params, view(data, :, :, :, i)))
  end
  return cat(result..., dims = 4)
end
AbstractImageReconstruction.process(::Type{<:AbstractDirectRadonAlgorithm}, params::RadonBackprojectionParameters, data::AbstractArray{T, 3}) where {T} = RadonKA.backproject(data, params.angles)
AbstractImageReconstruction.process(::Type{<:AbstractDirectRadonAlgorithm}, params::RadonFilteredBackprojectionParameters, data::AbstractArray{T, 3}) where {T} = RadonKA.backproject_filtered(data, params.angles; filter = params.filter)

# ## Algorithm
# The direct reconstruction algorithm has essentially no state to store between reconstructions and thus only needs its parameters as fields. We want our algorithm to accept any combination of our preprocessing and direct reconstruction parameters.
# This we encode in a new type:
Base.@kwdef struct DirectRadonParameters{P <: AbstractRadonPreprocessingParameters, R <: AbstractDirectRadonReconstructionParameters} <: AbstractRadonParameters
  pre::P
  reco::R
end
# And the according processing step:
function AbstractImageReconstruction.process(algoT::Type{<:AbstractDirectRadonAlgorithm}, params::DirectRadonParameters{P, R}, data::AbstractArray{T, 4}) where {T, P<:AbstractRadonPreprocessingParameters, R<:AbstractDirectRadonReconstructionParameters}
  data = process(algoT, params.pre, data)
  return process(algoT, params.reco, data)
end

# Now we can define the algorithm type itself. Algorithms are usually constructed with one argument passing in the user parameters:
mutable struct DirectRadonAlgorithm{D <: DirectRadonParameters} <: AbstractDirectRadonAlgorithm
  parameter::D
  output::Channel{Any}
  DirectRadonAlgorithm(parameter::D) where D = new{D}(parameter, Channel{Any}(Inf))
end
# And they implement a method to retrieve the used parameters:
AbstractImageReconstruction.parameter(algo::DirectRadonAlgorithm) = algo.parameter

# Algorithms are assumed to be stateful. To ensure thread safety, we need to implement the `lock` and `unlock` functions. We will use the `output` channel as a lock:
Base.lock(algo::DirectRadonAlgorithm) = lock(algo.output)
Base.unlock(algo::DirectRadonAlgorithm) = unlock(algo.output)

# And implement the `put!` and `take!` functions, mimicking the behavior of a FIFO channel for reconstructions:
Base.take!(algo::DirectRadonAlgorithm) = Base.take!(algo.output)
function Base.put!(algo::DirectRadonAlgorithm, data::AbstractArray{T, 4}) where {T} 
  lock(algo) do
    put!(algo.output, process(algo, algo.parameter, data))
  end
end

# The way the behaviour is implemented here, the algorithm does not buffer any inputs and instead blocks until the currenct reconstruction is done. Outputs are stored until they are retrieved.

# With `wait` and `isready` we can check if the algorithm is currently processing data or if it is ready to accept new inputs:
Base.wait(algo::DirectRadonAlgorithm) = wait(algo.output)
Base.isready(algo::DirectRadonAlgorithm) = isready(algo.output)