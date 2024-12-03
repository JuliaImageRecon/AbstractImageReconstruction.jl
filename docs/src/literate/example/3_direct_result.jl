include("../../literate/example/1_interface.jl") #hide
include("../../literate/example/2_direct.jl") #hide
using RadonKA, ImagePhantoms, ImageGeoms, CairoMakie, AbstractImageReconstruction #hide
using CairoMakie #hide
function plot_image(figPos, img; title = "", width = 150, height = 150) #hide
  ax = CairoMakie.Axis(figPos[1, 1]; yreversed=true, title, width, height) #hide
  hidedecorations!(ax) #hide
  hm = heatmap!(ax, img) #hide
  Colorbar(figPos[1, 2], hm) #hide
end #hide
angles = collect(range(0, π, 256)) #hide
shape = (128, 128, 128) #hide
params = map(collect, ellipsoid_parameters(; fovs = shape)) #hide
toft_settings = [1.0, -0.8, -0.2, -0.2, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1] #hide
for idx in eachindex(toft_settings) #hide
  params[idx][10] = toft_settings[idx] #hide
end #hide
ob = ellipsoid(map(Tuple, params)) #hide
ig = ImageGeom(;dims = shape) #hide
image = phantom(axes(ig)..., ob) #hide
sinogram = Array(RadonKA.radon(image, angles)) #hide
sinograms = similar(sinogram, size(sinogram)..., 5) #hide
images = similar(image, size(image)..., 5) #hide
for (i, intensity) in enumerate(range(params[3][end], 0.3, 5)) #hide
  params[3][end] = intensity #hide
  local ob = ellipsoid(map(Tuple, params)) #hide
  local ig = ImageGeom(;dims = shape) #hide
  images[:, :, :, i] = phantom(axes(ig)..., ob) #hide
  sinograms[:, :, :, i] = Array(RadonKA.radon(images[:, :, :, i], angles)) #hide
end #hide


# # Direct Reconstruction Result
# Now that we have implemented our direct reconstruction algorithm, we can use it to reconstruct for example the first three images of our time series.
# We first prepare our parameters:
pre = RadonPreprocessingParameters(frames = collect(1:3))
back_reco = RadonBackprojectionParameters(;angles)
filter_reco = RadonFilteredBackprojectionParameters(;angles);

# Then we can construct the algorithms:
algo_back = DirectRadonAlgorithm(DirectRadonParameters(pre, back_reco))
algo_filter = DirectRadonAlgorithm(DirectRadonParameters(pre, filter_reco));

# And apply them to our sinograms:
imag_back = reconstruct(algo_back, sinograms)
imag_filter = reconstruct(algo_filter, sinograms);

# Finally we can visualize the results:
fig = Figure()
for i = 1:3
  plot_image(fig[i,1], reverse(images[:, :, 48, i]))
  plot_image(fig[i,2], sinograms[:, :, 48, i])
  plot_image(fig[i,3], reverse(imag_back[:, :, 48, i]))
  plot_image(fig[i,4], reverse(imag_filter[:, :, 48, i]))
end
resize_to_layout!(fig)
fig

# To add new functionality to our direct reconstruction algorithm, we can simply add new preprocessing or reconstruction parameters and implement the according processing steps. This way we can easily extend our algorithm to support new features.
# We can also define our own file format to store the results of our reconstruction algorithms or dispatch our preprocessing on files and pass files instead of the sinograms directly.

# The way we use the algorithms here, requires the user to reconstruct the algorithm for each changed parameter. After we implement the more complex iterative reconstructions, we will take a look at how to make this process more manageable.