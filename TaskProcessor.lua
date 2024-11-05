if Debug then Debug.beginFile "TaskProcessor" end
OnInit.module("TaskProcessor", function(require)
    require "TimerQueue"
    require "LinkedList"
    require "TaskProcessor/EventListener/EventListenerTask"
    require "TaskProcessor/ReactiveX/ReactiveTask"
    require "TaskProcessor/ReactiveX/TaskObservable"
    require "TaskProcessor/ReactiveX/TaskObserver"
    require "TaskProcessor/ReactiveX/TaskSubject"
    require "TaskProcessor/ReactiveX/TaskSubscription"
    local FCFS = require "TaskProcessor/Strategies/FirstComeFirstServe"
    require "TaskProcessor/Strategies/LongestJobFirst"
    require "TaskProcessor/Strategies/ShortestJobFirst"
    require "TaskProcessor/Task"

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
    local processors = {} --- @type TaskProcessor[]

    --- Abstract
    ---@class SchedulingStrategy
    ---@field scheduleTask fun(self: SchedulingStrategy, processor: TaskProcessor, task: Task)

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

    ---@param coroutineSuccess boolean|string
    ---@param taskResult string|boolean?
    local function isTaskToBeRepeated(coroutineSuccess, taskResult)
        if coroutineSuccess == false then
            print("|cFFff0000TaskProcessing error: |r", taskResult)
            return false
        else
            return taskResult == true
        end
    end

    ---@param processor TaskProcessor
    ---@param task Task
    ---@param requestTime number?
    local function scheduleTask(processor, task, requestTime)
        task.requestTime = requestTime or processor.clock:getElapsed()
        processor.schedulingStrategy:scheduleTask(processor, task)
        if processor.taskExecutor.paused then
            processor.taskExecutor:resume()
        end
    end

    ---@param processor TaskProcessor
    local function process(processor)
        local task ---@type Task
        local delay ---@type number
        local success, result ---@type boolean, boolean|string?
        local currentTime = processor.clock:getElapsed()
        processor.currentOperations = 0
        if processor.tasks.n > 0 then
            for taskNode in processor.tasks:loop() do
                task = taskNode --[[@as LinkedListNode]].value ---@type Task

                processor.currentOperations = processor.currentOperations + task:peekOpCount()
                if processor.currentOperations > processor.opLimit then
                    break
                end

                if coroutine.status(task.taskThread) == 'dead' then
                    if task.callable then
                        task.taskThread = coroutine.create(task.callable) --regenerate task thread
                    else
                        print("|cffff0000 TaskProcessor Error:|r Callable thread cannot be re-started by task processor, Make sure the function within the thread is repeatable before enqueing it as such!")
                    end
                end
                delay = (currentTime - task.requestTime) * GAME_TICK_INVERSE
                success, result = task:propagateResults(delay,
                    coroutine.resume(task.taskThread, delay, table.unpack(task, 1, task.n)))

                taskNode:remove()
                if task.type == TaskType.REPEATING and isTaskToBeRepeated(success, result) then
                    task:nextOpCount()
                    if task.period <= 0 then
                        scheduleTask(processor, task, currentTime)
                    else
                        processor.taskExecutor:callDelayed(task.period, scheduleTask, processor, task)
                    end
                else
                    task:finish(delay)
                end
            end
        end

        if processor.tasks.n == 0 and processor.taskExecutor.n == 0 then
            processor.taskExecutor:pause()
        end
    end

    ---@class TaskProcessor
    ---@field package ratio integer
    ---@field package opLimit integer
    ---@field package taskExecutor TimerQueue
    ---@field package clock Stopwatch
    ---@field package currentOperations integer
    ---@field package schedulingStrategy SchedulingStrategy
    ---@field tasks TaskList
    TaskProcessor = {}
    TaskProcessor.__index = TaskProcessor
    TaskProcessor.__name = "TaskProcessor"


    ---@param ratio integer integer higher or equal to 1, will re-adjust this new processor and other existing processors op limit in comparison to these numbers.
    ---@param schedulingStrategy SchedulingStrategy? by default it's FCFS
    ---@return TaskProcessor
    function TaskProcessor.create(ratio, schedulingStrategy)
        assert((type(ratio) == "number" and math.floor(ratio) == ratio), "Paramater 'ratio' must be an integer")
        assert(ratio >= 1, "Parameter 'ratio' must be higher or equal to 1")
        local instance = setmetatable({
            ratio = ratio,
            schedulingStrategy = schedulingStrategy or FCFS,
            -- opLimit is set by refreshProcessorsOpLimits
            taskExecutor = TimerQueue.create(),
            clock = Stopwatch.create(true),
            tasks = LinkedList.create()
        }, TaskProcessor)
        table.insert(processors, instance)
        refreshProcessorsOpLimits()
        instance.taskExecutor:pause();
        instance.taskExecutor:callPeriodically(GAME_TICK, nil, process, instance)
        return instance
    end

    ---@alias CallableFunction fun(delay: integer, ...: unknown): repeat: boolean, ...
    ---@alias CallableTable {__call: CallableFunction}
    ---@alias TaskCallable thread|CallableFunction|CallableTable

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

    ---@param delay number
    ---@param table CallableTable
    ---@return ...
    local function callCallableTable(delay, table, ...)
        return table(delay, ...)
    end

    ---@overload fun(self: TaskProcessor, taskCallable: TaskCallable, opCounts: number|number[], api: TaskAPI.REACTIVE,       ...: unknown): TaskObservable
    ---@overload fun(self: TaskProcessor, taskCallable: TaskCallable, opCounts: number|number[], api: TaskAPI.EVENT_LISTENER, ...: unknown): TaskListener
    ---@param api TaskAPI
    function TaskProcessor:enqueue(callable, opCounts, api, ...)
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
                task = ReactiveTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.ONESHOT, nil, callable,
                    ...)
            else
                task = ReactiveTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.ONESHOT, nil, ...)
            end
        elseif api == TaskAPI.EVENT_LISTENER then
            if callableType == 'table' then
                task = EventListenerTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.ONESHOT, nil,
                    callable, ...)
            else
                task = EventListenerTask.create(thread, opCounts, self.clock:getElapsed(), TaskType.ONESHOT, nil, ...)
            end
        end

        scheduleTask(self, task)

        if api == TaskAPI.REACTIVE then
            return task.observable
        elseif api == TaskAPI.EVENT_LISTENER then
            return task.eventListener
        end
    end

    ---@overload fun(self: TaskProcessor, taskCallable: TaskCallable, period: number, opCounts: number|number[], api: TaskAPI.REACTIVE, ...: unknown): TaskObservable
    ---@overload fun(self: TaskProcessor, taskCallable: TaskCallable, period: number, opCounts: number|number[], api: TaskAPI.EVENT_LISTENER, ...: unknown): TaskListener
    ---@param api TaskAPI
    function TaskProcessor:enqueuePeriodic(callable, period, opCounts, api, ...)
        validateCommonArgs(opCounts)
        assert(type(period) == "number", "Argument period must be a positive non-zero number!")
        assert(period >= 0, "Argument period must not be negative!")
        local callableType = getCallableType(callable)

        local task ---@type Task
        if api == TaskAPI.REACTIVE then
            if callableType == 'table' then
                task = ReactiveTask.create(callCallableTable, opCounts, TaskType.REPEATING, period, callable, ...)
            else
                task = ReactiveTask.create(callable --[[@as thread|function]], opCounts, TaskType.REPEATING, period, ...)
            end
        elseif api == TaskAPI.EVENT_LISTENER then
            if callableType == 'table' then
                task = EventListenerTask.create(callCallableTable, opCounts, TaskType.REPEATING, period, callable, ...)
            else
                task = EventListenerTask.create(callable --[[@as thread|function]], opCounts, TaskType.REPEATING, period, ...)
            end
        end

        scheduleTask(self, task)

        if api == TaskAPI.REACTIVE then
            return task.observable
        elseif api == TaskAPI.EVENT_LISTENER then
            return task.eventListener
        end
    end
end)
if Debug then Debug.endFile() end
