mutable struct Timer
    start_time::Float64
    end_time::Float64
    running::Bool
    
    function Timer()
        new(0.0, 0.0, false)
    end
end

function start!(timer::Timer)
    timer.start_time = time_ns()
    timer.running = true
end

function stop!(timer::Timer)
    if timer.running
        timer.end_time = time_ns()
        timer.running = false
    end
end

function get_elapsed(timer::Timer)
    if timer.running
        return round((time_ns() - timer.start_time) / 1e9, digits=4)
    else
        return round((timer.end_time - timer.start_time) / 1e9, digits=4)
    end
end

function get_time(timer::Timer)
    return get_elapsed(timer)
end