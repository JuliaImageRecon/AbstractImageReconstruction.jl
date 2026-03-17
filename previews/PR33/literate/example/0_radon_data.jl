# # Radon Data

# In this example we will set up our radon data using RadonKA.jl, ImagePhantoms.jl and ImageGeoms.jl. We will start with simple 2D images and their sinograms and continue with a time series of 3D images and sinograms.

# ## Background
# The Radon transform is an integral transform that projects the values of a function(or a phantom) along straight lines onto a detector.
# These projections are recorded for a number of different angles and form the so-called sinogram. The Radon transform and its adjoint form the mathematical basis
# for computed tomography (CT) and other imaging modalities such as single photon emission computed tomography (SPECT) and positron emission tomography (PET).

# ## 2D Phantom
# We will use a simple Shepp-Logan phantom to generate our Radon data. The phantom is a standard test image for medical imaging and consists of a number of ellipses with different intensities.
# It can be generated using ImagePhantoms.jl and ImageGeoms.jl. as follows:

using ImagePhantoms, ImageGeoms
N = 256
image = shepp_logan(N, SheppLoganToft())
size(image)

# This produces a 256x256 image of a Shepp-Logan phantom. Next, we will generate the Radon data using `radon` from RadonKA.jl.
# The arguments of this function are the image or phantom to be transformed, the angles at which the projections are taken, and the used geometry of the system. For this example we will use the default parallel circle geometry. 
# For more details, we refer to the RadonKA.jl documentation. We will use 256 angles for the projections, between 0 and π.
using RadonKA
angles = collect(range(0, π, 256))
sinogram = Array(RadonKA.radon(image, angles))
size(sinogram)


# To visualize our progress so far, we will use CairoMakie.jl and a small helper function:
using CairoMakie
function plot_image(figPos, img; title = "", width = 150, height = 150)
  ax = CairoMakie.Axis(figPos[1, 1]; yreversed=true, title, width, height)
  hidedecorations!(ax)
  hm = heatmap!(ax, img)
  Colorbar(figPos[1, 2], hm)
end
fig = Figure()
plot_image(fig[1,1], image, title = "Image")
plot_image(fig[1,2], sinogram, title = "Sinogram")
resize_to_layout!(fig)
fig

# ## 3D Pnantom
# RadonKA.jl also supports 3D Radon transforms. The first two dimensions are interpreted as the XY plane where the transform applied and the last dimensions is the rotational axis z of the projections.
# For that we need to create a 3D Shepp-Logan phantom. First we retrieve the parameters of the ellipsoids of the Shepp-Logan phantom:
shape = (64, 64, 64)
params = map(collect, ellipsoid_parameters(; fovs = shape));

# We then scale the intensities of the ellipsoids to [0.0, ..., 1.0]:
toft_settings = [1.0, -0.8, -0.2, -0.2, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]
for idx in eachindex(toft_settings)
  params[idx][10] = toft_settings[idx]
end

# Finally, we create the 3D Shepp-Logan phantom by defining and sampling our image geometry: 
ob = ellipsoid(map(Tuple, params))
ig = ImageGeom(;dims = shape)
image = phantom(axes(ig)..., ob)
size(image)

# Now we can compute the 3D Radon transform of our phantom:
sinogram = Array(RadonKA.radon(image, angles))
size(sinogram)

# Let's visualize the 3D Radon data:
fig = Figure()
plot_image(fig[1,1], reverse(image[26,:,:]), title = "Slice YZ at z=26")
plot_image(fig[1,2], image[:,40,:], title = "Slice XZ at y=40")
plot_image(fig[2,1], reverse(image[:, :, 24]), title = "Slice XY at z=24")
plot_image(fig[2,2], reverse(sinogram[:,:,24]), title = "Sinogram at z=24")
plot_image(fig[3,1], reverse(image[:, :,16]), title = "Slice XY at z=16")
plot_image(fig[3,2], reverse(sinogram[:,:,16]), title = "Sinogram at z=16")
resize_to_layout!(fig)
fig


# ## Time Series of 3D Phantoms
# Lastly, we want to add a time dimension to our 3D phantom. For our example we will increase the intensity of the third ellipsoid every time step or frame.
images = similar(image, size(image)..., 5)
sinograms = similar(sinogram, size(sinogram)..., 5)
for (i, intensity) in enumerate(range(params[3][end], 0.3, 5))
  params[3][end] = intensity
  local ob = ellipsoid(map(Tuple, params))
  local ig = ImageGeom(;dims = shape)
  images[:, :, :, i] = phantom(axes(ig)..., ob)
  sinograms[:, :, :, i] = Array(RadonKA.radon(images[:, :, :, i], angles))
end
size(sinograms)

fig = Figure()
for i = 1:5
  plot_image(fig[i,1], reverse(images[:, :, 24, i]))
  plot_image(fig[i,2], sinograms[:, :, 24, i])
end
resize_to_layout!(fig)
fig

# The goal of our reconstruction package is now to recover an approximation of the time-series 3D phantoms from a given time-series of sinograms.
# In the next section we will introduce our class hierarchies and explore the API of AbstractImageReconstruction.jl.