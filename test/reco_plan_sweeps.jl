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
      
      # Test iterate
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
      
      # Test root returned
      for plan in sweep
          @test AbstractTrees.parent(plan) === nothing  # New copes have no parent
      end

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
      # TODO
    end

    @testset "Product" begin
      # TODO
    end
  end
  
  @testset "Error detection" begin
    @testset "Invalid values" begin
      # TODO
    end

    @testset "Field is not part of RecoPlan" begin
      # TODO
    end

    @testset "Duplicate field in product" begin
      # TODO
    end
    
    @testset "Duplicate field in zip" begin
      # TODO
    end
    
    @testset "Length mismatch in zip" begin
      # TODO
    end
  end
end
