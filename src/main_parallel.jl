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

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()

using JSON
using .DimacsParser
using Base.Threads  # For parallel execution

const SOLVERS = Dict(
    "dpll"            => inst -> DPLLSolver.run_dpll(inst),
    "dpll_bad"        => inst -> DPLLBad.run_dpll(inst),
    "cdcl_basic"      => inst -> CDCLBasic.cdcl_solve(inst),
    "cdcl_vsids"      => inst -> CDCLVSIDS.cdcl_solve(inst),
    "cdcl_vsids_luby" => inst -> CDCLVSIDSLuby.cdcl_solve(inst),
    "cdcl_vsids_luby_sd" => inst -> CDCLVSIDSLubySd.cdcl_solve(inst),
    "cdcl_vsids_luby_nd" => inst -> CDCLVSIDSLubyNd.cdcl_solve(inst),
)

const DEFAULT_SOLVER = "dpll"

function parse_args(args::Vector{String})
    solver_names = String[]
    input_file = nothing
    race_mode = false

    i = 1
    while i <= length(args)
        if args[i] == "--solver"
            if i + 1 > length(args)
                error("--solver requires a value. Available: $(join(sort(collect(keys(SOLVERS))), ", "))")
            end
            push!(solver_names, args[i + 1])
            i += 2
        elseif args[i] == "--race"
            # Race mode: run multiple solvers in parallel
            race_mode = true
            i += 1
        else
            input_file = args[i]
            i += 1
        end
    end

    # Default to single solver if none specified
    if isempty(solver_names)
        push!(solver_names, DEFAULT_SOLVER)
    end

    return solver_names, input_file, race_mode
end

"""
    race_solvers(instance, solver_names) -> (solution, time, winning_solver)

Run multiple solvers in parallel on different threads.
Returns the first solution found along with the solver that found it.
"""
function race_solvers(instance::SATInstance, solver_names::Vector{String})
    n_solvers = length(solver_names)
    
    # Shared results - protected by atomic flag
    result_channel = Channel{Tuple{Union{Dict{Int,Bool},Nothing}, Float64, String}}(n_solvers)
    
    # Atomic flag to indicate when first solver finishes
    finished = Threads.Atomic{Bool}(false)
    
    # Launch all solvers in parallel
    @sync begin
        for solver_name in solver_names
            Threads.@spawn begin
                try
                    # All solvers run to completion, first to finish submits result
                    timer = Timer()
                    start!(timer)
                    
                    solve_fn = SOLVERS[solver_name]
                    sol = solve_fn(deepcopy(instance))
                    
                    stop!(timer)
                    elapsed = get_time(timer)
                    
                    # Use atomic compare-and-swap to ensure only first solver submits
                    if sol !== nothing
                        # Try to set finished from false to true
                        old_val = Threads.atomic_cas!(finished, false, true)
                        if old_val == false
                            # We successfully transitioned from false to true
                            # This means we're the first to finish with a solution
                            put!(result_channel, (sol, elapsed, solver_name))
                        end
                    elseif !finished[]
                        # This solver found UNSAT - only submit if no one found SAT yet
                        old_val = Threads.atomic_cas!(finished, false, true)
                        if old_val == false
                            put!(result_channel, (nothing, elapsed, solver_name))
                        end
                    end
                catch e
                    # If a solver crashes, log it but continue
                    @warn "Solver $solver_name crashed: $e"
                    println(stderr, "Stack trace:")
                    println(stderr, sprint(showerror, e, catch_backtrace()))
                end
            end
        end
    end
    
    close(result_channel)
    
    # Return the first (and only) result
    if isready(result_channel)
        return take!(result_channel)
    else
        # All solvers failed
        return (nothing, 0.0, "none")
    end
end

"""
    run_single_solver(instance, solver_name) -> (solution, time, solver_name)

Run a single solver and return its result.
"""
function run_single_solver(instance::SATInstance, solver_name::String)
    timer = Timer()
    start!(timer)
    
    solve_fn = SOLVERS[solver_name]
    sol = solve_fn(instance)
    
    stop!(timer)
    elapsed = get_time(timer)
    
    return (sol, elapsed, solver_name)
end

function main(args::Vector{String})
    solver_names, input_file, race_mode = parse_args(args)

    if isnothing(input_file)
        println("Usage: julia main.jl [--race] [--solver <name>]... <cnf file>")
        println("Available solvers: $(join(sort(collect(keys(SOLVERS))), ", "))")
        println()
        println("Options:")
        println("  --solver <name>  Specify solver (can be used multiple times)")
        println("  --race           Run multiple solvers in parallel, return first result")
        println()
        println("Examples:")
        println("  julia main.jl test.cnf                                    # Run default solver")
        println("  julia main.jl --solver cdcl_vsids test.cnf               # Run specific solver")
        println("  julia main.jl --race --solver dpll --solver cdcl_vsids test.cnf  # Race two solvers")
        return
    end

    # Validate all solvers
    for solver_name in solver_names
        if !haskey(SOLVERS, solver_name)
            println("Unknown solver: $solver_name")
            println("Available solvers: $(join(sort(collect(keys(SOLVERS))), ", "))")
            return
        end
    end

    filename = basename(input_file)
    
    try
        instance = parse_cnf_file(input_file)
        if !isnothing(instance)
            print(instance)
        end

        # Run solver(s)
        sol, elapsed, winning_solver = if race_mode && length(solver_names) > 1
            println("Racing $(length(solver_names)) solvers on $(Threads.nthreads()) threads...")
            race_solvers(instance, solver_names)
        else
            run_single_solver(instance, solver_names[1])
        end

        # Format output
        sol_str = "--"
        result = "UNSAT"
        if !isnothing(sol)
            result = "SAT"
            sol_str = ""
            for var in 1:instance.numVars
                sol_str *= string(var) * " "
                sol_str *= sol[var] ? "true " : "false "
            end
        end
        
        printSol = Dict(
            "Instance" => filename,
            "Time" => string(round(elapsed, digits=2)),
            "Result" => result,
            "Solution" => sol_str,
            "Solver" => winning_solver
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
