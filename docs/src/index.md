# AbstractImageReconstruction.jl

*Abstract Interface for Medical Image Reconstruction Packages*

## Introduction

AbstractImageReconstruction.jl is a Julia package that serves as the core API for medical imaging packages. It provides an interface and type hierarchy to represent and implement image reconstruction algorithms, their parameters and runtime behaviour. In particular, this package serves as the API of the Julia packages [MPIReco.jl](https://github.com/MagneticParticleImaging/MPIReco.jl).

The main design idea is:

* Algorithms (`AbstractImageReconstructionAlgorithm`) represent the runnable reconstruction engine, including runtime state and scheduling.
* Parameters (`AbstractImageReconstructionParameters`) represent configurable processing steps. Parameters are callable objects that define how data is processed by an algorithm.
* Plans (`RecoPlan`) are mutable, serializable blueprints for algorithms and parameters that can be partially specified, inspected, modified, and built into concrete algorithms.

Algorithms can be extended either by defining new parameter types (new processing steps) for existing algorithms, or by introducing new algorithm structs when different state or runtime behaviour is required.

## Features

* Reconstruction control flow defined with multiple dispatch on extensible and exchangeable type hierarchies
* Separation of data processing (callable parameter objects) and reconstruction runtime (algorithms, scheduling, locking, channels)
* Storing, loading, and manipulating of reconstruction algorithms with (partially) specified parameters via `RecoPlan`
* Attaching callbacks to parameter changes with ` Observables.jl`
* Various generic utilities such as transparent caching of intermediate reconstruction results

## Installation

Within Julia, use the package manager:
```julia
using Pkg
Pkg.add("AbstractImageReconstruction")
```

AbstractImageReconstruction is not intended to be used alone, but together with an image reconstruction package that implements the provided interface, such as [MPIReco.jl](https://github.com/MagneticParticleImaging/MPIReco.jl).

## Usage

The actual construction of reconstruction algorithms depends on the implementation of the reconstruction package. Once an algorithm is constructed with the given parameters, images can be reconstructed as follows:

```julia
using AbstractImageReconstruction, MPIReco

params = ... # Setup reconstruction parameter
algo = ... # Setup chosen algorithm with params
raw = ... # Setup raw data

image = reconstruct(algo, raw)
```

An algorithm can be transformed into a `RecoPlan`. These are mutable and transparent wrappers around the nested types of the algorithm and its parameters, which can be saved and restored to and from TOML files.

```julia
plan = toPlan(algo)
savePlan(MPIReco, "Example", plan)
plan = loadPlan(MPIReco, "Example", [MPIReco, RegularizedLeastSquares, MPIFiles])

algo2 = build(plan)
algo == algo2 # true
```

Unlike concrete algorithm instances, a `RecoPlan` may still be missing certain values of its properties. Furthermore, they can encode the structure of an image reconstruction algorithm without concrete parameterization.

It is also possible to attach listeners to `RecoPlan` properties using `Observables.jl`, which call user-specified functions when they are changed. This allows specific `RecoPlans` to provide smart default parameter choices or embedding a plan into a GUI.