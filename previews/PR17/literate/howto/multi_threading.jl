include("../../literate/example/example_include_all.jl") #hide

# # Multi-Threading
# `AbstractImageReconstruction` assumes that algorithms are stateful. This is reflected in the FIFO behaviour and the locking interface of algorithms.
# The motivation behind this choice is that the nature of computations within an algorithms heavily impact if multi-threading is beneficial or not.
# For example, consider a GPU-accelerated reconstruction. There it might be faster to sequentially process all images on the GPU instead of processing them in parallel. Or consider, the preprocessing step of the Radon example where we average our data. If we were to extend our algorithm to read sinograms from a file, it might be inefficient to partially read and average frames from the file in parallel.
# Instead it would be more efficient to read the required file in one go and then average the frames in parallel.
# Therefore, the actual runtime behaviour is intended to be an implementation detail of an algorithm which is to be abstracted behind `reconstruct`.

# In the following we will explore the results of this design decision. If we consider a n algorithm such as:
plan = RecoPlan(IterativeRadonAlgorithm, parameter = RecoPlan(IterativeRadonParameters,
  pre = RecoPlan(RadonPreprocessingParameters, frames = collect(1:5)),
  reco = RecoPlan(IterativeRadonReconstructionParameters, shape = size(images)[1:3], angles = angles,
            iterations = 20, reg = [L2Regularization(0.001), PositiveRegularization()], solver = CGNR)
))
algo = build(plan)

# which acts on one frame at a time, we could in theory do:
# ```julia
# Threads.@threads for i = 1:size(sinograms, 4)
#  res = reconstruct(algo, sinograms[:, :, :, i:i])
#  # Store res
# end
# ```
# Due to the locking interface of the algorithm, this will not actually run in parallel. Instead the algorithm will be locked for each iteration and tasks will wait for the previous reconstruction to finish.

# If a user wants to explicitly use multi-threading, we could the plan to create a new algorithm for each task:
# ```julia 
# Threads.@threads for i = 1:size(sinograms, 4)
#   algo = build(plan)
#   res = reconstruct(algo, sinograms[:, :, :, i:i])
#   # Store res
# end
# ```
# This way each task has its own algorithm and can run in parallel. As mentioned before, this parallelization might not be the most efficient parallel reconstruction, both in terms of memory and runtime.

# To further improve the performance of the reconstruction, we could implement specific multi-threading `process`-ing steps for our algorithms. As an example, we will implement parallel processing for the iterative solver:
Base.@kwdef struct ThreadedIterativeReconstructionParameters{S <: AbstractLinearSolver, R <: AbstractRegularization, N} <: AbstractIterativeRadonReconstructionParameters
  solver::Type{S}
  iterations::Int64 
  reg::Vector{R}
  shape::NTuple{N, Int64} 
  angles::Vector{Float64}
end
# Our parameters are identical to the iterative reconstruction parameters from the iterative example. We only differ in the type of the parameters. This allows us to dispatch on the type of the parameters and implement a different `process` method for the threaded version:
function AbstractImageReconstruction.process(::Type{<:AbstractIterativeRadonAlgorithm}, params::ThreadedIterativeReconstructionParameters, op, data::AbstractArray{T, 4}) where {T}

  result = similar(data, params.shape..., size(data, 4))

  Threads.@threads for i = 1:size(data, 4)
    solver = createLinearSolver(params.solver, op; iterations = params.iterations, reg = params.reg)
    result[:, :, :, i] = solve!(solver, vec(data[:, :, :, i]))
  end

  return result
end

# While the Radon operator is thread-safe, the normal operator constructed by the solver is not. Therefore, we can reuse the Radon operator but still have to construct new solvers for each task.

# Our multi-threaded reconstruction can be constructed and used just like the single-threaded one::
plan.parameter.pre.frames = collect(1:size(sinograms, 4))
plan.parameter.reco = RecoPlan(ThreadedIterativeReconstructionParameters, shape = size(images)[1:3], angles = angles,
            iterations = 20, reg = [L2Regularization(0.001), PositiveRegularization()], solver = CGNR)

algo = build(plan)
imag_iter = reconstruct(algo, sinograms)
fig = Figure()
for i = 1:5
  plot_image(fig[i,1], reverse(images[:, :, 24, i]))
  plot_image(fig[i,2], sinograms[:, :, 24, i])
  plot_image(fig[i,3], reverse(imag_iter[:, :, 24, i]))
end
resize_to_layout!(fig)
fig
