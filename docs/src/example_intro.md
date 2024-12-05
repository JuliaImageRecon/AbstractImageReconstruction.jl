# Small Reconstruction Package for Radon projections
In this example we will implement a small image reconstruction package with the help of `AbstractImageReconstruction.jl`. Our example reconstruction package aims to provide direct and iterative reconstruction algorithms for Radon projection data. 

Most of the desired functionality is already implemented in various Julia packages. Our reconstruction packages now needs to properly connect these packages and transform the data into the appropriate formats for each package. 

The example is intended for developers of reconstruction packages that use `AbstractImageReconstruction`. End-users of such a package can consult the result sections of the example to see the high-level interface of `AbstractImagerReconstruction` and should otherwise consult the documentation of the concrete reconstruction package itself.

## Installation
We can install `AbstractImageReconstruction` using the Julia package manager. Open a Julia REPL and run the following command:

```julia
using Pkg
Pkg.add("AbstractImageReconstruction")
```
This will download and install AbstractImageReconstruction.jl and its dependencies. To install a different version, please consult the [Pkg documentation](https://pkgdocs.julialang.org/dev/managing-packages/#Adding-packages). In addition to AbstractImageReconstruction.jl, we will need a few more packages to get started, which we can install the same way.


[RadonKA.jl](https://github.com/roflmaostc/RadonKA.jl/tree/main) provides us with fast Radon forward and backprojections, which we can use for direct reconstructions and preparing example data for our package. 

[LinearOperatorCollection.jl](https://github.com/JuliaImageRecon/LinearOperatorCollection.jl) wraps the functionality of RadonKA.jl in a matrix-free linear operator, which can be used in iterative solvers.

[RegularizedLeastSquares.jl](https://github.com/JuliaImageRecon/RegularizedLeastSquares.jl) offers a variety of iterative solver and regularization options.

[ImagePhantoms.jl](https://github.com/JuliaImageRecon/ImagePhantoms.jl) and [ImageGeoms.jl](https://github.com/JuliaImageRecon/ImageGeoms.jl) allow us to define digital software "phantoms", which we will use to test our reconstruction algorithms.

Lastly, we will use [CairoMakie.jl](https://docs.makie.org/stable/) to visualize our results.

## Outline
[Radon Data](generated/example/0_radon_data.md): In this section we get familiar with RadonKA.jl and define a small dataformat for three-dimensional time-series sinograms. We also create the inverse problem, which we want to solve in the remainder of the example.

[Interface](generated/example/1_interface.md): Here we define the abstract types we will use in our package and take a look at what we need to implement to interact with `AbstractImageReconstruction`. We also start with a first processing step of our algorithms.

[Direct Reconstruction](generated/example/2_direct.md): Now we extend our abstract types with a concrete implementation of reconstruction algorithms using the backprojection and filtered backprojection.

[Direct Reconstruction Result](generated/example/3_direct_result.md): This section shows how to use the algorithm we just implemented.

[Iterative Reconstruction](generated/example/4_iterative.md): We finish our small example package by implementing an iterative reconstruction algorithm. For this algorithm we require more complex parametrization and data processing.

[Iterative Reconstruction Result](generated/example/5_iterative_result.md): The last section again shows how to use the just implemented algorithm. But it also highlights `RecoPlans`, which are a core utility of `AbstractImageReconstruction`. These plans allow a user to easily configure, store and load algorithms as templates.

For an even more indepth reconstruction package we refer to the magnetic particle imaging reconstruction package [MPIReco.jl](https://github.com/MagneticParticleImaging/MPIReco.jl).
