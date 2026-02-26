include("sat_instance.jl")
include("dimacs_parser.jl")
include("model_timer.jl")

using Pkg
Pkg.add([
    Pkg.PackageSpec(name="JSON", version="0.21.4"),
    Pkg.PackageSpec(name="ArgParse", version="1.1.4")
])
Pkg.instantiate()

using JSON
using .DimacsParser

const SOLVERS = [
    "dpll",
    "dpll_bad",
    "cdcl_basic",
    "cdcl_vsids",
    "cdcl_vsids_luby",
    "cdcl_vsids_luby_sd",
    "cdcl_vsids_luby_nd"
]

function parse_args(args::Vector{String})
    solver_names = String[]
    input_file = nothing
    timeout = 300  # Default 5 minutes

    i = 1
    while i <= length(args)
        if args[i] == "--solver"
            if i + 1 > length(args)
                error("--solver requires a value. Available: $(join(sort(SOLVERS), ", "))")
            end
            push!(solver_names, args[i + 1])
            i += 2
        elseif args[i] == "--timeout"
            if i + 1 > length(args)
                error("--timeout requires a value in seconds")
            end
            timeout = parse(Int, args[i + 1])
            i += 2
        else
            input_file = args[i]
            i += 1
        end
    end

    if isempty(solver_names)
        push!(solver_names, "cdcl_vsids")
        push!(solver_names, "cdcl_vsids_luby")
        push!(solver_names, "cdcl_vsids_luby_sd")
    end

    return solver_names, input_file, timeout
end

function race_solvers_multiprocess(input_file::String, solver_names::Vector{String}, 
                                   timeout::Int=300)
    n_solvers = length(solver_names)
    
    # Create temp directory for results
    temp_dir = mktempdir()
    
    try
        result_files = String[]
        processes = []
        
        println("Launching $(n_solvers) solver processes (timeout: $(timeout)s)...")
        
        # Launch each solver as a separate process
        for (idx, solver_name) in enumerate(solver_names)
            result_file = joinpath(temp_dir, "result_$idx.json")
            push!(result_files, result_file)
            
            # Build command to run solver process
            cmd = `julia --project=. src/run_solver_process.jl $solver_name $input_file $result_file`
            
            # Launch process in background
            proc = run(pipeline(cmd, stdout=devnull, stderr=devnull), wait=false)
            
            println("  [$solver_name] Started as PID $(getpid(proc))")
            push!(processes, (proc, solver_name, result_file, idx))
        end
        
        # Poll until one finishes or timeout
        start_time = time()
        check_interval = 0.1  # Check every 100ms
        
        while true
            elapsed = time() - start_time
            
            # Check timeout
            if elapsed >= timeout
                println("\nTimeout reached ($(timeout)s) - killing all processes...")
                for (proc, solver_name, _, _) in processes
                    if process_running(proc)
                        kill(proc, Base.SIGTERM)
                        println("  [$solver_name] Killed")
                    end
                end
                return (nothing, timeout, "timeout")
            end
            
            # Check each process
            for (proc, solver_name, result_file, idx) in processes
                if !process_running(proc)
                    # Process finished - check if result file exists
                    if isfile(result_file)
                        try
                            # Read result
                            result = JSON.parsefile(result_file)
                            
                            # Kill other processes immediately
                            println("\n[$solver_name] Finished first!")
                            for (other_proc, other_name, _, other_idx) in processes
                                if other_idx != idx && process_running(other_proc)
                                    kill(other_proc, Base.SIGTERM)
                                    println("  [$other_name] Killed")
                                end
                            end
                            
                            # Extract solution
                            sol_dict = nothing
                            if result["Result"] == "SAT"
                                # Parse solution string back to Dict
                                sol_dict = Dict{Int, Bool}()
                                tokens = split(strip(result["Solution"]))
                                for i in 1:2:length(tokens)-1
                                    var = parse(Int, tokens[i])
                                    val = tokens[i+1] == "true"
                                    sol_dict[var] = val
                                end
                            end
                            
                            return (sol_dict, parse(Float64, result["Time"]), solver_name)
                            
                        catch e
                            @warn "Failed to parse result from $solver_name: $e"
                        end
                    end
                end
            end
            
            sleep(check_interval)
        end
        
    finally
        # Cleanup temp directory
        try
            rm(temp_dir, recursive=true, force=true)
        catch e
            @warn "Failed to cleanup temp directory: $e"
        end
    end
end

# function run_single_solver_process(input_file::String, solver_name::String, timeout::Int=300)
#     temp_dir = mktempdir()
    
#     try
#         result_file = joinpath(temp_dir, "result.json")
        
#         # Build command
#         cmd = `julia --project=. src/run_solver_process.jl $solver_name $input_file $result_file`
        
#         println("Running $solver_name (timeout: $(timeout)s)...")
        
#         # Run with timeout
#         proc = run(pipeline(cmd, stdout=devnull, stderr=devnull), wait=false)
        
#         start_time = time()
#         while process_running(proc)
#             if time() - start_time >= timeout
#                 kill(proc, Base.SIGTERM)
#                 println("Timeout reached")
#                 return (nothing, timeout, solver_name)
#             end
#             sleep(0.1)
#         end
        
#         # Read result
#         if isfile(result_file)
#             result = JSON.parsefile(result_file)
            
#             # Parse solution
#             sol_dict = nothing
#             if result["Result"] == "SAT"
#                 sol_dict = Dict{Int, Bool}()
#                 tokens = split(strip(result["Solution"]))
#                 for i in 1:2:length(tokens)-1
#                     var = parse(Int, tokens[i])
#                     val = tokens[i+1] == "true"
#                     sol_dict[var] = val
#                 end
#             end
            
#             return (sol_dict, parse(Float64, result["Time"]), solver_name)
#         else
#             return (nothing, 0.0, solver_name)
#         end
        
#     finally
#         try
#             rm(temp_dir, recursive=true, force=true)
#         catch e
#             @warn "Failed to cleanup: $e"
#         end
#     end
# end

function main(args::Vector{String})
    solver_names, input_file, timeout = parse_args(args)

    if isnothing(input_file)
        println("Usage: julia main_multiprocess.jl [--race] [--timeout <seconds>] [--solver <n>]... <cnf file>")
        println("Available solvers: $(join(sort(SOLVERS), ", "))")
        println()
        println("Options:")
        println("  --solver <n>     Specify solver (can be used multiple times)")
        println("  --timeout <sec>  Set timeout in seconds (default: 300)")
        println()
        println("Examples:")
        println("  julia main_multiprocess.jl test.cnf")
        println("  julia main_multiprocess.jl --solver cdcl_vsids test.cnf")
        println("  julia main_multiprocess.jl --solver dpll --solver cdcl_vsids test.cnf")
        println("  julia main_multiprocess.jl --timeout 600 --solver cdcl_vsids --solver cdcl_vsids_luby test.cnf")
        return
    end

    # Validate all solvers
    for solver_name in solver_names
        if !(solver_name in SOLVERS)
            println("Unknown solver: $solver_name")
            println("Available solvers: $(join(sort(SOLVERS), ", "))")
            return
        end
    end
    
    # Check if file exists
    if !isfile(input_file)
        println("Error: File not found: $input_file")
        return
    end

    filename = basename(input_file)
    
    try
        # Parse instance to show info
        instance = parse_cnf_file(input_file)
        if !isnothing(instance)
            println("Instance: $filename")
            println("Variables: $(instance.numVars), Clauses: $(instance.numClauses)")
            println()
        end

        # Run solver(s)
        sol, elapsed, winning_solver = race_solvers_multiprocess(input_file, solver_names, timeout)

        # Format output
        sol_str = "--"
        result = "UNSAT"
        if !isnothing(sol)
            result = "SAT"
            sol_str = ""
            # Note: instance might be nothing if parsing failed, so get numVars from solution
            max_var = maximum(keys(sol))
            for var in 1:max_var
                sol_str *= string(var) * " "
                sol_str *= get(sol, var, false) ? "true " : "false "
            end
        end
        
        printSol = Dict(
            "Instance" => filename,
            "Time" => string(round(elapsed, digits=2)),
            "Result" => result,
            "Solution" => sol_str
        )
        
        println(JSON.json(printSol))
        
    catch e
        println("Error: $e")
        println(stderr, sprint(showerror, e, catch_backtrace()))
        rethrow(e)
    end
end

# Run main with command line arguments
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end