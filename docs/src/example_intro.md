# Small Reconstruction Package for Radon projections
In this example we will implement a small image reconstruction package using `AbstractImageReconstruction.jl`. Our reconstruction package `OurRadonreco` aims to provide direct and iterative reconstruction algorithms for Radon projection data. 

Most of the desired functionality is already implemented in various Julia packages. Our reconstruction package now needs to properly link these packages and transform the data into the appropriate formats for each package. 

!!! note
    The example is intended for developers of reconstruction packages that use `AbstractImageReconstruction`. End-users of such a package should consult the documentation of the concrete reconstruction package itself.

## Installation

We can install `AbstractImageReconstruction` using the Julia package manager:

```julia
using Pkg
Pkg.add("AbstractImageReconstruction")
```

This will download and install AbstractImageReconstruction.jl and its dependencies. To install a different version, please consult the [Pkg documentation](https://pkgdocs.julialang.org/dev/managing-packages/#Adding-packages). In addition to AbstractImageReconstruction.jl, we will need several more packages to get started, which we can install the same way.


* [RadonKA.jl](https://github.com/roflmaostc/RadonKA.jl/tree/main) provides fast Radon forward and backward projections for direct reconstructions
* [LinearOperatorCollection.jl](https://github.com/JuliaImageRecon/LinearOperatorCollection.jl) wraps RadonKA.jl functionality into a matrix-free linear operator for iterative solvers
* [RegularizedLeastSquares.jl](https://github.com/JuliaImageRecon/RegularizedLeastSquares.jl) offers iterative solvers and regularization options
* [ImagePhantoms.jl](https://github.com/JuliaImageRecon/ImagePhantoms.jl) and [ImageGeoms.jl](https://github.com/JuliaImageRecon/ImageGeoms.jl) allow defining digital software "phantoms" for testing
* [CairoMakie.jl](https://docs.makie.org/stable/) for visualization

## Outline

1. [Radon Data](generated/example/0_radon_data.md): Familiarize with RadonKA.jl, define a small data format for 3D time-series sinograms, and create the inverse problem

2. [Interface](generated/example/1_interface.md): Define abstract types and understand what needs to be implemented to interact with `AbstractImageReconstruction`

3. [Direct Reconstruction](generated/example/2_direct.md): Implement reconstruction algorithms using backprojection and filtered backprojection

4. [Direct Reconstruction Result](generated/example/3_direct_result.md): Use the implemented algorithm

5. [Iterative Reconstruction](generated/example/4_iterative.md): Implement an iterative reconstruction algorithm with more complex parametrization

6. [Iterative Reconstruction Result](generated/example/5_iterative_result.md): Use the algorithm and demonstrate `RecoPlans` for configuration, saving, and loading algorithms as templates

For an even more detailed reconstruction package we refer to the magnetic particle imaging reconstruction package [MPIReco.jl](https://github.com/MagneticParticleImaging/MPIReco.jl).