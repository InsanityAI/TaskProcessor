if Debug then Debug.beginFile "TaskProcessor/Strategies/FirstComeFirstServe" end
OnInit.module("TaskProcessor/Strategies/FirstComeFirstServe", function(require)
    ---@class FirstComeFirstServe: SchedulingStrategy
    local FirstComeFirstServe = {}
    FirstComeFirstServe.__index = FirstComeFirstServe
    FirstComeFirstServe.__name = "FirstComeFirstServe"

    -- Singleton
    ---@return FirstComeFirstServe
    function FirstComeFirstServe.create()
        return FirstComeFirstServe
    end

    ---@param processor TaskProcessor
    ---@param task Task
    function FirstComeFirstServe:scheduleTask(processor, task)
        processor.tasks:getPrev():insert(task, true)
    end

    return FirstComeFirstServe
end)
if Debug then Debug.endFile() end
