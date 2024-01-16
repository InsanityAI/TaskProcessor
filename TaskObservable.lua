if Debug then Debug.beginFile "TaskObservable" end
OnInit.module("TaskObservable", function(require)
    require "ReactiveX"

    ---@class TaskObservable : Observable
    ---@field _subscribe fun(observer: TaskObserver): any?
    -- Observables push values to Observers.
    TaskObservable = {}
    TaskObservable.__index = TaskObservable
    setmetatable({}, Observable)

    --- Creates a new TaskObservable.
    ---@param subscribe fun(observer: TaskObserver): any? subscription function that produces values.
    ---@return TaskObservable
    function TaskObservable.create(subscribe)
        return setmetatable(Observable.create(subscribe), TaskObservable) --[[@as TaskObservable]]
    end

    --- Shorthand for creating an TaskObserver and passing it to this TaskObservable's subscription function.
    ---@generic T
    ---@param onNext table|fun(value: T, delay: number) called when the TaskObservable produces a value.
    ---@param onError fun(message: string, delay: number)? called when the TaskObservable terminates due to an error.
    ---@param onCompleted fun(delay: number)? called when the TaskObservable completes normally.
    function TaskObservable:subscribe(onNext, onError, onCompleted)
        if type(onNext) == 'table' then
            return self._subscribe(onNext)
        else
            return self._subscribe(TaskObserver.create(onNext, onError, onCompleted))
        end
    end
end)
if Debug then Debug.endFile() end
