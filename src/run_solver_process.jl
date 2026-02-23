#!/usr/bin/env julia

# run_solver_process.jl
# Runs a single SAT solver as a separate process
# Usage: julia run_solver_process.jl <solver_name> <input_file> <output_file>

include("sat_instance.jl")
include("dimacs_parser.jl")
include("model_timer.jl")

include("solvers/dpll.jl")
include("solvers/dpll_bad.jl")
include("solvers/cdcl_basic_solver.jl")
include("solvers/cdcl_vsids_solver.jl")
include("solvers/cdcl_vsids_luby_solver.jl")
include("solvers/cdcl_vsids_luby_sd.jl")
include("solvers/cdcl_vsids_luby_nd.jl")

using JSON
using .DimacsParser

const SOLVERS = Dict(
    "dpll"            => inst -> DPLLSolver.run_dpll(inst),
    "dpll_bad"        => inst -> DPLLBad.run_dpll(inst),
    "cdcl_basic"      => inst -> CDCLBasic.cdcl_solve(inst),
    "cdcl_vsids"      => inst -> CDCLVSIDS.cdcl_solve(inst),
    "cdcl_vsids_luby" => inst -> CDCLVSIDSLuby.cdcl_solve(inst),
    "cdcl_vsids_luby_sd" => inst -> CDCLVSIDSLubySd.cdcl_solve(inst),
    "cdcl_vsids_luby_nd" => inst -> CDCLVSIDSLubyNd.cdcl_solve(inst),
)

function main(args::Vector{String})
    if length(args) < 3
        println(stderr, "Usage: julia run_solver_process.jl <solver_name> <input_file> <output_file>")
        exit(1)
    end
    
    solver_name = args[1]
    input_file = args[2]
    output_file = args[3]
    
    if !haskey(SOLVERS, solver_name)
        println(stderr, "Unknown solver: $solver_name")
        println(stderr, "Available: $(join(sort(collect(keys(SOLVERS))), ", "))")
        exit(1)
    end
    
    try
        # Parse instance
        instance = parse_cnf_file(input_file)
        if instance === nothing
            println(stderr, "Failed to parse instance")
            exit(1)
        end
        
        # Run solver
        timer = Timer()
        start!(timer)
        
        solve_fn = SOLVERS[solver_name]
        sol = solve_fn(instance)
        
        stop!(timer)
        elapsed = get_time(timer)
        
        # Format solution
        sol_str = "--"
        result_status = "UNSAT"
        if !isnothing(sol)
            result_status = "SAT"
            sol_str = ""
            for var in 1:instance.numVars
                sol_str *= string(var) * " "
                sol_str *= sol[var] ? "true " : "false "
            end
        end
        
        # Create result
        result = Dict(
            "Instance" => basename(input_file),
            "Solver" => solver_name,
            "Time" => string(round(elapsed, digits=2)),
            "Result" => result_status,
            "Solution" => sol_str,
            "ProcessID" => getpid()
        )
        
        # Write to output file atomically
        temp_file = output_file * ".tmp"
        open(temp_file, "w") do f
            write(f, JSON.json(result))
        end
        mv(temp_file, output_file, force=true)
        
    catch e
        # Write error to output file
        error_result = Dict(
            "Instance" => basename(input_file),
            "Solver" => solver_name,
            "Time" => "--",
            "Result" => "ERROR",
            "Solution" => "--",
            "Error" => string(e),
            "ProcessID" => getpid()
        )
        
        try
            open(output_file, "w") do f
                write(f, JSON.json(error_result))
            end
        catch write_err
            println(stderr, "Failed to write error: $write_err")
        end
        
        rethrow(e)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end