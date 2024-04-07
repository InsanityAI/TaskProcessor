if Debug then Debug.beginFile "TaskProcessor/Strategies/ShortestJobFirst" end
OnInit.module("TaskProcessor/Strategies/ShortestJobFirst", function(require)
    ---@class ShortestJobFirst: SchedulingStrategy
    local ShortestJobFirst = {}
    ShortestJobFirst.__index = ShortestJobFirst

    -- Singleton
    ---@return ShortestJobFirst
    function ShortestJobFirst.create()
        return ShortestJobFirst
    end

    ---@param processor Processor
    ---@param task Task
    function ShortestJobFirst:scheduleTask(processor, task)
        local taskOpCount = task:peekOpCount()
        local inserted = false
        for taskNode in processor.tasks:loop() do
            if taskNode.value --[[@as Task]]:peekOpCount() > taskOpCount then
                taskNode:insert(task)
                inserted = true
                break
            end
        end
        if not inserted then
            processor.tasks:getPrev():insert(task, true)
        end
    end

    return ShortestJobFirst
end)
if Debug then Debug.endFile() end
