const _NANO = 1000000000

mutable struct Timer
    start_time::Float64
    end_time::Float64
    running::Bool
    
    function Timer()
        new(0.0, 0.0, false)
    end
end

function start(timer::Timer)
    timer.start_time = Base.time_ns()
    timer.running = true
end

function stop(timer::Timer)
    if timer.running
        timer.end_time = Base.time_ns()
        timer.running = false
    end
end

function getElapsed(timer::Timer)
    if timer.running
        return round((Base.time_ns() - timer.start_time) / _NANO, digits=4)
    else
        return round((timer.end_time - timer.start_time) / _NANO, digits=4)
    end
end

function getTime(timer::Timer)
    return getElapsed(timer)
end
