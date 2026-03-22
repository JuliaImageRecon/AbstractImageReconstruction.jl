# AbstractImageReconstruction.jl

*Abstract Interface for Medical Image Reconstruction Research Packages*

## Introduction

AbstractImageReconstruction.jl is a Julia package that serves as the core API for medical imaging packages. It provides an interface and type hierarchy to represent and implement image reconstruction algorithms, their parameters and runtime behaviour. In particular, this package serves as the API of the Julia packages [MPIReco.jl](https://github.com/MagneticParticleImaging/MPIReco.jl).

The main design idea is:

* Algorithms (`AbstractImageReconstructionAlgorithm`) represent the runnable reconstruction runtime, including runtime state and scheduling.
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

## Usage (End-User)

The actual construction of reconstruction algorithms depends on the implementation of the reconstruction package. The documentation of AbstractImageReconstruction is mainly focused fr developers. Users of packages implemented with this interface will be able to perform reconstructions as follows:

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

Unlike concrete algorithm instances, a `RecoPlan` may still be missing certain values of its properties. Furthermore, they can encode the structure of an image reconstruction algorithm without concrete parameterization. This allows users to preconfigure image reconstruction templates.

It is also possible to attach listeners to `RecoPlan` properties using `Observables.jl`, which call user-specified functions when they are changed. This allows specific `RecoPlans` to provide smart default parameter choices or embedding a plan into a GUI.

## Usage (Package Developer)

Package developers create reconstruction packages by implementing types that extend `AbstractImageReconstructionAlgorithm` and `AbstractImageReconstructionParameters`. This separation provides flexibility for different reconstruction strategies.

### Overview

- **Algorithms** (`AbstractImageReconstructionAlgorithm`): Handle runtime behavior (state, locking, channels, scheduling)
- **Parameters** (`AbstractImageReconstructionParameters`): Handle data processing via callable interface (`param(algo, inputs...)`)
- **RecoPlans**: Mutable, serializable blueprints for algorithms and parameters

Algorithms can be extended either by defining new parameter types (new processing steps) for existing algorithms, or by introducing new algorithm structs when different state or runtime behaviour is required.

### Getting Started

Most of the remaining documentation of the package is presented in the form a simple radon based image reconstruction package.

### Core Concepts

#### Algorithms and Parameters

Algorithms and parameters have a clear separation of concerns:

- **Algorithms** handle runtime behavior (state, locking, channels, scheduling)
- **Parameters** handle data processing via callable interface (`param(algo, inputs...)`)

Parameters can be composed using the `@chain` macro to create processing pipelines. See [Interface](generated/example/1_interface.md) for implementation details.

#### RecoPlan

`RecoPlan` serves as a mutable, serializable blueprint for algorithms and parameters:

- Can be partially specified (templates for reconstruction)
- Supports property modification and recursive setting
- Customizable serialization to TOML with type preservation via StructUtils.jl
- Shared caches across algorithms built from the same plan

See [Iterative Reconstruction Result](generated/example/5_iterative_result.md) for RecoPlan usage examples.

### Implementation Guide

#### Essential Macros

The package provides macros to reduce boilerplate:

- `@parameter` - Define parameter structs with keyword constructors and validation
- `@chain` - Chain multiple processing steps sequentially
- `@reconstruction` - Define algorithms with automatic interface implementation (put!, take!, lock, etc.)

See the [API](API/api.md) for complete documentation of these macros.

#### Required Interface

When implementing custom algorithms without the provided macros, you must implement:

- `Base.put!(algo, inputs...)` - Submit input data for reconstruction
- `Base.take!(algo)` - Retrieve the reconstructed result
- `Base.lock(algo)`, `Base.unlock(algo)` - Synchronization primitives
- `Base.isready(algo)`, `Base.wait(algo)` - Status and blocking
- `AbstractImageReconstruction.parameter(algo)` - Access algorithm's main parameter

Algorithms should implement FIFO behavior: each `put!` call stores one result that is retrieved by the corresponding `take!`.

### Advanced Topics

#### Caching

Transparent caching of processing results via `ProcessResultCache`:

- Avoids unnecessary recomputations when parameters change
- Shared across algorithms built from the same plan
- LRU strategy automatic cache eviction
- See [Caching](generated/howto/caching.md) for details

#### Serialization

Save and load plans as TOML files:

- `savePlan(io, plan)` / `loadPlan(io, modules)` for round-trip serialization
- Full type preservation with module resolution
- Custom serialization styles for advanced use cases
- Plans as templates for repeated reconstructions
- See [Serialization](generated/howto/serialization.md) and [Storage](generated/howto/storage.md)

#### Observables

Reactive programming for interactive applications:

- Attach callbacks to plan property changes with `Observables.on`
- Link properties with `LinkedPropertyListener` (e.g., derive one parameter from another)
- Connect callbacks to interactive GUI applications for generic reconstructon UIs
- See [Observables](generated/howto/observables.md)

#### Custom Constructors

Advanced initialization patterns:

- `@init` hook for simple post-construction setup
- Custom constructors for type-dependent initialization
- Validation and logging during initialization
- See [Custom Constructors](generated/howto/constructors.md)

#### Multi-Threading

Control parallel execution strategies:

- Algorithms are stateful with locking interfaces
- Parallelization at algorithm level (separate instances) or processing step level
- Thread safety considerations for stateful algorithms
- See [Multi-Threading](generated/howto/multi_threading.md)

### Complete Examples

For a complete reconstruction package implementation:

- `OurRadonReco` - The example package (direct/iterative Radon reconstruction)
- [MPIReco.jl](https://github.com/MagneticParticleImaging/MPIReco.jl) - Implementation for MPI

### API Reference

See the [API](API/api.md) section for complete documentation of:
- All public functions and types
- Required methods for custom implementations
- Detailed macro documentation