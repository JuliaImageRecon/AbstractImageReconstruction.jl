export ThreadPinnedAlgorithm, ThreadPinnedAlgorithmParameter
Base.@kwdef struct ThreadPinnedAlgorithmParameter <: AbstractImageReconstructionParameters
  threadID::Int64
  algo::AbstractImageReconstructionAlgorithm
end

mutable struct ThreadPinnedAlgorithm <: AbstractImageReconstructionAlgorithm
  params::ThreadPinnedAlgorithmParameter
  recoTask::Union{Nothing,Task}
  taskLock::ReentrantLock
  inputChannel::Channel{Any}
  outputChannel::Channel{Any}
end

ThreadPinnedAlgorithm(params::ThreadPinnedAlgorithmParameter) = ThreadPinnedAlgorithm(params, nothing, ReentrantLock(), Channel{Any}(Inf), Channel{Any}(Inf))

take!(algo::ThreadPinnedAlgorithm) = take!(algo.outputChannel)
function put!(algo::ThreadPinnedAlgorithm, u)
  put!(algo.inputChannel, u)
  lock(algo.taskLock)
  try
    if isnothing(algo.recoTask) || istaskdone(algo.recoTask)
      algo.recoTask = @tspawnat algo.params.threadID pinnedRecoTask(algo)
    end
  finally
    unlock(algo.taskLock)
  end
end
function pinnedRecoTask(algo::ThreadPinnedAlgorithm)
  while isready(algo.inputChannel)
    result = nothing
    try
      put!(algo.params.algo, take!(algo.inputChannel))
      result = take!(algo.params.algo)
    catch e
      result = e
    end
    put!(algo.outputChannel, result)
  end
end
# TODO general async task, has to preserve order (cant just spawn task for each put)
# TODO Timeout task with timeout options for put and take
# TODO maybe can be cancelled?

export AbstractMultiThreadedProcessing
abstract type AbstractMultiThreadedProcessing <: AbstractImageReconstructionAlgorithm end

mutable struct RoundRobinProcessAlgorithm <: AbstractMultiThreadedProcessing
  threads::Vector{Int64}
  threadNum::Int64
  threadTasks::Vector{Union{Task, Nothing}}
  inputChannels::Vector{Channel{Any}}
  inputOrder::Channel{Int64}
  outputChannels::Vector{Channel{Any}}
  processLock::ReentrantLock
end
RoundRobinProcessAlgorithm(threads::Vector{Int64}) = RoundRobinProcessAlgorithm(threads, 1, [nothing for i = 1:length(threads)], [Channel{Any}(Inf) for i = 1:length(threads)], Channel{Int64}(Inf), [Channel{Any}(Inf) for i = 1:length(threads)], ReentrantLock())
RoundRobinProcessAlgorithm(threads::UnitRange) = RoundRobinProcessAlgorithm(collect(threads))
function put!(algo::RoundRobinProcessAlgorithm, innerAlgo::AbstractImageReconstructionAlgorithm, params::AbstractImageReconstructionParameters, inputs...)
  lock(algo.processLock) do
    threadNum = algo.threadNum
    task = algo.threadTasks[threadNum]
    put!(algo.inputChannels[threadNum], (innerAlgo, params, inputs))
    put!(algo.inputOrder, threadNum)
    if isnothing(task) || istaskdone(task)
      algo.threadTasks[threadNum] = @tspawnat algo.threads[threadNum] processInputs(algo, threadNum)
    end
    algo.threadNum = mod1(algo.threadNum + 1, length(algo.threads)) 
  end
end

function processInputs(algo::RoundRobinProcessAlgorithm, threadNum)
  input = algo.inputChannels[threadNum]
  output = algo.outputChannels[threadNum]
  while isready(input)
    result = nothing
    try
      inner, params, inputs = take!(input)
      result = process(inner, params, inputs...)
    catch e
      @error "Error in image processing thread $(algo.threads[threadNum])" exception=(e, catch_backtrace())
      result = e
    end
    put!(output, result)
  end
end

function take!(algo::RoundRobinProcessAlgorithm)
  outputOrder = take!(algo.inputOrder)
  return take!(algo.outputChannels[outputOrder])
end

export MultiThreadedAlgorithmParameter, MultiThreadedAlgorithm, MultiThreadedInput
struct MultiThreadedInput
  scheduler::AbstractMultiThreadedProcessing
  inputs::Tuple
end
Base.@kwdef struct MultiThreadedAlgorithmParameter <: AbstractImageReconstructionParameters
  threadIDs::Union{Vector{Int64}, UnitRange{Int64}}
  algo::AbstractImageReconstructionAlgorithm
end

mutable struct MultiThreadedAlgorithm <: AbstractImageReconstructionAlgorithm
  params::MultiThreadedAlgorithmParameter
  scheduler::RoundRobinProcessAlgorithm
end
MultiThreadedAlgorithm(params::MultiThreadedAlgorithmParameter) = MultiThreadedAlgorithm(params, RoundRobinProcessAlgorithm(params.threadIDs))
put!(algo::MultiThreadedAlgorithm, inputs...) = put!(algo.params.algo, MultiThreadedInput(algo.scheduler, inputs))
take!(algo::MultiThreadedAlgorithm) = take!(algo.params.algo)