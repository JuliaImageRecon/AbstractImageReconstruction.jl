include("../../literate/example/example_include_all.jl") #hide

# # Serialization
# As was shown in the example, a `RecoPlan` `AbstractImageReconstruction` can be used to easily parametrize reconstruction algorithms or provide a template structure. 
# Serializing and deserializing a plan can therefore be used to provide templates of algorithms as well as storing a fully parametrized algorithm to reproduce a reconstruction later on.
# The main goal of serialization is not to store and restore the concrete binary representation of the algorithm, but to store the parameters and the structure of the algorithm.
# Changes to parameters or algorithms internals could thus still be supported by a deserialized plan, as long as the keyword arguments of the constructor are still valid. 

# !!! warning
#     Serialization is intended as a best-effort feature to provide a way to store and load plans.
#     Depending on the Julia version, the reconstruction package in question and the complexity of custom structs used in the parameters, serialization might not work as expected.

# `RecoPlans` support serialization to TOML files using the [TOML.jl](https://docs.julialang.org/en/v1/stdlib/TOML/) standard library and the [StructUtils.jl](https://github.com/JuliaServices/StructUtils.jl) package.
# Let's first create an empty RecoPlan as a template:
pre = RadonPreprocessingParameters(frames = collect(1:3))
back_reco = RadonBackprojectionParameters(;angles)
algo_back = DirectRadonAlgorithm(DirectRadonParameters(pre, back_reco))
plan = toPlan(algo_back)
clear!(plan)

# We can save the plan to a file:

# ```julia
#   savePlan("myplan.toml", plan)
# ```

# Or preview the TOML output:

io = IOBuffer()
savePlan(io, plan)
seekstart(io)
println(String(take!(io)))

# ## Serialization Structure

# Before serialization as a TOML file, the plan is turned into a nested dictionary using `StructUtils.lower`.
# The serialization uses a style-based approach, where different styles can customize how types are serialized:

using AbstractImageReconstruction.StructUtils
style = RecoPlanStyle()
dict = StructUtils.lower(style, plan)

# This dictionary contains metadata (starting with `_`) used during deserialization to recreate the correct types.

# The metadata includes:
# - `_module`: The module where the type is defined
# - `_type`: The type name (for RecoPlan, includes the parametric type)

# ## Custom Serialization with Styles

# `AbstractImageReconstruction` provides a default style for RecoPlans and certain default types.
# For custom types, you can override the serialization behavior using custom styles.

# As an example, let's add a new parameter struct for a filtered backprojection process using a given geometry:
export CustomGeomFilteredBackprojectionParameters
@parameter struct CustomGeomFilteredBackprojectionParameters{G <: RadonGeometry} <: OurRadonReco.AbstractDirectRadonReconstructionParameters
  angles::Vector{Float64}
  filter::Union{Nothing, Vector{Float64}} = nothing
  geometry::G
end
function (params::CustomGeomFilteredBackprojectionParameters)(::Type{<:AbstractDirectRadonAlgorithm}, data::AbstractArray{T, 3}) where {T}
  return RadonKA.backproject_filtered(data, params.angles; filter = params.filter, geometry = params.geometry)
end

# First we will take a look at the default serialization:
reco = RecoPlan(CustomGeomFilteredBackprojectionParameters; angles = [0.0], 
        geometry = RadonFlexibleCircle(size(sinograms, 1), [0.0, 0.0], [1.0, 1.0]))
try
  io = IOBuffer()
  savePlan(io, reco)
  seekstart(io)
  println(String(take!(io)))
catch ex
  @error ex
end

# In this case the default didn't work, because a RadonFlexibleCircle is not a data type supported by TOML.
# We need to provide a custom serialization for the geometry. This is especially helpful for:
# - Custom types with large amounts of data
# - Types that should store only essential information (e.g., file paths instead of full data)

# ## Creating a Custom Style

# To customize serialization, we create a custom style and override the `StructUtils.lower` and `StructUtils.lift` methods:
# First, define a custom style that inherits from `CustomPlanStyle`:

struct MyRadonStyle <: CustomPlanStyle end

# This a style provided by AbstractImageReconstruction, which has a fallback to the usual RecoPlanStyle.

# We want to serialize the geometry as a custom dictionary. For that we first need to override the default `lower` method for the geometry: 
function StructUtils.lower(::MyRadonStyle, value::RadonFlexibleCircle)
  return Dict{String, Any}(
    "N" => value.N,
    "in" => value.in_height,
    "out" => value.out_height,
  )
end

# This method is called when the fields for the `CustomGeomFilteredBackprojectionParameters` are serialized.
# Now we can serialize using our custom style:
io = IOBuffer()
savePlan(io, reco, field_style=MyRadonStyle())
seekstart(io)
println(String(take!(io)))

# ## Custom Deserialization

# We also need to define how to deserialize our custom representation.
# This is done by overriding the `StructUtils.lift` method:

function StructUtils.lift(::MyRadonStyle, ::Type{<:RadonFlexibleCircle}, source::AbstractDict)
  return RadonFlexibleCircle(source["N"], source["in"], source["out"]), source
end

# Two things of note with this method. According to the StructUtils interface, the lift method returns a tuple with the return value and any side-effects.
# In usual serialization settings for AbstractImageReconstruction, this can be ignored/set to the provided source.
# Secondly our parameter is actually more generic than just the flexible circle. This means we need to record more metadata to support lifting of the correct type:
function StructUtils.lower(::MyRadonStyle, value::RadonFlexibleCircle)
  return Dict{String, Any}(
    "N" => value.N,
    "in" => value.in_height,
    "out" => value.out_height,
    "_type" => "RadonFlexibleCircle",
    "_module" => string(parentmodule(typeof(value)))
  )
end
# Here we followed the convetion from AbstractImageReconstruction, which stores `_module` and `_type` for the `RecoPlans`.
# Using that information, we can now define a lift method for the generic RadonGeometry:
function StructUtils.lift(::MyRadonStyle, ::Type{RadonGeometry}, dict::AbstractDict)
  if haskey(dict, "_type") && dict["_type"] == "RadonFlexibleCircle"
    return StructUtils.lift(MyRadonStyle(), RadonFlexibleCircle, dict)
  end
  return first(StructUtils.lift(RecoPlanStyle(), RadonGeometry, dict)), dict
end
# In the aboive variant, we hardcoded the string to type conversion. AbstractImageReconstruction can also be supplied with modules which can be used
# during deserialization to go from strings to types. For that we can access the scoped value MODULE_DICT inside the lift function:
function StructUtils.lift(::MyRadonStyle, ::Type{RadonGeometry}, dict::AbstractDict)
  type = MODULE_DICT[dict["_module"], dict["_type"]]
  return first(StructUtils.lift(MyRadonStyle(), type, dict)), dict
end
# We need to supply modules during deserialization to populate this dictionary.

# ## Round-Trip Test

# Finally, we can test that our custom serialization works correctly:

# First, let's print `reco again`:
reco

# Afterwards, we can save and load a plan from an IO buffer:

io = IOBuffer()
savePlan(io, reco, field_style=MyRadonStyle())
seekstart(io)
recoCopy = loadPlan(io, [parentmodule(CustomGeomFilteredBackprojectionParameters), OurRadonReco, RadonKA], field_style=MyRadonStyle())



# For deserialization, we needed to provide the modules where the types are defined. The module dict used within our lift method is populated from these modules.

# This allows the deserializer to "find" the correct types and dispatch to the appropriate `StructUtils.lift` methods.

# The module list should include:
# - Package modules with reconstruction types (e.g., `OurRadonReco`, `RadonKA`)
# - Any custom package modules you've used which contain types using as parameter inputs

# For a more user-friendly system that automatically tracks and discovers modules, see the Plan Storage and Usability How-To.
