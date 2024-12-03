# Small Reconstruction Package for Radon projections
In this example we will implement a small image reconstruction package with the help of `AbstractImageReconstruction.jl`. Our example reconstruction package aims to provide direct and iterative reconstruction algorithms for Radon projection data with optional GPU support. 

Most of the desired functionality is already implemented in various Julia packages. Our reconstruction packages now needs to properly connect these packages and transform the data into the appropriate formats for each package.

## Installation
In addition to AbstractImageReconstruction.jl, we will need a few more packages to get started. We can install these packages using the Julia package manager. Open a Julia REPL and run the following command:

```julia
using Pkg
Pkg.add("AbstractImageReconstruction")
```
This will download and install AbstractImageReconstruction.jl and its dependencies. To install a different version, please consult the [Pkg documentation](https://pkgdocs.julialang.org/dev/managing-packages/#Adding-packages). 


[RadonKA.jl](https://github.com/roflmaostc/RadonKA.jl/tree/main) provides us with fast Radon forward and backprojections, which we can use for direct reconstructions and preparing example data for our package. 

[LinearOperatorCollection.jl](https://github.com/JuliaImageRecon/LinearOperatorCollection.jl) wraps the functionality of RadonKA.jl in a matrix-free linear operator, which can be used in iterative solvers.

[RegularizedLeastSquares.jl](https://github.com/JuliaImageRecon/RegularizedLeastSquares.jl) offers a variety of iterative solver and regularization options.

[ImagePhantoms.jl](https://github.com/JuliaImageRecon/ImagePhantoms.jl) and [ImageGeoms.jl](https://github.com/JuliaImageRecon/ImageGeoms.jl) allow us to define digital software "phantoms", which we will use to test our reconstruction algorithms.

Lastly, we will use [CairoMakie.jl](https://docs.makie.org/stable/) to visualize our results.

## Outline

