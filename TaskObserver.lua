if Debug then Debug.beginFile "TaskObserver" end
OnInit.module("TaskObserver", function(require)
    require "ReactiveX"

    ---@class TaskObserver : Observer
    ---@field _onNext fun(value: unknown, delay: number)?
    ---@field _onError fun(message: string, delay: number)?
    ---@field _onCompleted fun(delay: number)?
    TaskObserver = {}
    TaskObserver.__index = TaskObserver
    setmetatable(TaskObserver, Observer)

    ---@generic T
    ---@param onNext fun(value: T, delay: number)
    ---@param onError fun(message: string, delay: number)?
    ---@param onCompleted fun()?
    ---@return TaskObserver
    function TaskObserver.create(onNext, onError, onCompleted)
        return setmetatable(Observer.create(onNext, onError, onCompleted), TaskObserver) --[[@as TaskObserver]]
    end

    --- Pushes a value to the Observer.
    ---@generic T
    ---@param value T
    ---@param delay number
    function TaskObserver:onNext(value, delay)
        if not self.stopped then
            self._onNext(value, delay)
        end
    end

    --- Notify the Observer that an error has occurred.
    ---@param message string A string describing what went wrong.
    ---@param delay number
    function TaskObserver:onError(message, delay)
        if not self.stopped then
            self.stopped = true
            self._onError(message, delay)
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
