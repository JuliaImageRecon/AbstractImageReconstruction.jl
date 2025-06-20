@testset "Caching" begin
  Base.@kwdef mutable struct CacheableParameter <: AbstractImageReconstructionParameters
    factor::Int64
    cache_misses::Ref{Int64}
  end
  Base.@kwdef mutable struct PureCacheableParameter <: AbstractImageReconstructionParameters
    factor::Int64
    cache_misses::Ref{Int64}
  end
  mutable struct CacheableAlgorithm{P} <: AbstractImageReconstructionAlgorithm
    const parameter::Union{P, ProcessResultCache{P}}
    value::Int64
    output::Channel{Int64}
    CacheableAlgorithm(parameter::ProcessResultCache{P}) where P = new{P}(parameter, 1, Channel{Int64}(Inf))
    CacheableAlgorithm(parameter::P) where P = new{P}(parameter, 1, Channel{Int64}(Inf))
  end
  AbstractImageReconstruction.parameter(algo::CacheableAlgorithm) = algo.parameter
  Base.lock(algo::CacheableAlgorithm) = lock(algo.output)
  Base.unlock(algo::CacheableAlgorithm) = unlock(algo.output)
  Base.take!(algo::CacheableAlgorithm) = Base.take!(algo.output)
  function Base.put!(algo::CacheableAlgorithm, value) 
    lock(algo) do
      put!(algo.output, process(algo, algo.parameter, value))
    end
  end
  # Implement proper hashing for algorithm, otherwise hash will ignore changes to value
  function Base.hash(algo::CacheableAlgorithm, h::UInt64)
    return hash(typeof(algo), hash(algo.output, hash(algo.value, hash(algo.parameter, h))))
  end

  function AbstractImageReconstruction.process(algo::CacheableAlgorithm, parameter::CacheableParameter, value)
    parameter.cache_misses[] += 1
    return algo.value + parameter.factor * value
  end
  function AbstractImageReconstruction.process(algo::CacheableAlgorithm, parameter::Union{PureCacheableParameter, ProcessResultCache{PureCacheableParameter}}, value)
    return algo.value + process(typeof(algo), parameter, value)
  end
  function AbstractImageReconstruction.process(algo, parameter::PureCacheableParameter, value)
    parameter.cache_misses[] += 1
    return parameter.factor * value
  end

  @testset "Constructor" begin
    cached_parameter = PureCacheableParameter(3, Ref(0))
    cache = ProcessResultCache(; param = cached_parameter, maxsize = 42)
    cache2 = ProcessResultCache(cache.cache; param = cache.param)
    cache3 = ProcessResultCache(42; param = cache.param)
    @test cache.cache == cache2.cache
    @test cache.maxsize == cache2.maxsize
    @test cache.cache.maxsize == cache2.cache.maxsize
    @test cache2.maxsize == cache3.maxsize
    @test cache2.cache.maxsize == cache3.cache.maxsize
  end

  @testset "Stateful Process" begin
    uncached_parameter = CacheableParameter(3, Ref(0))    
    algo = CacheableAlgorithm(uncached_parameter)

    cache_misses = Ref(0)
    cached_parameter = CacheableParameter(3, cache_misses)
    cache = ProcessResultCache(; param = cached_parameter, maxsize = 1)
    cached_algo = CacheableAlgorithm(cache)
    # Inital reco misses cache
    @test reconstruct(algo, 42) == reconstruct(cached_algo, 42)
    @test cache_misses[] == 1
    cache_misses[] = 0
    # Other value misses cache
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 1
    cache_misses[] = 0
    # Repeated value hits cache
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 0
    cache_misses[] = 0
    # Changing parameter results in cache miss
    uncached_parameter.factor = 5
    cached_parameter.factor = 5
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 1
    cache_misses[] = 0
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 0
    cache_misses[] = 0
    # Changing algorithm results in cache miss
    algo.value = 2
    cached_algo.value = 2
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 1
    cache_misses[] = 0
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 0
    cache_misses[] = 0

    @testset "Resize" begin
      resize!(cache, 3)
      for i in 1:3
        @test reconstruct(algo, i) == reconstruct(cached_algo, i)
      end
      old_misses = cache_misses[]
      for i in 1:3
        @test reconstruct(algo, i) == reconstruct(cached_algo, i)
        @test cache_misses[] == old_misses
      end
      resize!(cache, 0)
      for i in 1:3
        @test reconstruct(algo, i) == reconstruct(cached_algo, i)
      end
      @test cache_misses[] == old_misses + 3       
    end


  end
  
  @testset "Pure Process" begin
    uncached_parameter = CacheableParameter(3, Ref(0))    
    algo = CacheableAlgorithm(uncached_parameter)

    cache_misses = Ref(0)
    cached_parameter = PureCacheableParameter(3, cache_misses)
    cache = ProcessResultCache(; param = cached_parameter, maxsize = 1)
    cached_algo = CacheableAlgorithm(cache)
    # Inital reco misses cache
    @test reconstruct(algo, 42) == reconstruct(cached_algo, 42)
    @test cache_misses[] == 1
    cache_misses[] = 0
    # Other value misses cache
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 1
    cache_misses[] = 0
    # Repeated value hits cache
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 0
    cache_misses[] = 0
    # Changing parameter results in cache miss
    uncached_parameter.factor = 5
    cached_parameter.factor = 5
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 1
    cache_misses[] = 0
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 0
    cache_misses[] = 0
    # Changing algorithm results in no cache miss
    algo.value = 2
    cached_algo.value = 2
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 0
    cache_misses[] = 0
    @test reconstruct(algo, 3) == reconstruct(cached_algo, 3)
    @test cache_misses[] == 0
    cache_misses[] = 0

    @testset "Resize" begin
      resize!(cache, 3)
      for i in 1:3
        @test reconstruct(algo, i) == reconstruct(cached_algo, i)
      end
      old_misses = cache_misses[]
      for i in 1:3
        @test reconstruct(algo, i) == reconstruct(cached_algo, i)
        @test cache_misses[] == old_misses
      end
      resize!(cache, 0)
      for i in 1:3
        @test reconstruct(algo, i) == reconstruct(cached_algo, i)
      end
      @test cache_misses[] == old_misses + 3 
    end

  end

  @testset "RecoPlan" begin
    cache_misses = Ref(0)
    cached_parameter = PureCacheableParameter(3, cache_misses)
    cache = ProcessResultCache(; param = cached_parameter, maxsize = 1)

    plan = toPlan(cache)
    setAll!(plan, :maxsize, 3)
    @test plan.cache.maxsize == 3

    process(CacheableAlgorithm, cache, 42)
    @test length(keys(cache.cache)) == 1
    empty!(cache)
    @test length(keys(cache.cache)) == 0
    process(CacheableAlgorithm, cache, 42)
    @test plan.cache == cache.cache
    @test length(keys(cache.cache)) == 1
    empty!(plan)
    @test length(keys(cache.cache)) == 0

    clear!(plan)
    io = IOBuffer()
    toTOML(io, plan)
    seekstart(io)
    planCopy = loadPlan(io, [Main, AbstractImageReconstruction])

    setAll!(planCopy, :factor, 3)
    setAll!(planCopy, :cache_misses, Ref(0))
    copy1 = build(planCopy)
    copy2 = build(planCopy)
    @test copy1.cache == copy2.cache
    resize!(copy1, 42)

    @test copy2.cache.maxsize == 42
  end

end