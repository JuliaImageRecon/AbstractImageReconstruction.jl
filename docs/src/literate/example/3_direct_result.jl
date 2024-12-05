include("../../literate/example/example_include.jl") #hide

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
  plot_image(fig[i,1], reverse(images[:, :, 24, i]))
  plot_image(fig[i,2], sinograms[:, :, 24, i])
  plot_image(fig[i,3], reverse(imag_back[:, :, 24, i]))
  plot_image(fig[i,4], reverse(imag_filter[:, :, 24, i]))
end
resize_to_layout!(fig)
fig

# To add new functionality to our direct reconstruction algorithm, we can simply add new preprocessing or reconstruction parameters and implement the according processing steps. This way we can easily extend our algorithm to support new features.
# We can also define our own file format to store the results of our reconstruction algorithms or dispatch our preprocessing on files and pass files instead of the sinograms directly.

# The way we use the algorithms here, requires the user to reconstruct the algorithm for each changed parameter. After we implement the more complex iterative reconstructions, we will take a look at how to make this process more manageable.