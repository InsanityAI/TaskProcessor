if Debug then Debug.beginFile "TaskProcessor/ReactiveX/TaskObserver" end
OnInit.module("TaskProcessor/ReactiveX/TaskObserver", function(require)
    require "ReactiveX"

    ---@class TaskObserver : Observer
    ---@field _onNext fun(delay: number, ...: unknown)?
    ---@field _onError fun(delay: number, message: string)?
    ---@field _onCompleted fun(delay: number)?
    TaskObserver = {}
    TaskObserver.__index = TaskObserver
    TaskObserver.__name = "TaskObserver"
    setmetatable(TaskObserver, Observer)

    ---@param onNext fun(delay: number, ...: unknown)
    ---@param onError fun(message: string, delay: number)?
    ---@param onCompleted fun()?
    ---@return TaskObserver
    function TaskObserver.create(onNext, onError, onCompleted)
        return setmetatable(Observer.create(onNext, onError, onCompleted), TaskObserver) --[[@as TaskObserver]]
    end

    --- Pushes a value to the Observer.
    ---@param delay number
    ---@param ... unknown
    function TaskObserver:onNext(delay, ...)
        if not self.stopped then
            self._onNext(delay, ...)
        end
    end

    --- Notify the Observer that an error has occurred.
    ---@param delay number
    ---@param message string A string describing what went wrong.
    function TaskObserver:onError(delay, message)
        if not self.stopped then
            self.stopped = true
            self._onError(delay, message)
        end
    end

    --- Notify the Observer that the sequence has completed and will produce no more values.
    ---@param delay number
    function TaskObserver:onCompleted(delay)
        if not self.stopped then
            self.stopped = true
            self._onCompleted(delay)
        end
    end
end)
if Debug then Debug.endFile() end
