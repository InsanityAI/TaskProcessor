if Debug then Debug.beginFile "TaskProcessor" end
OnInit.module("TaskProcessor", function(require)
    require "TimerQueue"

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

    ---@param processor Processor
    ---@param task Task
    local function enqueueToAvailableTaskBucket(processor, task)
        if processor.taskExecutor.paused then
            processor.taskExecutor:resume()
        end
        local chosenBucket ---@type TaskBucket
        local taskOpCount = task:getOpCount()
        if processor.taskBuckets then
            for _, bucket in ipairs(processor.taskBuckets) do
                if bucket.opCount + taskOpCount <= processor.opLimit then
                    chosenBucket = bucket
                    break
                end
            end
        end

        if chosenBucket == nil then
            chosenBucket = LinkedList.create()
            chosenBucket:insert(task, true)
            table.insert(processor.taskBuckets, { tasks = chosenBucket, opCount = taskOpCount })
        else
            chosenBucket.tasks:insert(task, true)
            chosenBucket.opCount = chosenBucket.opCount + taskOpCount
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
    ---@param task TaskList
    local function dequeueTask(bucket, task)
        bucket.opCount = bucket.opCount - task.value:getOpCount()
        task:remove()
    end


    ---@param coroutineSuccess boolean|string
    ---@param taskResult string|boolean?
    local function isTaskToBeRepeated(coroutineSuccess, taskResult)
        if coroutineSuccess == false then
            return false
        else
            return taskResult == true
        end
    end

    ---@param processor Processor
    ---@param bucket TaskBucket
    ---@param currentTime number
    local function processTasks(processor, bucket, currentTime)
        if bucket.tasks.n > 0 then
            for taskNode in bucket.tasks:loop() do
                local task = taskNode --[[@as LinkedListNode]].value ---@type Task
                local delay = (currentTime - task.requestTime) * GAME_TICK_INVERSE
                local coroutineSuccess, taskResult = task:propagateResults(delay, coroutine.resume(task.taskThread, delay, table.unpack(task, 1, task.n)))
                processor.currentOperations = processor.currentOperations + task:getOpCount()

                if task.type == TaskType.REPEATING and isTaskToBeRepeated(coroutineSuccess, taskResult) then
                    task.requestTime = currentTime
                else
                    dequeueTask(bucket, taskNode)
                    task:finish(delay)
                end
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

    ---@alias TaskCallable thread|(fun(delay: integer, ...: unknown): repeat: boolean, ...)|{__call: fun(delay: integer, ...: unknown): repeat: boolean, ...}

    ---@param opCounts integer|integer[]
    local function validateCommonArgs(opCounts)
        local opCountsType = type(opCounts)
        if opCountsType == "table" then
            local count = 0
            for _, value in ipairs(opCounts) do
                assert(type(value) == "number", "opCount must be a number!")
                assert(value > 0, "opCount cannot be 0 or less!")
                count = count + 1
            end
            if not count then
                error("opCount must be a number or an array of numbers")
            end
        elseif opCountsType == "number" then
            assert(opCounts > 0, "opCount cannot be 0 or less!")
        else
            error("opCounts must either be a number or an array of numbers!")
        end
    end

    ---@param taskCallable TaskCallable
    ---@return "table"|"function"|"thread"
    local function getCallableType(taskCallable)
        local callableType = type(taskCallable)
        if callableType == 'table' then
            if taskCallable.__call then
                return "table"
            else
                error("Argument callable of table type does not contain __call metamethod!")
            end
        elseif callableType == 'function' then
            return "function"
        elseif callableType == 'thread' then
            return "thread"
        else
            error("Cannot call a non-callable object of type " .. callableType .. "!")
        end
    end

    ---@param table {__call: fun(delay: number, ...: unknown): ...: unknown}
    ---@return ...
    local function callCallableTable(delay, table, ...)
        return table(delay, ...)
    end

    ---@overload fun(self: Processor, taskCallable: TaskCallable, opCounts: number|number[], api: TaskAPI.REACTIVE,       ...: unknown): TaskObservable
    ---@overload fun(self: Processor, taskCallable: TaskCallable, opCounts: number|number[], api: TaskAPI.EVENT_LISTENER, ...: unknown): EventListener
    function Processor:enqueue(callable, opCounts, api, ...)
        validateCommonArgs(opCounts)
        local callableType = getCallableType(callable)
        local thread ---@type thread
        if callableType == 'table' then
            thread = coroutine.create(callCallableTable)
        elseif callableType == 'function' then
            thread = coroutine.create(callable)
        elseif callableType == 'thread' then
            thread = callable --[[@as thread]]
        end

        local task ---@type Task
        if api == TaskAPI.REACTIVE then
            if callableType == 'table' then
                task = ReactiveTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.ONESHOT, nil, callable, ...)
            else
                task = ReactiveTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.ONESHOT, nil, ...)
            end
        elseif api == TaskAPI.EVENT_LISTENER then
            if callableType == 'table' then
                task = EventListenerTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.ONESHOT, nil, callable, ...)
            else
                task = EventListenerTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.ONESHOT, nil, ...)
            end
        end

        enqueueToAvailableTaskBucket(self, task)

        if api == TaskAPI.REACTIVE then
            return task.observable
        elseif api == TaskAPI.EVENT_LISTENER then
            return task.eventListener
        end
    end

    ---@overload fun(self: Processor, taskCallable: TaskCallable, period: number, opCounts: number|number[], api: TaskAPI.REACTIVE, ...: unknown): TaskObservable
    ---@overload fun(self: Processor, taskCallable: TaskCallable, period: number, opCounts: number|number[], api: TaskAPI.EVENT_LISTENER, ...: unknown): EventListener
    function Processor:enqueuePeriodic(callable, period, opCounts, api, ...)
        validateCommonArgs(opCounts)
        assert(type(period) == "number", "Argument period must be a positive non-zero number!")
        assert(period > 0, "Argument period must be a positive non-zero number!")
        local callableType = getCallableType(callable)
        local thread ---@type thread
        if callableType == 'table' then
            thread = coroutine.create(callCallableTable)
        elseif callableType == 'function' then
            thread = coroutine.create(callable)
        elseif callableType == 'thread' then
            thread = callable --[[@as thread]]
        end

        local task ---@type Task
        if api == TaskAPI.REACTIVE then
            if callableType == 'table' then
                task = ReactiveTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.REPEATING, period, callable, ...)
            else
                task = ReactiveTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.REPEATING, period, ...)
            end
        elseif api == TaskAPI.EVENT_LISTENER then
            if callableType == 'table' then
                task = EventListenerTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.REPEATING, period, callable, ...)
            else
                task = EventListenerTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.REPEATING, period, ...)
            end
        end

        enqueueToAvailableTaskBucket(self, task)

        if api == TaskAPI.REACTIVE then
            return task.observable
        elseif api == TaskAPI.EVENT_LISTENER then
            return task.eventListener
        end
    end
end)
if Debug then Debug.endFile() end
