using RadonKA, ImagePhantoms, ImageGeoms, CairoMakie, AbstractImageReconstruction, RegularizedLeastSquares
using CairoMakie 
using .OurRadonReco
function plot_image(figPos, img; title = "", width = 150, height = 150) 
  ax = CairoMakie.Axis(figPos[1, 1]; yreversed=true, title, width, height) 
  hidedecorations!(ax) 
  hm = heatmap!(ax, img) 
  Colorbar(figPos[1, 2], hm) 
end

isDataDefined = @isdefined sinograms
angles, shape, sinograms, images = isDataDefined ? (angles, shape, sinograms, images) : begin 
  angles = collect(range(0, π, 256)) 
  shape = (64, 64, 64) 
  params = map(collect, ellipsoid_parameters(; fovs = shape)) 
  toft_settings = [1.0, -0.8, -0.2, -0.2, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1] 
  for idx in eachindex(toft_settings) 
    params[idx][10] = toft_settings[idx] 
  end 
  ob = ellipsoid(map(Tuple, params)) 
  ig = ImageGeom(;dims = shape) 
  local image = phantom(axes(ig)..., ob) 
  sinogram = Array(RadonKA.radon(image, angles)) 
  sinograms = similar(sinogram, size(sinogram)..., 5) 
  images = similar(image, size(image)..., 5) 
  for (i, intensity) in enumerate(range(params[3][end], 0.3, 5)) 
    params[3][end] = intensity 
    local ob = ellipsoid(map(Tuple, params)) 
    local ig = ImageGeom(;dims = shape) 
    images[:, :, :, i] = phantom(axes(ig)..., ob) 
    sinograms[:, :, :, i] = Array(RadonKA.radon(images[:, :, :, i], angles)) 
  end 
  return angles, shape, sinograms, images
end
nothing
