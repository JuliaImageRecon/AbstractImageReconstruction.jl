include("../../literate/example/example_include_all.jl") #hide
# # Plan Storage and Useability

# When working with serialized `RecoPlan`s, managing modules and plan files becomes important.
# This guide shows how to set up a plan storage system for automatic module discovery. Ideally, this is implemented in a reconstruction package and abstracted away from the users.

# ## Basic Storage System

# Here's a simple system for managing plan directories and modules:
# We first track plans and modules for our reconstruction:
const recoPlanPaths = AbstractString[]
const recoPlanModules = Module[AbstractImageReconstruction, OurRadonReco, RegularizedLeastSquares]

# And then we define methods to extend our storage:
addRecoPlanPath(path) = !(path in recoPlanPaths) ? pushfirst!(recoPlanPaths, path) : nothing
addRecoPlanModule(mod) = !(mod in recoPlanModules) ? push!(recoPlanModules, mod) : nothing
getRecoPlanModules() = recoPlanModules
function getRadonPlanList(; full = false)
  result = String[]
  for path in recoPlanPaths
    if isdir(path)
      push!(result, [plan for plan in filter(a->contains(a,".toml"),readdir(path, join =  full))]...)
    end
  end
  return result
end

# Afterwards we define a helper function which lets us find a plan if a user provides the name
function planpath(name::AbstractString)
  for dir in recoPlanPaths
    filename = joinpath(dir, string(name, ".toml"))
    isfile(filename) && return filename
  end
  isfile(name) && return name
  throw(ArgumentError("Could not find plan: $name"))
end

# ## Radon-Specific Storage System

# Once we defined this tooling in our Radon package, we can provide some default reconstruction algorithms.
# Let's assume we have a subfolder called for configured `RecoPlans`:
const DEFAULT_PLANS_PATH = joinpath(@__DIR__, "config")
if !isdir(DEFAULT_PLANS_PATH)
  mkdir(DEFAULT_PLANS_PATH)
end
# We can add this path when loading our Radon package:
addRecoPlanPath(DEFAULT_PLANS_PATH)

# And we can add a helper functions which either directly loads a plan from a file or searches for stored one:
function loadRadonPlan(planfile::AbstractString, modules; kwargs...)
  return open(planfile, "r") do io
    return loadRadonPlan(io, modules; kwargs...)
  end
end
function loadRadonPlan(io, modules; kwargs...)
  plan = loadPlan(io, modules)
  setAll!(plan; kwargs...)
  return plan
end
function RadonRecoPlan(value::String, modules = getRecoPlanModules(); kwargs...)
  if isfile(value) && endswith(value, ".toml")
    return loadRadonPlan(value, modules; kwargs...)
  else
    return loadRadonPlan(planpath(value), modules; kwargs...)
  end
end

# And we can provide a helper reconstruction function:
function AbstractImageReconstruction.reconstruct(name::String, sino; modules = getRecoPlanModules(), kwargs...)
  plan = RadonRecoPlan(name, modules; kwargs...)
  return reconstruct(build(plan), sino)
end

# Let us now populate our storage with some reconstructions:
# First a simple direct reconstruction:
plan = RecoPlan(DirectRadonAlgorithm; parameter = 
  RecoPlan(DirectRadonParameters; 
    pre = RecoPlan(RadonPreprocessingParameters),
    reco = RecoPlan(RadonBackprojectionParameters)
  )
)
savePlan(joinpath(DEFAULT_PLANS_PATH, "direct.toml"), plan)
# Then a filtered back projection:
plan = RecoPlan(DirectRadonAlgorithm; parameter = 
  RecoPlan(DirectRadonParameters; 
    pre = RecoPlan(RadonPreprocessingParameters),
    reco = RecoPlan(RadonFilteredBackprojectionParameters)
  )
)
savePlan(joinpath(DEFAULT_PLANS_PATH, "filtered.toml"), plan)
# And lastly an iterative reconstruction:
plan = RecoPlan(IterativeRadonAlgorithm; parameter = 
  RecoPlan(IterativeRadonParameters; 
    pre = RecoPlan(RadonPreprocessingParameters),
    reco = RecoPlan(IterativeRadonReconstructionParameters)
  )
)
savePlan(joinpath(DEFAULT_PLANS_PATH, "iterative.toml"), plan)

# ## Usage Example

# With this system, using our reconstructions becomes much simpler.
# user would only need to load our reco package OurRadonReco:

# ```julia
# using OurRadonReco
# ```
# They can then list available plans
getRadonPlanList()

# Load a plan by name (modules are automatically used)
plan = RadonRecoPlan("filtered")

# Or setup reconstructions using the plans directly or our helper method:
params = Dict{Symbol, Any}()
params[:frames] = collect(1:3)
params[:eltype] = eltype(sinograms)
params[:shape] = size(images)[1:3]
params[:angles] = angles
params[:iterations] = 20
params[:reg] = [L2Regularization(0.001), PositiveRegularization()]
params[:solver] = CGNR
image_direct = reconstruct("direct", sinograms; params...)
image_filtered = reconstruct("filtered", sinograms; params...)
image_iter = reconstruct("iterative", sinograms; params...)

fig = Figure()
for i = 1:3
  plot_image(fig[i,1], reverse(images[:, :, 24, i]), title = i == 1 ? "Phantom" : "")
  plot_image(fig[i,2], sinograms[:, :, 24, i], title = i == 1 ? "Sinogram" : "")
  plot_image(fig[i,3], reverse(image_direct[:, :, 24, i]), title = i == 1 ? "BP" : "")
  plot_image(fig[i,4], reverse(image_filtered[:, :, 24, i]), title = i == 1 ? "Filtered BP" : "")
  plot_image(fig[i,5], reverse(image_iter[:, :, 24, i]), title = i == 1 ? "Iterative" : "")
end
resize_to_layout!(fig)
fig

# If users want to extend our package with new algorithms, they can just write new parameters or algorithms and add them to our tracking setup.
# Similarly, other packages building upon ours recos could add themselves during loading and make their plans available via our base interface.

# Some further steps to flesh out such a system:
# * Add caching of `RecoPlans`
# * Keyword arguments can change plan structures and should be applied in specific orders
# * Graphical interface to allow users full control over the nested algorithms
# * `reconstruct` helper function is committing type-piracy in its current form, since neither Strings, Arrays nor the function itself are defined in AbstractImageReconstruction