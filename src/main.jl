include("sat_instance.jl")
include("dimacs_parser.jl")
include("model_timer.jl")

include("solvers/dpll.jl")
include("solvers/dpll_bad.jl")
include("solvers/cdcl_basic_solver.jl")
include("solvers/cdcl_vsids_solver.jl")
include("solvers/cdcl_vsids_luby_solver.jl")

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()

using JSON
using .DimacsParser

const SOLVERS = Dict(
    "dpll"            => inst -> DPLLSolver.run_dpll(inst),
    "dpll_bad"        => inst -> DPLLBad.run_dpll(inst),
    "cdcl_basic"      => inst -> CDCLBasic.cdcl_solve(inst),
    "cdcl_vsids"      => inst -> CDCLVSIDS.cdcl_solve(inst),
    "cdcl_vsids_luby" => inst -> CDCLVSIDSLuby.cdcl_solve(inst),
)

const DEFAULT_SOLVER = "dpll"

function parse_args(args::Vector{String})
    solver_name = DEFAULT_SOLVER
    input_file = nothing

    i = 1
    while i <= length(args)
        if args[i] == "--solver"
            if i + 1 > length(args)
                error("--solver requires a value. Available: $(join(sort(collect(keys(SOLVERS))), ", "))")
            end
            solver_name = args[i + 1]
            i += 2
        else
            input_file = args[i]
            i += 1
        end
    end

    return solver_name, input_file
end

function main(args::Vector{String})
    solver_name, input_file = parse_args(args)

    if isnothing(input_file)
        println("Usage: julia main.jl [--solver <name>] <cnf file>")
        println("Available solvers: $(join(sort(collect(keys(SOLVERS))), ", "))")
        return
    end

    if !haskey(SOLVERS, solver_name)
        println("Unknown solver: $solver_name")
        println("Available solvers: $(join(sort(collect(keys(SOLVERS))), ", "))")
        return
    end

    solve_fn = SOLVERS[solver_name]
    filename = basename(input_file)
    
    timer = Timer()
    start!(timer)
    
    try
        instance = parse_cnf_file(input_file)
        if !isnothing(instance)
            print(instance)
        end
        
        sol = solve_fn(instance)
        
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
