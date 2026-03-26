using AbstractImageReconstruction
using AbstractImageReconstruction.Observables
using AbstractImageReconstruction.AbstractTrees
using Test
using RegularizedLeastSquares
using TOML
using AbstractImageReconstruction.AbstractTrees
using AbstractImageReconstruction.ScopedValues
using AbstractImageReconstruction.StructUtils

include(joinpath(@__DIR__(), "..", "docs", "src", "literate", "example", "example_include_all.jl"))

abstract type AbstractTestBase <: AbstractImageReconstructionAlgorithm end
abstract type AbstractTestParameters <: AbstractImageReconstructionParameters end

@testset "AbstractImageReconstruction.jl" begin
  include("algorithm_api.jl")
  include("reco_plan.jl")
  include("struct_transforms.jl")
  include("serialization.jl")
  include("linkedproperty.jl")
  include("caching.jl")
  include("reco_plan_sweeps.jl")
end
