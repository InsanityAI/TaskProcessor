if Debug then Debug.beginFile "TaskProcessor/Strategies/LongestJobFirst" end
OnInit.module("TaskProcessor/Strategies/LongestJobFirst", function(require)
    ---@class LongestJobFirst: SchedulingStrategy
    local LongestJobFirst = {}
    LongestJobFirst.__index = LongestJobFirst

    -- Singleton
    ---@return LongestJobFirst
    function LongestJobFirst.create()
        return LongestJobFirst
    end

    ---@param processor Processor
    ---@param task Task
    function LongestJobFirst:scheduleTask(processor, task)
        local taskOpCount = task:peekOpCount()
        local inserted = false
        for taskNode in processor.tasks:loop() do
            if taskNode.value --[[@as Task]]:peekOpCount() < taskOpCount then
                taskNode:insert(task)
                inserted = true
                break
            end
        end
        if not inserted then
            processor.tasks:getPrev():insert(task, true)
        end
    end

    return LongestJobFirst
end)
if Debug then Debug.endFile() end
