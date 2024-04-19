if Debug then Debug.beginFile "TaskProcessor/ReactiveX/TaskSubject" end
OnInit.module("TaskProcessor/ReactiveX/TaskSubject", function(require)
    require "ReactiveX"
    require "TaskProcessor/ReactiveX/TaskObservable"
    require "TaskProcessor/ReactiveX/TaskObserver"

    ---@class TaskSubject : BehaviorSubject
    ---@field observers TaskObserver[]
    TaskSubject = {}
    TaskSubject.__index = TaskSubject
    TaskSubject.__name = "TaskSubject"
    setmetatable(TaskSubject, BehaviorSubject)

    ---@return TaskSubject
    function TaskSubject.create()
        local TaskSubject = setmetatable({
            observers = {}
        }, TaskSubject)
        return TaskSubject --[[@as TaskSubject]]
    end

    --- Creates a new Observer and attaches it to the TaskSubject.
    ---@param onNext fun(delay: number, ...: unknown) - A function called when the TaskSubject produces a value or an existing Observer to attach to the TaskSubject.
    ---@param onError fun(delay: number, message: string) - Called when the TaskSubject terminates due to an error.
    ---@param onCompleted fun(delay: number) - Called when the TaskSubject completes normally.
    ---@return Subscription?
    function TaskSubject:subscribe(onNext, onError, onCompleted)
        local observer = TaskObserver.create(onNext, onError, onCompleted) --[[@as TaskObserver]]
        if self.value then
            observer:onNext(self.delay, table.unpack(self.value))
            observer:onCompleted(self.delay)
            return
        elseif self.errorMessage then
            observer:onError(self.delay, self.errorMessage)
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
    ---@param delay number
    ---@param ... unknown
    function TaskSubject:onNext(delay, ...)
        if not self.stopped then
            self.delay = delay
            self.value = table.pack(...) -- terrible practice...

            for i = 1, #self.observers do
                self.observers[i]:onNext(delay, ...)
            end
        end
    end

    --- Signal to all Observers that an error has occurred.
    ---@param delay number
    ---@param message string - A string describing what went wrong.
    function TaskSubject:onError(delay, message)
        if not self.stopped then
            self.errorMessage = message

            for i = 1, #self.observers do
                self.observers[i]:onError(delay, self.errorMessage)
            end

            self.stopped = true
        end
    end

    ---@param self TaskSubject
    ---@param delay number
    ---@param ... unknown
    local function completeAll(self, delay, ...)
        for i = 1, #self.observers do
            if self.value then
                self.observers[i]:onNext(self.delay, ...)
            end

            self.observers[i]:onCompleted(delay)
        end
    end

    --- Signal to all Observers that the TaskSubject will not produce any more values.
    ---@param delay number
    function TaskSubject:onCompleted(delay)
        if not self.stopped then
            completeAll(self, delay, table.unpack(self.value))
            self.stopped = true
        end
    end
end)
if Debug then Debug.endFile() end
