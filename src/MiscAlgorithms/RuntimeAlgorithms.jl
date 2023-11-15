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

mutable struct QueuedProcessAlgorithm <: AbstractMultiThreadedProcessing
  threads::Vector{Int64}
  threadTasks::Vector{Union{Task, Nothing}}
  inputChannel::Channel{Any}
  inputOrder::Channel{Int64}
  outputChannels::Vector{Channel{Any}}
  processLock::ReentrantLock
end
QueuedProcessAlgorithm(threads::Vector{Int64}) = QueuedProcessAlgorithm(threads, [nothing for i = 1:length(threads)], Channel{Any}(Inf), Channel{Int64}(Inf), [Channel{Any}(Inf) for i = 1:length(threads)], ReentrantLock())
QueuedProcessAlgorithm(threads::UnitRange) = QueuedProcessAlgorithm(collect(threads))
function put!(algo::QueuedProcessAlgorithm, inputs...)
  lock(algo.processLock) do
    threadNum = pickThread(algo)
    if isnothing(threadNum)
      put!(algo.inputChannel, inputs)
    else
      put!(algo.inputOrder, threadNum)
      algo.threadTasks[threadNum] = @tspawnat algo.threads[threadNum] processThread(algo, threadNum, inputs...)
    end
  end
end

function pickThread(algo::QueuedProcessAlgorithm)
  choices = map(x -> isnothing(x) || istaskdone(x), algo.threadTasks)
  return findfirst(choices)
end
function processThread(algo::QueuedProcessAlgorithm, threadNum, args...)
  processInputs(algo, threadNum, args...)
  while isready(algo.inputChannel)
    args = nothing
    lock(algo.processLock) do 
      # Check that the channel wasn't emptied while waiting on the lock
      if isready(algo.inputChannel)
        args = take!(algo.inputChannel)
      end
    end
    # Processing outside of lock to not block it
    if !isnothing(args)
      put!(algo.inputOrder, threadNum)
      processInputs(algo, threadNum, args...)
    end
  end
end
function processInputs(algo::QueuedProcessAlgorithm, threadNum, args...)
  output = algo.outputChannels[threadNum]
  result = nothing
  try
    result = process(args...)
  catch e
    @error "Error in image processing thread $(algo.threads[threadNum])" exception=(e, catch_backtrace())
    result = e
  end
  put!(output, result)
end
process(fn::Function, args...) = fn(args...)

function take!(algo::QueuedProcessAlgorithm)
  outputOrder = take!(algo.inputOrder)
  return take!(algo.outputChannels[outputOrder])
end

nthreads(algo::QueuedProcessAlgorithm) = length(algo.threads)

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
  scheduler::QueuedProcessAlgorithm
end
MultiThreadedAlgorithm(params::MultiThreadedAlgorithmParameter) = MultiThreadedAlgorithm(params, QueuedProcessAlgorithm(params.threadIDs))
put!(algo::MultiThreadedAlgorithm, inputs...) = put!(algo.params.algo, MultiThreadedInput(algo.scheduler, inputs))
take!(algo::MultiThreadedAlgorithm) = take!(algo.params.algo)