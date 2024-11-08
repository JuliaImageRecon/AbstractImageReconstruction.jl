function Base.show(io::IO, plan::RecoPlan{T}) where {T <: AbstractImageReconstructionAlgorithm}
  print(io, "RecoPlan{$T}")
end

function Base.show(io::IO, plan::RecoPlan{T}) where {T <: AbstractImageReconstructionParameters}
  print(io, "RecoPlan{$T}($(join(propertynames(plan), ", ")))")
end

function Base.show(io::IO, ::MIME"text/plain", plan::RecoPlan{T}) where {T}
  if get(io, :compact, false)
    show(io, plan)
  else
    showtree(io, plan)
  end
end

const INDENT = "   "
const PIPE   = "│  "
const TEE    = "├─ "
const ELBOW  = "└─ "


function showtree(io::IO, plan::RecoPlan{T}, indent::String = "", depth::Int=1) where {T}
  io = IOContext(io, :limit => true, :compact => true)

  if depth == 1
    print(io, indent, "RecoPlan{$T}", "\n")
  end

  props = propertynames(plan)
  for (i, prop) in enumerate(props)
    property = getproperty(plan, prop)
    showproperty(io, prop, property, indent, i == length(props), depth)
  end
end

function showproperty(io::IO, name, property, indent, islast, depth)
  print(io, indent, islast ? ELBOW : TEE, name, " = ", property, "\n")
end

function showproperty(io::IO, name, ::Missing, indent, islast, depth)
  print(io, indent, islast ? ELBOW : TEE, name, "\n")
end

function showproperty(io::IO, name, property::RecoPlan{T}, indent, islast, depth) where T
  print(io, indent, islast ? ELBOW : TEE, name, "::RecoPlan{$T}", "\n")
  showtree(io, property, indent * (islast ? INDENT : PIPE), depth + 1)
end