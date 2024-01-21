if Debug then Debug.beginFile "TaskProcessor" end
OnInit.module("TaskProcessor", function(require)
    require "TimerQueue"
    require "TaskSubject"
    require "DoublyLinkedList"

    local WC3_OP_LIMIT = 1666666 -- JASS's max OP limit, used as reference to how many operations would lua be able to do without in-game lags. Very experimental and not yet confirmed.
    -- How many operations can all processors in total use up in comparison to WC3_OP_LIMIT constant.
    -- Leftover is used up by the game's internal machinations and other triggers not registered with any processor.
    local GLOBAL_PROCESS_RATIO = 0.8 -- from 0.0 to 1.0
    local GAME_TICK = 0.02
    local GAME_TICK_INVERSE = 1 / GAME_TICK

    -- ========================================= --
    -- Internal variables --
    -- ========================================= --
    local globalProcessOpLimit = WC3_OP_LIMIT * GLOBAL_PROCESS_RATIO * GAME_TICK
    local processors = {} --- @type Processor[]

    local function refreshProcessorsOpLimits()
        if #processors == 0 then return end
        local totalRatio = 0
        for _, processor in ipairs(processors) do
            totalRatio = totalRatio + processor.ratio;
        end
        for _, processor in ipairs(processors) do
            processor.opLimit = globalProcessOpLimit * (processor.ratio / totalRatio)
        end
    end

    ---@class Task
    ---@field fn fun(delay: number): any
    ---@field opCount integer
    ---@field promise TaskSubject
    ---@field requestTime number
    Task = {}
    Task.__index = Task

    ---@param fn fun(delay: number)
    ---@param opCount integer
    ---@param currentTime number
    ---@return Task
    local function createTask(fn, opCount, currentTime)
        return setmetatable({
            fn = fn,
            opCount = opCount,
            requestTime = currentTime
        }, Task)
    end

    ---@class PeriodicTask : Task
    ---@field period number
    ---@field fn fun(delay: number): boolean done
    PeriodicTask = setmetatable({}, Task)
    PeriodicTask.__index = PeriodicTask

    ---@param task Task
    ---@param period number
    ---@return PeriodicTask
    local function createPeriodicTask(task, period)
        task--[[@as PeriodicTask]].period = period
        return setmetatable(task, PeriodicTask) --[[@as PeriodicTask]]
    end

    ---@class CompositeTask: Task
    ---@field fn fun(delay: number): unknown?
    ---@field composite true
    CompositeTask = setmetatable({}, Task)
    CompositeTask.__index = CompositeTask

    ---@return CompositeTask
    function CompositeTask:clone()
        return setmetatable({
            fn = self.fn,
            opCount = self.opCount,
            requestTime = self.requestTime,
            promise = self.promise,
            composite = true,
        }, CompositeTask) --[[@as CompositeTask]]
    end

    local function compositeTask(fn, opCount, currentTime)
        return setmetatable({
            fn = fn,
            opCount = opCount,
            requestTime = currentTime,
            composite = true
        }, CompositeTask)
    end

    ---@class TaskBucket
    ---@field tasks LinkedListHead
    ---@field opCount integer

    ---@param processor Processor
    ---@param task Task
    local function enqueueToAvailableTaskBucket(processor, task)
        if processor.taskExecutor.paused then
            processor.taskExecutor:resume()
        end
        local chosenBucket ---@type TaskBucket
        if processor.taskBuckets then
            for index, bucket in ipairs(processor.taskBuckets) do
                if index == processor.currentBucketIndex then
                    if task --[[@as CompositeTask]].composite and processor.currentOperations + task.opCount <= processor.opLimit then
                        chosenBucket = bucket
                        break
                    end
                elseif bucket.opCount + task.opCount <= processor.opLimit then
                    chosenBucket = bucket
                    break
                end
            end
        end

        if chosenBucket == nil then
            chosenBucket = LinkedList.create()
            chosenBucket:insert(task, true)
            table.insert(processor.taskBuckets, { tasks = chosenBucket, opCount = task.opCount } --[[@as TaskBucket]])
        else
            chosenBucket.tasks:insert(task, true)
            chosenBucket.opCount = chosenBucket.opCount + task.opCount
        end
    end

    ---@class Processor
    ---@field ratio integer -- readOnly
    ---@field opLimit integer -- readOnly, how many operations can this processor do in a game-tick
    ---@field taskBuckets TaskBucket[] -- readOnly, don't touch!
    ---@field taskExecutor TimerQueue -- readOnly
    ---@field clock Stopwatch -- readOnly
    ---@field currentBucketIndex integer -- readOnly
    ---@field currentOperations integer -- readOnly
    Processor = {}
    Processor.__index = Processor

    ---@param bucket TaskBucket
    ---@param task LinkedListNode
    local function dequeueTask(bucket, task)
        bucket.opCount = bucket.opCount - task.value --[[@as Task]].opCount
        task:remove()
    end

    ---@param task Task
    ---@param delay number
    ---@param status boolean
    ---@param ... unknown
    ---@return unknown?
    local function propagateResults(task, delay, status, ...)
        if status == true then
            task.promise:onNext(delay, ...)
        else
            task.promise:onError(delay, ...)
            task.promise:onCompleted(delay)
            return
        end

        return select(1, ...)
    end

    ---@param processor Processor
    ---@param bucket TaskBucket
    ---@param currentTime number
    local function processTasks(processor, bucket, currentTime)
        if bucket.tasks.n > 0 then
            local taskNode = bucket.tasks.next
            local previousNode = bucket.tasks
            while taskNode ~= bucket.tasks.head do
                local task = taskNode --[[@as LinkedListNode]].value ---@type Task
                local delay = (currentTime - task.requestTime) * GAME_TICK_INVERSE
                local result = propagateResults(task, delay, pcall(task.fn, delay))

                processor.currentOperations = processor.currentOperations + task.opCount

                if task --[[@as PeriodicTask]].period and result == false then
                    task.requestTime = currentTime
                elseif task --[[@as CompositeTask]].composite and result then
                    local currentTask = taskNode
                    taskNode, previousNode = previousNode, previousNode.prev
                    dequeueTask(bucket, currentTask)
                    enqueueToAvailableTaskBucket(processor, task --[[@as CompositeTask ]]:clone())
                else
                    local currentTask = taskNode
                    taskNode, previousNode = previousNode, previousNode.prev
                    dequeueTask(bucket, currentTask)
                    task.promise:onCompleted(delay)
                end
                previousNode = taskNode
                taskNode = taskNode.next
            end
        end
    end

    ---@param processor Processor
    local function process(processor)
        local bucketAmount = #processor.taskBuckets
        if bucketAmount == 0 then
            processor.taskExecutor:pause()
            return
        elseif processor.currentBucketIndex > bucketAmount then
            processor.currentBucketIndex = 1
        end

        local bucket = processor.taskBuckets[processor.currentBucketIndex]
        processTasks(processor, bucket, processor.clock:getElapsed())
        processor.currentOperations = 0

        if bucket.opCount == 0 then
            table.remove(processor.taskBuckets, processor.currentBucketIndex)
            if #processor.taskBuckets == 0 then
                processor.taskExecutor:pause()
                processor.currentBucketIndex = 1
            end
        else
            processor.currentBucketIndex = processor.currentBucketIndex + 1
        end
    end

    ---@param fn fun(delay: number):any or boolean if period is defined
    ---@param fnOpCount integer
    ---@param period number?
    ---@param composite boolean?
    ---@return TaskObservable
    function Processor:enqueueTask(fn, fnOpCount, period, composite)
        assert(type(fn) == "function", "Parameter 'fn' must be a function.")
        assert(type(fnOpCount) == "number" and math.floor(fnOpCount) == fnOpCount,
            "Parameter 'fnOpCount' must be an integer.")
        local task
        if composite then
            task = compositeTask(fn, fnOpCount, self.clock:getElapsed())
        else
            task = createTask(fn, fnOpCount, self.clock:getElapsed())
        end
        if period then
            assert(type(period) == 'number' and period > 0, "Parameter 'period' must be a number and higher than 0.")
            task = createPeriodicTask(task, period)
        end
        task.promise = TaskSubject.create()
        enqueueToAvailableTaskBucket(self, task)

        return task.promise --[[@as TaskObservable]]
    end

    ---@param ratio integer integer higher or equal to 1, will re-adjust this new processor and other existing processors op limit in comparison to these numbers.
    ---@return Processor
    function Processor.create(ratio)
        assert((type(ratio) == "number" and math.floor(ratio) == ratio), "Paramater 'ratio' must be an integer")
        assert(ratio >= 1, "Parameter 'ratio' must be higher or equal to 1")
        local instance = setmetatable({
            ratio = ratio,
            -- opLimit is set by refreshProcessorsOpLimits
            taskBuckets = {},
            taskExecutor = TimerQueue.create(),
            currentBucketIndex = 1,
            currentOperations = 0,
            clock = Stopwatch.create(true)
        }, Processor)
        table.insert(processors, instance)
        refreshProcessorsOpLimits()
        instance.taskExecutor:pause();
        instance.taskExecutor:callPeriodically(GAME_TICK, nil, process, instance)
        return instance
    end
end)
if Debug then Debug.endFile() end
