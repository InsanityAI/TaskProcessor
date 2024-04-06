if Debug then Debug.beginFile "TaskProcessor/EventListener/Task" end
OnInit.module("TaskProcessor/EventListener/Task", function(require)
    local EL = require.optionally "EventListener" ---@type EventListener
    if not EL then
        return
    end
    require "TaskProcessor.Task"

    ---@class EventListenerTask: Task
    ---@field eventListener EventListener
    EventListenerTask = {}
    EventListenerTask.__index = EventListenerTask
    setmetatable(EventListenerTask, Task)

    ---@param taskThread thread
    ---@param opCounts integer|integer[]
    ---@param requestTime number
    ---@param taskType TaskType
    ---@param period number?
    ---@param ... unknown
    ---@return EventListenerTask
    function EventListenerTask.create(taskThread, opCounts, requestTime, taskType, period, ...)
        local o = setmetatable(Task.create(taskThread, opCounts, requestTime, taskType, period, ...), EventListenerTask) --[[@as EventListenerTask]]
        o.eventListener = EventListener.create()
        return o
    end

    function EventListenerTask.getAPIType()
        return TaskAPI.EVENT_LISTENER
    end

    ---@overload fun(self: EventListenerTask, delay: number, coroutineSuccess: true, taskDone?: boolean, ...: unknown): coroutineSuccess: true, taskDone: boolean?
    ---@overload fun(self: EventListenerTask, delay: number, coroutineSuccess: false, message: string): coroutineSuccess: false, message: string
    function EventListenerTask:propagateResults(delay, coroutineSuccess, taskDone, ...)
        if coroutineSuccess then
            self.eventListener:run(delay, coroutineSuccess, ...)
        else
            self.eventListener:run(delay, coroutineSuccess, taskDone)
        end
        return coroutineSuccess, taskDone
    end

    ---@param delay number
    function EventListenerTask:finish(delay)
        self.eventListener:destroy()
    end
end)
if Debug then Debug.endFile() end
