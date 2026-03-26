
using Base.Iterators: product, zip

export PlanSweep, plan_sweep, @plan_sweep
"""
    PlanSweep{T}

A parameter sweep specification that iterates over values for a specific field of a `RecoPlan`.

Each `PlanSweep` targets one concrete `RecoPlan` and modifies one of its fields with different values.
The parameter type `T` corresponds to the type of values in the sweep.

# Fields
- `plan::RecoPlan`: The base configuration template
- `field::Symbol`: The field to vary
- `values::Vector{T}`: The values to iterate over

# Example
```julia
base = RecoPlan(...)

sweep = PlanSweep(base, :iterations, [1, 5, 10])
for plan in sweep
  algo = build(plan)
  # ... use algorithm
end

# Multi-parameter grid via product
sweep1 = PlanSweep(base, :iterations, [1, 2])
sweep2 = PlanSweep(base, :reg, [0.001, 0.01])

for plan in Iterators.product(sweep1, sweep2)
  algo = build(plan)
end
```
"""
struct PlanSweep{T, P}
  plan::RecoPlan{P}
  field::Symbol
  values::Vector{T}
  function PlanSweep(plan::RecoPlan{P}, field::Symbol, values::Vector{T}) where {T,P}
    if !all([validvalue(plan, type(plan, field), v) for v in values])
      throw(ArgumentError("Field $field sweeps over values with an invalid type"))
    end
    return new{T, P}(plan, field, values)
  end
end
Base.summary(ps::PlanSweep) = "PlanSweep($(typeof(root(ps.plan))), field=$(ps.field), nvalues=$(length(ps)))"
Base.show(io::IO, ps::PlanSweep) = print(io, summary(ps))
function Base.show(io::IO, ::MIME"text/plain", ps::PlanSweep)
    println(io, summary(ps))
    # Show a small preview of values
    n = length(ps)
    maxpreview = 5
    vals = n <= maxpreview ? ps.values : vcat(ps.values[1:maxpreview], ["…"])
    print(io, "  values = ")
    show(io, vals)
end


function PlanSweep(plan::RecoPlan, field::Symbol, values)
  return PlanSweep(plan, field, collect(values))
end

struct ProdSweep
  sweeps::Vector{PlanSweep}
end
Base.summary(ps::ProdSweep) = "ProdSweep($(length(ps.sweeps)) sweeps, total_combinations=$(length(ps)))"
Base.show(io::IO, ps::ProdSweep) = print(io, summary(ps))
function Base.show(io::IO, ::MIME"text/plain", ps::ProdSweep)
    println(io, summary(ps))
    for (i, s) in enumerate(ps.sweeps)
        println(io, "  [$i] ", summary(s))
    end
end

struct ZipSweep
  sweeps::Vector{PlanSweep}
end
Base.summary(zs::ZipSweep) = "ZipSweep($(length(zs.sweeps)) sweeps, length=$(length(zs)))"
Base.show(io::IO, zs::ZipSweep) = print(io, summary(zs))
function Base.show(io::IO, ::MIME"text/plain", zs::ZipSweep)
    println(io, summary(zs))
    for (i, s) in enumerate(zs.sweeps)
        println(io, "  [$i] ", summary(s))
    end
end

function root(plan::RecoPlan)
  p = plan
  while parent(p) !== nothing
    p = parent(p)
  end
  return p
end

function Base.getindex(sweep::PlanSweep, i::Int)
  if i < 1 || i > length(sweep.values)
    throw(IndexError("index $i out of range [1, $(length(sweep.values))]"))
  end
  
  setproperty!(sweep.plan, sweep.field, sweep.values[i])
  return root(sweep.plan)
end

function (sweep::PlanSweep)(i::Int)
  if i < 1 || i > length(sweep.values)
    throw(IndexError("index $i out of range [1, $(length(sweep.values))]"))
  end
  return sweep.field => sweep.values[i]
end

function (sweep::ProdSweep)(i::Int)
  if i < 1 || i > length(sweep)
    throw(IndexError("index $i out of range [1, $(length(sweep))]"))
  end
  indices = Tuple(CartesianIndices(Tuple(length.(sweep.sweeps))))[i].I
  return tuple((sweep_i.field => sweep_i.values[idx] for (sweep_i, idx) in zip(sweep.sweeps, indices))...)
end

function (sweep::ZipSweep)(i::Int)
  if i < 1 || i > length(sweep)
    throw(IndexError("index $i out of range [1, $(length(sweep))]"))
  end
  return tuple((sweep_i.field => sweep_i.values[i] for sweep_i in sweep.sweeps)...)
end

function Base.getindex(sweep::ProdSweep, i::Int)
  indices = Tuple(CartesianIndices(Tuple(length.(sweep.sweeps))))[i].I
  for (sweep_i, idx) in zip(sweep.sweeps, indices)
    setproperty!(sweep_i.plan, sweep_i.field, sweep_i.values[idx])
  end
  return root(sweep.sweeps[1].plan)
end

function Base.getindex(sweep::ZipSweep, i::Int)
  for sweep_i in sweep.sweeps
    setproperty!(sweep_i.plan, sweep_i.field, sweep_i.values[i])
  end
  return root(sweep.sweeps[1].plan)
end

Base.length(sweep::PlanSweep) = length(sweep.values)
Base.length(sweep::ProdSweep) = prod(length, sweep.sweeps)
Base.length(sweep::ZipSweep) = length(sweep.sweeps[1])

Base.eltype(sweep::PlanSweep) = typeof(root(sweep.plan))
Base.eltype(sweep::ProdSweep) = eltype(first(sweep.sweeps))
Base.eltype(sweep::ZipSweep) = eltype(first(sweep.sweeps))

Base.iterate(sweep::PlanSweep) = (getindex(sweep, 1), 2)
function Base.iterate(sweep::PlanSweep, i::Int)
  if i > length(sweep.values)
    return nothing
  end
  return (getindex(sweep, i), i + 1)
end

Base.iterate(sweep::ProdSweep) = (getindex(sweep, 1), 2)
function Base.iterate(sweep::ProdSweep, i::Int)
  if i > length(sweep)
    return nothing
  end
  return (getindex(sweep, i), i + 1)
end

Base.iterate(sweep::ZipSweep) = (getindex(sweep, 1), 2)
function Base.iterate(sweep::ZipSweep, i::Int)
  if i > length(sweep)
    return nothing
  end
  return (getindex(sweep, i), i + 1)
end



function parse_dot_path(ex, fields = [])
  if ex isa Symbol
    return :($ex), fields
  end
  if Meta.isexpr(ex, :(.))
    remaining, last_field = ex.args
    pushfirst!(fields, last_field)
    return parse_dot_path(remaining, fields)
  end
  error("Expected plan.field notation, got $ex")
end

function build_getproperty_chain(base, fields::Vector)
  if isempty(fields)
    return base
  end
  expr = base
  for field in fields
    expr = :((getproperty($expr, $field)))
  end
  return expr
end

function create_plan_sweep(ex)
  if Meta.isexpr(ex, :(=))
    lhs, rhs = ex.args
    base, fields = parse_dot_path(lhs)
    
    if isempty(fields)
      error("Expected plan.field notation, got $lhs")
    end
    
    if length(fields) == 2
      parent_plan = base
      sweep_field = fields[1]
    else
      parent_plan = build_getproperty_chain(base, fields[1:end-1])
      sweep_field = last(fields)
    end
    
    return :(PlanSweep($(esc(parent_plan)), $(esc(sweep_field)), $(esc(rhs))))
  else
    error("Expected plan.parameter = iter notation, got $ex")
  end
end

"""
    @plan_sweep plan.parameter.pre.iterations = [1, 10, 15]

Create a PlanSweep using an assignment syntax
"""
macro plan_sweep(ex)
  return create_plan_sweep(ex)
end

"""
    Iterators.product(sweeps::PlanSweep...)

Create a product of `PlanSweeps` that iterates over the Cartesian product of multiple `PlanSweep` objects.
Each sweep must target a different field of the same root plan. The iteration yields all
combinations of sweep values in a grid-like fashion.

# Example
```julia
iter = Iterators.product(
  @plan_sweep(plan.parameter.reco.iterations = [1, 10, 100]),
  @plan_sweep(plan.parameter.reco.solver = [CGNR, Kaczmarz])
)
for p in iter
  algo = build(p)
  # Runs 6 combinations: (1,CGNR), (10,CGNR), (100,CGNR), (1,Kaczmarz), (10,Kaczmarz), (100,Kaczmarz)
end
```

Throws
- ArgumentError if sweeps don't share the same root plan
- ArgumentError if duplicate sweeps target the same plan-field combination
"""
function Iterators.product(sweeps::PlanSweep...)
  if length(unique([root(sweep.plan) for sweep in sweeps])) != 1
    throw(ArgumentError("Sweeps don't all share the same root"))
  end

  seen = Set{Tuple{RecoPlan, Symbol}}()
  for sweep in sweeps
    key = (sweep.plan, sweep.field)
    if key in seen
      throw(ArgumentError("Duplicate sweep: plan $(typeof(sweep.plan)) with field $(sweep.field) already in product"))
    end
    push!(seen, key)
  end
  
  return ProdSweep(collect(sweeps))
end

"""
    Iterators.zip(sweeps::PlanSweep...)

Create a zipped `PlanSweep` that iterates over multiple `PlanSweep` objects in parallel.
Each sweep must have the same length and must target different fields of the same root plan.
The iteration yields plans where all sweeps are applied simultaneously.

# Example
```julia
iter = Iterators.zip(
  @plan_sweep(plan.parameter.reco.iterations = [1, 10, 100]),
  @plan_sweep(plan.parameter.reco.solver = [CGNR, Kaczmarz, FISTA])
)
for p in iter
  algo = build(p)
  # Runs 3 combinations: (1,CGNR), (10,Kaczmarz), (100,GMRES)
end
```

# Throws
- ArgumentError if sweeps don't share the same root plan
- ArgumentError if sweeps have different lengths
- ArgumentError if duplicate sweeps target the same plan-field combination
"""
function Iterators.zip(sweeps::PlanSweep...)
  if length(unique([root(sweep.plan) for sweep in sweeps])) != 1
    throw(ArgumentError("Sweeps don't all share the same root"))
  end

  lengths = length.(sweeps)
  if length(unique(lengths)) > 1
      throw(ArgumentError("All PlanSweeps must have same length for zip"))
  end
  
  seen = Set{Tuple{RecoPlan, Symbol}}()
  for sweep in sweeps
      key = (sweep.plan, sweep.field)
      if key in seen
          throw(ArgumentError("Duplicate sweep: plan $(typeof(sweep.plan)) with field $(sweep.field) already in zip"))
      end
      push!(seen, key)
  end
  
  return ZipSweep(collect(sweeps))
end
