@testset "Caching" begin
  @parameter mutable struct CacheableParameter <: AbstractImageReconstructionParameters
    factor::Int64
    cache_misses::Ref{Int64}
  end
  @parameter mutable struct PureCacheableParameter <: AbstractImageReconstructionParameters
    factor::Int64
    cache_misses::Ref{Int64}
  end

  @reconstruction mutable struct CacheableAlgorithm{P} <: AbstractImageReconstructionAlgorithm
    @parameter parameter::Union{P, ProcessResultCache{P}}
    value::Int64 = 1
  end

  function (parameter::CacheableParameter)(algo::CacheableAlgorithm, value)
    parameter.cache_misses[] += 1
    return algo.value + parameter.factor * value
  end
  function (parameter::Union{PureCacheableParameter, ProcessResultCache{PureCacheableParameter}})(algo::CacheableAlgorithm, value)
    return algo.value + parameter(typeof(algo), value)
  end
  function (parameter::PureCacheableParameter)(algo, value)
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

    cache(CacheableAlgorithm, 42)
    @test length(keys(cache.cache)) == 1
    empty!(cache)
    @test length(keys(cache.cache)) == 0
    cache(CacheableAlgorithm, 42)
    @test plan.cache == cache.cache
    @test length(keys(cache.cache)) == 1
    empty!(plan)
    @test length(keys(cache.cache)) == 0

    clear!(plan)
    io = IOBuffer()
    savePlan(io, plan)
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


  @testset "Hashing" begin
    # Algorithm hash:
    #  - depends on parameter and state fields (e.g. `value`)
    #  - does NOT depend on internal fields starting with "_" (e.g. `_channel`)

    param = CacheableParameter(3, Ref(0))
    algo1 = CacheableAlgorithm(param)
    algo2 = CacheableAlgorithm(param)

    # Different instances -> different channels
    @test algo1 !== algo2
    @test algo1._channel !== algo2._channel
    @test hash(algo1) == hash(algo2)

    # Changing a state field (`value`) changes the hash
    h_before = hash(algo1)
    algo1.value += 1
    @test hash(algo1) != h_before

    @parameter mutable struct HashParam <: AbstractImageReconstructionParameters
      a::Int
      _b::Int
    end
    p = HashParam(1, 2)
    h_param = hash(p)
    p._b = 42
    @test hash(p) == h_param
    p.a = 7
    @test hash(p) != h_param

    # Falls back to objectid based hash
    @parameter hash = false mutable struct NoHashParam <: AbstractImageReconstructionParameters
      a::Int64 = 42
    end
    p = NoHashParam()
    p2 = NoHashParam()
    @test hash(p) != hash(p2)

    @reconstruction hash = false mutable struct NoHashAlgorithm{P} <: AbstractImageReconstructionAlgorithm
      @parameter parameter::Union{P, ProcessResultCache{P}}
      value::Int64 = 1
    end
    algo = NoHashAlgorithm(p)
    algo2 = NoHashAlgorithm(p)
    @test hash(algo) != hash(algo2)

  end

end