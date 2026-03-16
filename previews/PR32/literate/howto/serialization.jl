include("../../literate/example/example_include_all.jl") #hide

# # Serialization
# As was shown in the example, a `RecoPlan` `AbstractImageReconstruction` can be used to easily parametrize reconstruction algorithms or provide a template structure. 
# Serializing and deserializing a plan can therefore be used to provide templates of algorithms as well as storing a fully parametrized algorithm to reproduce a reconstruction later on.
# The main goal of serialization is not to store and restore the concrete binary representation of the algorithm, but to store the parameters and the structure of the algorithm.
# Changes to parameters or algorithms internals could thus still be supported by a deserialized plan, as long as the keyword arguments of the constructor are still valid.

# !!! warning
#     Serialization is still in an experimental state and might change in the future. It is intended as a best-effort feature to provide a way to store and load plans.
#     Depending on the Julia version, the reconstruction package in question and the complexity of custom structs used in the parameters, serialization might not work as expected.

# `RecoPlans` are serialized as TOML files using the [TOML.jl](https://docs.julialang.org/en/v1/stdlib/TOML/) standard library:
pre = RadonPreprocessingParameters(frames = collect(1:3))
back_reco = RadonBackprojectionParameters(;angles)
algo_back = DirectRadonAlgorithm(DirectRadonParameters(pre, back_reco))
plan = toPlan(algo_back)
clear!(plan)
#toTOML(stdout, plan)

# Before serialization as a TOML file, the plan is turned into a nested dictionary using the functions `toDict, toDict!, toDictValue` and `toDictValue!`.
# The top-level function is `toDict`:
toDict(plan)

# This method creates a dictionary and records not only the value of the argument, but also the module and type name among other metadata. This metadata starts with a `_` and is used during deserialization to recreate the correct types.
# After creating the dictionary, the function `toDict!` is called to add the argument and its metadata to the dictionary.

# The value-representation of the argument is added to the dictionary using the `toDictValue!` method.
# The default `toDictValue!` for structs with fields adds each field of the argument as a key-value pair with the value being provided by the `toDictValue` function.

# While `AbstractImageReconstruction` tries to provide default implementations, multiple dispatch can be used for custom serialization of types.

# As an example we will add a new parameter struct for a filtered backprojection process using a given geometry:
export CustomGeomFilteredBackprojectionParameters
Base.@kwdef struct CustomGeomFilteredBackprojectionParameters{G <: RadonGeometry} <: OurRadonReco.AbstractDirectRadonReconstructionParameters
  angles::Vector{Float64}
  filter::Union{Nothing, Vector{Float64}} = nothing
  geometry::G
end
function AbstractImageReconstruction.process(::Type{<:AbstractDirectRadonAlgorithm}, params::CustomGeomFilteredBackprojectionParameters, data::AbstractArray{T, 3}) where {T}
  return RadonKA.backproject_filtered(data, params.angles; filter = params.filter, geometry = params.geometry)
end

# First we will take a look at the default serialization:
reco = RecoPlan(CustomGeomFilteredBackprojectionParameters; angles = [0.0], 
        geometry = RadonFlexibleCircle(size(sinograms, 1), [0.0, 0.0], [1.0, 1.0]))
toTOML(stdout, reco)

# In this case the default seems to work, but we can also provide a custom serialization for the geometry. This is especially helpful for custom types that contain large amounts of data, which we don't want to serialize.
# An example of this could be a file with meeasurement data, where we just want to store the file path and not the whole data.

# We want to serialize the geometry as a custom dictionary. For that we first need to override the default `toDictValue` method for the geometry: 
AbstractImageReconstruction.toDictValue(value::RadonGeometry) = toDict(value)

# This method is called when the fields for the `CustomGeomFilteredBackprojectionParameters` are serialized.

# Now that we create a custom dict representation, we can override the behaviour after the metadata is recorded. For that we specialize the `toDictValue!` method:
function AbstractImageReconstruction.toDictValue!(dict, value::RadonFlexibleCircle)
  dict["in"] = value.in_height
  dict["out"] =  value.out_height
  dict["N"] = value.N
end

# This results in our custom serialization:
toTOML(stdout, reco)

# We also need to create the corresponding deserialization functions. This is done by defining a `fromTOML` method for the type.
# Since we defined our value to be represented as a dictionary, we will need to construct our type from a dictionary:
function AbstractImageReconstruction.fromTOML(::Type{<:RadonGeometry}, dict::Dict{String, Any})
  return RadonFlexibleCircle(dict["N"], dict["in"], dict["out"])
end

# Finally, we can do a round-trip test to see if our serialization and deserialization works:
#md # ```julia
#md # io = IOBuffer()
#md # toTOML(io, reco)
#md # seekstart(io)
#md # recoCopy = loadPlan(io, [Main, OurRadonReco, RadonKA])
#md # toTOML(stdout, recoCopy)
#md # ```
io = IOBuffer() #jl
toTOML(io, reco) #jl
seekstart(io) #jl
recoCopy = loadPlan(io, [Main, OurRadonReco, RadonKA]) #jl
toTOML(stdout, recoCopy) #jl


# For deserialization we need to provide the module where the type is defined. This is necessary to "find" the correct type during deserialization that allows for the dispatch to the correct `fromTOML` method.
# Generally, this module selection can be done by the reconstruction package developer, though it is also possible for the user to add modules since they can easily extend algorithms with new processing steps.