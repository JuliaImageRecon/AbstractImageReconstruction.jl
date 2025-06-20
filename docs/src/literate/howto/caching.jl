include("../../literate/example/example_include_all.jl") #hide


# # Caching
# Image reconstruction algorithms can be computationally expensive. To avoid unnecessary recomputations, we can cache the results of processing steps.
# This can be especially helpful if a user wants to change parameters of an algorithm that only impact parts of the processing.
# We have seen a small example of caching in the `IterativeRadonAlgorithm` implementation. There the algorithm itself cached a result in its properties.
# `AbstractImageReconstruction` provides a more general caching mechanism that can be used for any processing step. However, the caching mechanism is not enabled by default and has to be explicitly implemented by the algorithm developer.

# This How-To builds on the results of the example sections.

# ## ProcessResultCache
# The caching mechanism is based on the `ProcessResultCache` type. This type wraps around a different `AbstractImageReconstructionParameter` and caches the result of a processing step.
# Such a `process`ing step which offer functionality to other `process` steps is a `AbstractUtilityReconstructionParameter`. These utility steps should return the same result as if the inner step was called directly.

# The cache itself is connected to a `RecoPlan` and any instances build from the same plan instance share this cache and can reuse the result of the processing step.

# Let's implement the `ProcessResultCache` type for the Radon preprocessing step. We first define a struct a very costly preprocessing step:
Base.@kwdef struct CostlyPreprocessingParameters <: AbstractRadonPreprocessingParameters
  frames::Vector{Int64} = []
  runtime::Float64 = 1.0
end
function AbstractImageReconstruction.process(::Type{<:AbstractRadonAlgorithm}, params::CostlyPreprocessingParameters, data::AbstractArray{T, 4}) where {T}
  frames = isempty(params.frames) ? (1:size(data, 4)) : params.frames
  data = data[:, :, :, frames]
  @info "Very costly preprocessing step"
  sleep(params.runtime)
  return data
end

# Now we can define a processing step that internally uses another processing step. We allow this inner parameter to be cached by considering the following `Union`:
Base.@kwdef struct RadonCachedPreprocessingParameters{P <: AbstractRadonPreprocessingParameters, PU <: AbstractUtilityReconstructionParameters{P}} <: AbstractRadonPreprocessingParameters
  params::Union{P, PU}
end
# Note that this case is a bit artifical and a more sensible place would be the algorithm parameters themselves. However, for the case of simplicity we did not introduce the concept in the example.
# In this artifical case we just pass the parameters to the processing step. A real implementation might do some more processing with the result of the inner processing step:
AbstractImageReconstruction.process(algoT::Type{<:AbstractRadonAlgorithm}, params::RadonCachedPreprocessingParameters, args...) = process(algoT, params.params, args...)

# We deliberaly implement the `process` function for algorithm type to avoid our cache being invalided by state changes of an algoritm instance.

# Now we construct a plan for a direct reconstruction algorithm that uses the costly preprocessing step:
pre = CostlyPreprocessingParameters(; frames = collect(1:3), runtime = 1.0)
preCached = RadonCachedPreprocessingParameters(ProcessResultCache(pre, maxsize = 2))
prePlan = toPlan(preCached)
recoPlan = RecoPlan(IterativeRadonReconstructionParameters; angles = angles, shape = size(images)[1:3],
            iterations = 10, reg = [L2Regularization(0.001), PositiveRegularization()], solver = CGNR)
params = RecoPlan(IterativeRadonParameters; pre = prePlan, reco = recoPlan)
plan = RecoPlan(IterativeRadonAlgorithm; parameter = params)

# When we built the algorithm from the plan, the costly preprocessing step is only executed once and the result is cached and can be reused:
algo = build(plan)
reconstruct(algo, sinograms);
reconstruct(algo, sinograms);

# If we change the parameters of the algorithms without affecting the preprocessing step, we can still reuse the cached result:
setAll!(plan, :iterations, 5)
algo = build(plan)
reconstruct(algo, sinograms);
plan.parameter.reco.iterations == 5

# `ProcessResultCache` uses a least recently used (LRU) strategy to store the results. The cache size can be set by the user and defaults to 1. If the cache is full, the least recently used result is removed from the cache.

# The cache is checked with a key formed with the hash of all arguments of the processing step. `AbstractImageReconstruction` provides a default `hash` method for AbstractImageReconstructionParameters`, which hashes all properties of a parameter.

# Other methods of cache invalidation are creating a new plan or manual invalidation of the cache:
empty!(algo.parameter.pre.params)
reconstruct(algo, sinograms);

# Caches support serialization like other `RecoPlans`:
clear!(plan)
toTOML(stdout, plan)

# Caches can also be resized. You can either set the maxsize property of the RecoPlan or use `resize!` on the `ProcessResultCache`. Resizing a cache affects all algorithms build from the same plan.
setAll!(plan, :maxsize, 0)
