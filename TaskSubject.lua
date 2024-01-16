if Debug then Debug.beginFile "TaskSubject" end
OnInit.module("TaskSubject", function(require)
    require "ReactiveX"
    require "TaskObservable"
    require "TaskObserver"

    ---@class TaskSubject : BehaviorSubject
    ---@field observers TaskObserver[]
    TaskSubject = {}
    TaskSubject.__index = TaskSubject
    setmetatable(TaskSubject, BehaviorSubject)

    ---@return TaskSubject
    function TaskSubject.create()
        local TaskSubject = setmetatable({
            observers = {}
        }, TaskSubject)
        return TaskSubject --[[@as TaskSubject]]
    end

    --- Creates a new Observer and attaches it to the TaskSubject.
    ---@generic T
    ---@param onNext fun(value: T, delay: number) - A function called when the TaskSubject produces a value or an existing Observer to attach to the TaskSubject.
    ---@param onError fun(message: string, delay: number) - Called when the TaskSubject terminates due to an error.
    ---@param onCompleted fun(delay: number) - Called when the TaskSubject completes normally.
    ---@return Subscription?
    function TaskSubject:subscribe(onNext, onError, onCompleted)
        local observer = TaskObserver.create(onNext, onError, onCompleted) --[[@as TaskObserver]]
        if self.value then
            observer:onNext(self.value, self.delay)
            observer:onCompleted(self.delay)
            return
        elseif self.errorMessage then
            observer:onError(self.errorMessage, self.delay)
            return
        end

        table.insert(self.observers, observer)

        return Subscription.create(function()
            for i = 1, #self.observers do
                if self.observers[i] == observer then
                    table.remove(self.observers, i)
                    return
                end
            end
        end)
    end

    --- Pushes a value to the TaskSubject.
    ---@generic T
    ---@param value T
    ---@param delay number
    function TaskSubject:onNext(value, delay)
        if not self.stopped then
            self.value = value
            self.delay = delay

            for i = 1, #self.observers do
                self.observers[i]:onNext(value, delay)
            end
        end
    end

    --- Signal to all Observers that an error has occurred.
    ---@param message string - A string describing what went wrong.
    ---@param delay number
    function TaskSubject:onError(message, delay)
        if not self.stopped then
            self.errorMessage = message

            for i = 1, #self.observers do
                self.observers[i]:onError(self.errorMessage, delay)
            end

            self.stopped = true
        end
    end

    --- Signal to all Observers that the TaskSubject will not produce any more values.
    ---@param delay number
    function TaskSubject:onCompleted(delay)
        if not self.stopped then
            for i = 1, #self.observers do
                if self.value then
                    self.observers[i]:onNext(self.value, self.delay)
                end

                self.observers[i]:onCompleted(delay)
            end

            self.stopped = true
        end
    end
end)
if Debug then Debug.endFile() end
