using AbstractImageReconstruction
using AbstractImageReconstruction.Observables
using AbstractImageReconstruction.AbstractTrees
using Test
using RegularizedLeastSquares

include(joinpath(@__DIR__(), "..", "docs", "src", "literate", "example", "example_include_all.jl"))

@testset "AbstractImageReconstruction.jl" begin
  include("algorithm_api.jl")
  include("reco_plan.jl")
  include("struct_transforms.jl")
  include("serialization.jl")
  include("linkedproperty.jl")
  include("caching.jl")
end
