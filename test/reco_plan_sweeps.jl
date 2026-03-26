@testset "PlanSweep" begin

  @parameter struct SweepParams <: AbstractTestParameters
    value::Float64 = 1.0
    iterations::Int = 10
    reg::Float64 = 0.01
  end

  @parameter struct NestedParams <: AbstractTestParameters
    pre::SweepParams = SweepParams()
    reco::SweepParams = SweepParams()
  end
  
  @reconstruction struct SweepAlgorithm <: AbstractTestBase
    @parameter parameter::NestedParams
  end


  pre = SweepParams(reg = 0.001)
  reco = SweepParams(iterations = 5)
  nested_params = NestedParams(pre, reco)
  algo = SweepAlgorithm(nested_params)
  base = toPlan(algo)
  
  @testset "Construction" begin  
    sweep1 = PlanSweep(base.parameter.pre, :value, [1.0, 2.0, 3.0])
    @test sweep1.plan isa RecoPlan{SweepParams}
    @test sweep1.field == :value
    @test sweep1.values == [1.0, 2.0, 3.0]
    @test sweep1 isa PlanSweep{Float64}
    
    sweep2 = PlanSweep(base.parameter.pre, :iterations, [5, 10, 15])
    @test sweep2.values == [5, 10, 15]
    @test sweep2 isa PlanSweep{Int}
    
    sweep3 = PlanSweep(base.parameter.pre, :value, 1.0:0.5:2.0)
    @test sweep3.values == [1.0, 1.5, 2.0]
  end
  
  @testset "Iteration" begin
      base_plan = RecoPlan(SweepParams)
      sweep = PlanSweep(base_plan, :value, [1.0, 2.0, 3.0])
      
      # Test iterate (uses getindex internally)
      plans = collect(sweep)
      @test length(plans) == 3
      @test all(p -> p isa RecoPlan, plans)
      
      # Verify each plan has correct value
      @test plans[1].value == 1.0
      @test plans[2].value == 2.0
      @test plans[3].value == 3.0
      
      # Test length
      @test length(sweep) == 3
      
      # Test eltype
      @test eltype(sweep) <: RecoPlan
      
      # Test root returned, and that copies are independent roots
      for plan in sweep
        @test AbstractTrees.parent(plan) === nothing
      end
      plans2 = collect(sweep)
      @test plans2[1] !== plans2[2] !== plans2[3]

      # Test key-value:
      @test all(sweep(i)[1] == :value for i = 1:3)
      @test sweep(1)[2] == 1.0
      @test sweep(2)[2] == 2.0
      @test sweep(3)[2] == 3.0
  end
  
  @testset "Single Parameter Sweep" begin
      @testset "SweepParams: Not nested" begin
        base_plan = RecoPlan(SweepParams)
        sweep = PlanSweep(base_plan, :value, [0.1, 0.5, 1.0])
        
        @test length(sweep) == 3
        @test first(iterate(sweep, 1)).value == 0.1
        @test first(iterate(sweep, 2)).value == 0.5
        @test first(iterate(sweep, 3)).value == 1.0
        @test typeof(first(iterate(sweep, 1))) == typeof(base_plan) 
      end

      @testset "SweepParams: Not nested via macro" begin
        base_plan = RecoPlan(SweepParams)
        sweep = @plan_sweep base_plan.value = [0.1, 0.5, 1.0]
        
        @test length(sweep) == 3
        @test first(iterate(sweep, 1)).value == 0.1
        @test first(iterate(sweep, 2)).value == 0.5
        @test first(iterate(sweep, 3)).value == 1.0
        @test typeof(first(iterate(sweep, 1))) == typeof(base_plan) 
      end

      @testset "SweepParams: nested" begin
        base_plan = RecoPlan(NestedParams, pre = RecoPlan(SweepParams))
        sweep = PlanSweep(base_plan.pre, :value, [0.1, 0.5, 1.0])
        
        @test length(sweep) == 3
        @test first(iterate(sweep, 1)).pre.value == 0.1
        @test first(iterate(sweep, 2)).pre.value == 0.5
        @test first(iterate(sweep, 3)).pre.value == 1.0
        @test typeof(first(iterate(sweep, 1))) == typeof(base_plan) 
      end
      
      @testset "SweepParams: nested via macro" begin
        base_plan = RecoPlan(NestedParams, pre = RecoPlan(SweepParams))
        sweep = @plan_sweep base_plan.pre.value = [0.1, 0.5, 1.0]
        
        @test length(sweep) == 3
        @test first(iterate(sweep, 1)).pre.value == 0.1
        @test first(iterate(sweep, 2)).pre.value == 0.5
        @test first(iterate(sweep, 3)).pre.value == 1.0
        @test typeof(first(iterate(sweep, 1))) == typeof(base_plan) 
      end
  end
  
  @testset "Multiple Sweeps" begin
    @testset "Zip" begin
      # Two fields of the same base plan
      base_plan = RecoPlan(SweepParams)
      sweep_val = PlanSweep(base_plan, :value, [0.1, 0.5, 1.0])
      sweep_it  = PlanSweep(base_plan, :iterations, [1, 2, 3])

      z = Iterators.zip(sweep_val, sweep_it)
      @test z isa AbstractImageReconstruction.ZipSweep
      @test length(z) == 3
      @test eltype(z) == eltype(sweep_val) == eltype(sweep_it)

      # Check plans for each index
      p1 = z[1]
      p2 = z[2]
      p3 = z[3]

      @test p1.value == 0.1 && p1.iterations == 1
      @test p2.value == 0.5 && p2.iterations == 2
      @test p3.value == 1.0 && p3.iterations == 3

      # Each plan is a fresh root
      @test AbstractTrees.parent(p1) === nothing
      @test AbstractTrees.parent(p2) === nothing
      @test AbstractTrees.parent(p3) === nothing
      @test p1 !== p2 !== p3

      # Functor returns (field=>value, field=>value, ...)
      kvs1 = z(1)
      @test kvs1[1] == (:value => 0.1)
      @test kvs1[2] == (:iterations => 1)
    end

    @testset "Product" begin
      base_plan = RecoPlan(SweepParams)
      sweep_val = PlanSweep(base_plan, :value, [0.1, 0.5])
      sweep_it  = PlanSweep(base_plan, :iterations, [1, 2, 3])

      prod_sweep = Iterators.product(sweep_val, sweep_it)
      @test prod_sweep isa AbstractImageReconstruction.ProdSweep
      @test length(prod_sweep) == 2 * 3 == 6
      @test eltype(prod_sweep) == eltype(sweep_val) == eltype(sweep_it)

      # Expected combinations
      expected = collect(Base.Iterators.product([0.1, 0.5], [1, 2, 3]))

      for i in 1:length(prod_sweep)
          p = prod_sweep[i]
          @test p.value == expected[i][1]
          @test p.iterations == expected[i][2]
          @test AbstractTrees.parent(p) === nothing
      end

      # Functor returns tuples of field=>value pairs
      kvs = prod_sweep(1)
      @test length(kvs) == 2
      @test :value in first.(kvs) && :iterations in first.(kvs)
    end
  end
  
  @testset "Error detection" begin
    @testset "Invalid values" begin
      base_plan = RecoPlan(SweepParams)

      # iterations is Int; strings are invalid
      @test_throws ArgumentError PlanSweep(base_plan, :iterations, ["a", "b"])

      # reg is Float64; symbols are invalid
      @test_throws ArgumentError PlanSweep(base_plan, :reg, [:x, :y])
    end

    @testset "Field is not part of RecoPlan" begin
      base_plan = RecoPlan(SweepParams)

      # Non-existent field in constructor
      @test_throws ErrorException PlanSweep(base_plan, :nonexistent, [1, 2])

      # Non-existent field via macro
      @test_throws ErrorException begin
        @plan_sweep base_plan.nonexistent = [1, 2]
      end
    end

    @testset "Duplicate field in product" begin
      base_plan = RecoPlan(SweepParams)
      s1 = PlanSweep(base_plan, :value, [0.1, 0.5])
      s2 = PlanSweep(base_plan, :value, [1.0, 2.0])

      @test_throws ArgumentError Iterators.product(s1, s2)
    end
    
    @testset "Duplicate field in zip" begin
      base_plan = RecoPlan(SweepParams)
      s1 = PlanSweep(base_plan, :value, [0.1, 0.5])
      s2 = PlanSweep(base_plan, :value, [1.0, 2.0])

      @test_throws ArgumentError Iterators.zip(s1, s2)
    end
    
    @testset "Length mismatch in zip" begin
      base_plan = RecoPlan(SweepParams)
      s1 = PlanSweep(base_plan, :value, [0.1, 0.5])
      s2 = PlanSweep(base_plan, :iterations, [1, 2, 3])

      @test_throws ArgumentError Iterators.zip(s1, s2)
    end

    @testset "Root mismatch in product/zip" begin
      base1 = RecoPlan(SweepParams)
      base2 = RecoPlan(SweepParams)

      s1 = PlanSweep(base1, :value, [0.1, 0.5])
      s2 = PlanSweep(base2, :iterations, [1, 2])

      @test_throws ArgumentError Iterators.product(s1, s2)
      @test_throws ArgumentError Iterators.zip(s1, s2)
    end
  end
end