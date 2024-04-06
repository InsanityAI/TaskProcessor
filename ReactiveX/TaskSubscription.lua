if Debug then Debug.beginFile "TaskProcessor/ReactiveX/TaskSubscription" end
OnInit.module("TaskProcessor/ReactiveX/TaskSubscription", function(require)
    ---@class TaskSubscription: Subscription
    ---@field observer Observer
    ---@field task ReactiveTask
    TaskSubscription = {}
    TaskSubscription.__index = TaskSubscription
    setmetatable(TaskSubscription, Subscription)

    -- Creates a new Subscription.
    ---@param action? fun(subscription: Subscription) action - The action to run when the subscription is unsubscribed. It will only be run once.
    ---@param observer TaskObserver
    ---@param task ReactiveTask
    ---@return TaskSubscription
    function TaskSubscription.create(action, observer, task)
        local o = setmetatable(Subscription.create(action), TaskSubscription) --[[@as TaskSubscription]]
        o.observer = observer
        o.task = task
        return o
    end
end)
if Debug then Debug.endFile() end
