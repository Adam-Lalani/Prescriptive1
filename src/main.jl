include("sat_instance.jl")
include("dimacs_parser.jl")
include("model_timer.jl")
include("dpll.jl")

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()

using JSON
using .DimacsParser

function main(args::Vector{String})
    if isempty(args)
        println("Usage: julia main.jl <cnf file>")
        return
    end
    
    input_file = args[1]
    filename = basename(input_file)
    
    timer = Timer()
    start!(timer)
    
    try
        instance = parse_cnf_file(input_file)
        if !isnothing(instance)
            print(instance)
        end
        
        # Use optimized 2-watched literal DPLL solver
        sol = run_dpll(instance)
        
        stop!(timer)
        
        sol_str = "--"
        result = "UNSAT"
        if !isnothing(sol)
            result = "SAT"
            sol_str = ""
            for var in sort(collect(instance.vars))
                sol_str *= string(var) * " "
                sol_str *= sol[var] ? "true " : "false "
            end
        end
        
        printSol = Dict(
            "Instance" => filename,
            "Time" => string(round(get_time(timer), digits=2)),
            "Result" => result,
            "Solution" => sol_str
        )
        
        println(JSON.json(printSol))
        
    catch e
        println("Error: $e")
        rethrow(e)
    end
end

# Run main with command line arguments
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
