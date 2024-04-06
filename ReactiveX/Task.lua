if Debug then Debug.beginFile "TaskProcessor.ReactiveX.Task" end
OnInit.module("TaskProcessor.ReactiveX.Task", function(require)
    require "TaskProcessor.Task"
    require "SyncedTable"

    ---@class ReactiveTask: Task
    ---@field observers table<TaskObserver, boolean>
    ---@field observable TaskObservable
    ReactiveTask = {}
    ReactiveTask.__index = ReactiveTask
    setmetatable(ReactiveTask, Task)

    ---@param subscription TaskSubscription
    local function unsubscribeAction(subscription)
        subscription.task.observers[subscription.observer] = nil
    end

    ---@param observer TaskObserver
    ---@param task ReactiveTask
    ---@return TaskSubscription
    local function subscribeObserver(observer, task)
        local subscription = TaskSubscription.create(unsubscribeAction, observer, task)
        task.observers[observer] = true
        return subscription
    end

    ---@param taskThread thread
    ---@param opCounts integer|integer[]
    ---@param requestTime number
    ---@param taskType TaskType
    ---@param period number?
    ---@param ... unknown
    ---@return ReactiveTask
    function ReactiveTask.create(taskThread, opCounts, requestTime, taskType, period, ...)
        local o = setmetatable(Task.create(taskThread, opCounts, requestTime, taskType, period, ...), ReactiveTask) --[[@as ReactiveTask]]
        o.observable = TaskObservable.create(o, subscribeObserver)
        o.observers = SyncedTable.create()
        return o
    end

    function ReactiveTask.getAPIType()
        return TaskAPI.REACTIVE
    end

    ---@overload fun(self: ReactiveTask, delay: number, coroutineSuccess: true, taskDone?: boolean, ...: unknown): coroutineSuccess: true, taskDone: boolean?
    ---@overload fun(self: ReactiveTask, delay: number, coroutineSuccess: false, message: string): coroutineSuccess: false, message: string
    function ReactiveTask:propagateResults(delay, coroutineSuccess, taskDone, ...)
        if coroutineSuccess then
            for observer, _ in pairs(self.observers) do
                observer:onNext(delay, ...)
            end
        else
            for observer, _ in pairs(self.observers) do
                observer:onError(delay, taskDone --[[@as string]])
            end
        end
        return coroutineSuccess, taskDone
    end

    ---@param delay number
    function ReactiveTask:finish(delay)
        for observer, _ in pairs(self.observers) do
            observer:onCompleted(delay)
        end
    end

end)
if Debug then Debug.endFile() end
