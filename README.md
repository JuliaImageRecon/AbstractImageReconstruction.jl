# AbstractImageReconstruction

[![Build Status](https://github.com/JuliaImageRecon/AbstractImageReconstruction.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaImageRecon/AbstractImageReconstruction.jl/actions/workflows/CI.yml?query=branch%3Amain)

[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://JuliaImageRecon.github.io/AbstractImageReconstruction.jl)


This package contains an interface and type hierarchy for image reconstruction algorithms and their parameters, together with associated utility tools.

## Installation

Within Julia, use the package manager:
```julia
using Pkg
Pkg.add("AbstractImageReconstruction")
```
AbstractImageReconstruction is not intended to be used alone, but together with an image reconstruction package that implements the provided interface, such as [MPIReco.jl](https://github.com/MagneticParticleImaging/MPIReco.jl)

## Usage
Concrete construction of reconstruction algorithms depend on the implementation of the reconstruction package. Once an algorithms is constructed with the given paramters, images can be reconstructed as follows:
```julia
using AbstractImageReconstruction, MPIReco

params = ... # Setup reconstruction paramter
algo = ... # Setup chosen algorithm with params
raw = ... # Setup raw data

image = reconstruct(algo, raw)
```
Once an algorithm is constructed it can be transformed into a `RecoPlan`. These are mutable and transparent wrappers around the nested types of the algorithm and its paramters, that can be stored and restored to and from TOML files.

```julia
plan = toPlan(algo)
savePlan(MPIReco, "Example", plan)
plan = loadPlan(MPIReco, "Example", [MPIReco, RegularizedLeastSquares, MPIFiles])

algo2 = build(plan)
algo == algo2 # true
```
Unlike concrete algorithm instances, a `RecoPlan` may still be missing certain values of its fields and it can encode the structure of an image reconstruction algorithm without concrete parameterization.

It is also possible to attach `Listeners` to `RecoPlan` fields, that call user-specified functions if they are changed. This allows specific `RecoPlans` to provide smart default paramter choices or embedding a plan into a GUI.