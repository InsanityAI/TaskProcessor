if Debug then Debug.beginFile "TaskProcessor/Task" end
OnInit.module("TaskProcessor/Task", function(require)
    ---@enum TaskAPI
    TaskAPI = {
        REGULAR = 1,
        REACTIVE = 2,
        EVENT_LISTENER = 3
    }

    ---@enum TaskType
    TaskType = {
        ONESHOT = 1,
        REPEATING = 2,
        COMPOSITE = 3
    }

    ---Abstract
    ---@class Task
    ---@field type TaskType
    ---@field callable function?
    ---@field taskThread thread
    ---@field opCounts integer|{n: integer, index: integer, [integer]: integer}
    ---@field requestTime number
    ---@field period number?
    ---@field [integer] unknown
    ---@field n integer argumentVectorSize
    ---@field getAPIType fun(): TaskAPI
    ---@field propagateResults fun(self: Task, delay: number, success: boolean, taskDone?: boolean, ...: unknown): coroutineSuccess: boolean, taskDone: boolean|string?
    ---@field finish fun(self: Task, delay: number)
    ---@field peekOpCount fun(self: Task): integer Fetches task's current opCount
    ---@field nextOpCount fun(self: Task): integer Increment opCount stage (if there's multiple), returns the next opCount
    Task = {}
    Task.__index = Task
    Task.__name = "Task"

    ---@param task Task
    ---@return integer
    local function getOPCount(task)
        return task.opCounts --[[@as integer]]
    end

    ---@param task Task
    ---@return integer
    local function getCurrentOpCount(task)
        return task.opCounts[task.opCounts.index]
    end

    local opCount ---@type integer
    ---@param task Task
    ---@return integer
    local function getNextOpCount(task)
        opCount = task.opCounts[task.opCounts.index]
        if task.opCounts.index < task.opCounts.n then
            task.opCounts.index = task.opCounts.index + 1
        end
        return opCount
    end

    ---@param callable thread|function
    ---@param opCounts integer|{n: integer, index: integer, [integer]: integer}
    ---@param taskType TaskType
    ---@param period number?
    ---@param ... unknown
    ---@return Task
    function Task.create(callable, opCounts, taskType, period, ...)
        local o = table.pack(...)

        o.opCounts = opCounts
        o.type = taskType
        o.period = period

        if type(callable) == 'thread' then
            o.taskThread = callable
        else
            o.callable = callable
            o.taskThread = coroutine.create(callable)
        end

        if type(o.opCounts) == "table" then
            o.opCounts.n = #opCounts
            o.opCounts.index = 1
            o.peekOpCount = getCurrentOpCount
            o.nextOpCount = getNextOpCount
        else
            o.peekOpCount = getOPCount
            o.nextOpCount = getOPCount
        end

        return setmetatable(o, Task)
    end

    ---@class TaskList: LinkedListHead
    ---@field value Task
end)
if Debug then Debug.endFile() end
