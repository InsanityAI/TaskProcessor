if Debug then Debug.beginFile "TaskObservable" end
OnInit.module("TaskObservable", function(require)
    require "ReactiveX"

    ---@class TaskObservable : Observable
    ---@field task ReactiveTask
    ---@field _subscribe fun(observer: TaskObserver, task: ReactiveTask): TaskSubscription
    -- Observables push values to Observers.
    TaskObservable = {}
    TaskObservable.__index = TaskObservable
    setmetatable({}, Observable)

    -- Creates a new TaskObservable.
    ---@param task ReactiveTask
    ---@param subscribe fun(observer: TaskObserver, task: ReactiveTask): TaskSubscription subscription function that produces values.
    ---@return TaskObservable
    function TaskObservable.create(task, subscribe)
        local o = setmetatable(Observable.create(subscribe), TaskObservable) --[[@as TaskObservable]]
        o.task = task
        return o
    end

    --- Shorthand for creating an TaskObserver and passing it to this TaskObservable's subscription function.
    ---@param onNext table|fun(delay: number, ...: unknown) called when the TaskObservable produces a value.
    ---@param onError fun(delay: number, message: string)? called when the TaskObservable terminates due to an error.
    ---@param onCompleted fun(delay: number)? called when the TaskObservable completes normally.
    function TaskObservable:subscribe(onNext, onError, onCompleted)
        if type(onNext) == 'table' then
            return self._subscribe(onNext, self.task)
        else
            return self._subscribe(TaskObserver.create(onNext, onError, onCompleted), self.task)
        end
    end
end)
if Debug then Debug.endFile() end
