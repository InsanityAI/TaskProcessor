if Debug then Debug.beginFile "TaskProcessor.Task" end
OnInit.module("TaskProcessor.Task", function (require)

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
    ---@field taskThread thread
    ---@field opCounts integer|{n: integer, index: integer, [integer]: integer}
    ---@field requestTime number
    ---@field period number?
    ---@field [integer] unknown
    ---@field n integer argumentVectorSize
    ---@field getAPIType fun(): TaskAPI
    ---@field propagateResults fun(self: Task, delay: number, success: boolean, taskDone?: boolean, ...: unknown): coroutineSuccess: boolean, taskDone: boolean|string?
    ---@field finish fun(self: Task, delay: number)
    Task = {}
    Task.__index = Task

    ---@param taskThread thread
    ---@param opCounts integer|{n: integer, index: integer, [integer]: integer}
    ---@param requestTime number
    ---@param taskType TaskType
    ---@param period number?
    ---@param ... unknown
    ---@return Task
    function Task.create(taskThread, opCounts, requestTime, taskType, period, ...)
        local o = table.pack(...)
        o.taskThread = taskThread
        o.opCounts = opCounts
        o.requestTime = requestTime
        o.taskType = taskType
        o.period = period

        if type(o.opCounts) == "table" then
            o.opCounts.n = #opCounts
            o.opCounts.index = 0
        end

        return setmetatable(o, Task)
    end

    local opCount ---@type integer
    ---@return integer
    function Task:getOpCount()
        opCount = self.opCounts[self.opCounts.index]
        if self.opCounts.index < self.opCounts.n then
            self.opCounts.index = self.opCounts.index + 1
        end
        return opCount
    end

    ---@class TaskList: LinkedListHead
    ---@field value Task

    ---@class TaskBucket
    ---@field tasks TaskList
    ---@field opCount integer

    ---@alias CallableTable {__call: fun(delay: integer, ...: unknown)}
end)
if Debug then Debug.endFile() end