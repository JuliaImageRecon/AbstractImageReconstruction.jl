include("../../literate/example/1_interface.jl") #hide
using RadonKA #hide
export AbstractIterativeRadonReconstructionParameters, IterativeRadonReconstructionParameters, IterativeRadonParameters, IterativeRadonAlgorithm #hide

# # Iterative Reconstruction
# In this section we implement a more complex iterative reconstruction algorithm. 
# We will use iterative solvers provided by [RegularizedLeastSquares.jl](https://github.com/JuliaImageRecon/RegularizedLeastSquares.jl). These solver feature a variety of arguments, in this example we will just focus on the parameters for the number of iterations and regularization.
# Each solver requires either a matrix or a matrix-free linear operator which implements multiplication with a vector as input. We will use [LinearOperatorCollection.jl](https://github.com/JuliaImageRecon/LinearOperatorCollection.jl), which implements a wrapper around RadonKA.

# For this example, we will further assume that the construction of this operator is costly and should be done only once. This means our algorithm will be stateful and has to store the operator.

# ## Parameters and Processing
# We will start by defining the parameters for the algorithm and the processing steps. Afterwards we can implement the algorithm itself. Since we will use the same preprocessing as for the direct reconstruction, we can reuse the parameters and processing steps and jump directly to the iterative parameters:
using RegularizedLeastSquares, LinearOperatorCollection
abstract type AbstractIterativeRadonReconstructionParameters <: AbstractRadonReconstructionParameters end
@parameter struct IterativeRadonReconstructionParameters{T, S <: AbstractLinearSolver, R <: AbstractRegularization, N} <: AbstractIterativeRadonReconstructionParameters
  eltype::Type{T}
  solver::Type{S}
  iterations::Int64 
  reg::Vector{R}
  shape::NTuple{N, Int64} 
  angles::Vector{Float64}
end
# The parameters of this struct can be grouped into three catergories. The solver type just specifies which solver to use. The number of iterations and the regularization term could be abstracted into a nested `AbstractRadonParameter` which describe the parameters for the solver. Lastly the shape and angles are required to construct the linear operator.

# Since we want to construct the linear operator only once, we will write the `process` method with the operator as a given argument:
function (params::IterativeRadonReconstructionParameters{T})(::Type{<:AbstractIterativeRadonAlgorithm}, op, data::AbstractArray{T, 4}) where {T}
  solver = createLinearSolver(params.solver, op; iterations = params.iterations, reg = params.reg)

  result = similar(data, params.shape..., size(data, 4))

  for i = 1:size(data, 4)
    result[:, :, :, i] = solve!(solver, vec(data[:, :, :, i]))
  end

  return result
end

# Later we need to define to create the operator and pass it to this `process` method.

# ## Algorithm
# Similar to the direct reconstruction algorithm, we want our iterative algorithm to accept both preprocessing and reconstruction parameters. We will encode this in a new type:
@parameter struct IterativeRadonParameters{P<:AbstractRadonPreprocessingParameters, R<:AbstractIterativeRadonReconstructionParameters} <: AbstractRadonParameters 
  pre::P
  reco::R
end
# Instead of defining essentially the same struct again, we could also define a more generic one and specify the supported reconstruction parameter as type constraints in the algorithm constructor.

# Unlike the direct reconstruction algorithm, the iterative algorithm has to store the linear operator. We will store it as a field in the algorithm type in an initialization step:
@reconstruction mutable struct IterativeRadonAlgorithm{D <: IterativeRadonParameters} <: AbstractIterativeRadonAlgorithm
  @parameter parameter::D
  op::Union{Nothing, AbstractLinearOperator} = nothing

  @init function createOperator(algo)
    params = algo.parameter.reco
    algo.op = RadonOp(params.eltype; shape = params.shape, angles = params.angles)
  end
end
# If our algorithms require more complex initial state or parametric types, we can also create custom constructors. See the API for more information.

# Next we implement the our manual chain method for our reconstruction parameters and an algorithm instance. This allows us to access the operator and pass it to the reconstruction step:
function (params::IterativeRadonParameters{P, R})(algo::IterativeRadonAlgorithm, data::AbstractArray{T, 4}) where {T, P<:AbstractRadonPreprocessingParameters, R<:AbstractIterativeRadonReconstructionParameters}
  data = params.pre(algo, data)
  return params.reco(algo, algo.op, data)
end

# Our algorithm is not type stable. To fix this, we would need to know the element type of the sinograms during construction. Which is possible with a different parameterization of the algorithm. We will not do this here.
# Often times the performance impact of this is negligible as the critical sections are in the preprocessing or the iterative solver, especially since we still dispatch on the operator.