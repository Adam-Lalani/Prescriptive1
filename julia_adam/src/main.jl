using ArgParse
using JSON

include("sat_instance.jl")
include("model_timer.jl")
include("dimacs_parser.jl")
include("dpll_solver.jl")
include("cdcl_vsids_solver.jl")

using .DimacsParser

function main(input_file::String)
    if isempty(input_file)
        println("Usage: julia src/main.jl <cnf file>")
        return
    end
    
    filename = basename(input_file)
    
    timer = Timer()
    start(timer)
    
    instance = nothing
    try
        instance = DimacsParser.parse_cnf_file(input_file)
        if instance !== nothing
            print(instance)
        end
    catch e
        println("Error: $e")
    end
    
    # Solve using CDCL solver with 2-watched literals and VSIDS
    solution = nothing
    if instance !== nothing
        solution = cdcl_solve(instance)
    end
    
    stop(timer)
    
    result = "--"
    if solution !== nothing && instance !== nothing
        result = ""
        for var in instance.vars
            result *= string(var) * " "
            result *= solution[var] ? "true " : "false "
        end
    end
    
    printSol = Dict(
        "Instance" => filename,
        "Time" => string(round(getTime(timer), digits=2)),
        "Result" => result
    )
    
    println(JSON.json(printSol))
end

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "input_file"
            help = "Input CNF file"
            required = true
    end
    return parse_args(s)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    parsed_args = parse_commandline()
    main(parsed_args["input_file"])
end
