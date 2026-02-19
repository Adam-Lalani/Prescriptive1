module DPLLSolver

import ..SATInstance

# Optimized DPLL with 2-Watched Literals
mutable struct WatchedClause
    literals::Vector{Int}
    watch1::Int  # index into literals array
    watch2::Int  # index into literals array
    
    function WatchedClause(literals::Vector{Int})
        n = length(literals)
        if n == 0
            error("Empty clause - UNSAT")
        elseif n == 1
            new(literals, 1, 1)
        else
            new(literals, 1, 2)
        end
    end
end

mutable struct DPLL
    clauses::Vector{WatchedClause}
    watch_list::Dict{Int, Vector{Int}}
    assignment::Vector{Int8}  # 0=unassigned, 1=true, -1=false (indexed by variable)
    assignment_stack::Vector{Tuple{Int, Bool}}  # (var, value) for backtracking
    num_vars::Int
    decision_level::Int
    
    function DPLL(instance::SATInstance)
        num_vars = instance.numVars
        clauses = WatchedClause[]
        watch_list = Dict{Int, Vector{Int}}()
        
        for clause_set in instance.clauses
            clause_vec = collect(clause_set)
            if isempty(clause_vec)
                error("Empty clause found - UNSAT")
            end
            push!(clauses, WatchedClause(clause_vec))
        end
        
        # Initialize watch lists
        for (idx, clause) in enumerate(clauses)
            lit1 = clause.literals[clause.watch1]
            lit2 = clause.literals[clause.watch2]
            
            if !haskey(watch_list, lit1)
                watch_list[lit1] = Int[]
            end
            push!(watch_list[lit1], idx)
            
            if lit1 != lit2
                if !haskey(watch_list, lit2)
                    watch_list[lit2] = Int[]
                end
                push!(watch_list[lit2], idx)
            end
        end
        
        assignment = zeros(Int8, num_vars + 1)  # 1-indexed
        assignment_stack = Tuple{Int, Bool}[]
        
        new(clauses, watch_list, assignment, assignment_stack, num_vars, 0)
    end
end

@inline function is_satisfied(solver::DPLL, lit::Int)::Bool
    var = abs(lit)
    val = solver.assignment[var]
    if val == 0
        return false
    end
    return (lit > 0 && val == 1) || (lit < 0 && val == -1)
end

@inline function is_falsified(solver::DPLL, lit::Int)::Bool
    var = abs(lit)
    val = solver.assignment[var]
    if val == 0
        return false
    end
    return (lit > 0 && val == -1) || (lit < 0 && val == 1)
end

@inline function is_unassigned(solver::DPLL, lit::Int)::Bool
    return solver.assignment[abs(lit)] == 0
end

function assign!(solver::DPLL, var::Int, value::Bool)
    solver.assignment[var] = value ? Int8(1) : Int8(-1)
    push!(solver.assignment_stack, (var, value))
end

function backtrack!(solver::DPLL, level::Int)
    while length(solver.assignment_stack) > level
        var, _ = pop!(solver.assignment_stack)
        solver.assignment[var] = 0
    end
end

function propagate!(solver::DPLL, lit::Int)::Bool
    neg_lit = -lit
    
    if !haskey(solver.watch_list, neg_lit)
        return true
    end
    
    watching_clauses = solver.watch_list[neg_lit]
    i = 1
    
    while i <= length(watching_clauses)
        clause_idx = watching_clauses[i]
        clause = solver.clauses[clause_idx]
        
        lit1 = clause.literals[clause.watch1]
        lit2 = clause.literals[clause.watch2]
        
        if lit1 != neg_lit
            lit1, lit2 = lit2, lit1
            clause.watch1, clause.watch2 = clause.watch2, clause.watch1
        end
        
        if is_satisfied(solver, lit2)
            i += 1
            continue
        end
        
        found_new_watch = false
        for j in 1:length(clause.literals)
            if j == clause.watch1 || j == clause.watch2
                continue
            end
            
            lit_j = clause.literals[j]
            if !is_falsified(solver, lit_j)
                clause.watch1 = j
                deleteat!(watching_clauses, i)
                if !haskey(solver.watch_list, lit_j)
                    solver.watch_list[lit_j] = Int[]
                end
                push!(solver.watch_list[lit_j], clause_idx)
                found_new_watch = true
                break
            end
        end
        
        if found_new_watch
            continue
        end
        
        if is_falsified(solver, lit2)
            return false
        end
        
        if is_unassigned(solver, lit2)
            var2 = abs(lit2)
            value2 = lit2 > 0
            assign!(solver, var2, value2)
            
            if !propagate!(solver, lit2)
                return false
            end
        end
        
        i += 1
    end
    
    return true
end

function find_unit_clause(solver::DPLL)::Union{Int, Nothing}
    for clause in solver.clauses
        satisfied = false
        unassigned_lit = 0
        num_unassigned = 0
        
        for lit in clause.literals
            if is_satisfied(solver, lit)
                satisfied = true
                break
            elseif is_unassigned(solver, lit)
                unassigned_lit = lit
                num_unassigned += 1
            end
        end
        
        if !satisfied && num_unassigned == 1
            return unassigned_lit
        end
    end
    return nothing
end

function all_satisfied(solver::DPLL)::Bool
    for clause in solver.clauses
        clause_sat = false
        for lit in clause.literals
            if is_satisfied(solver, lit)
                clause_sat = true
                break
            end
        end
        if !clause_sat
            return false
        end
    end
    return true
end

function pick_branching_variable(solver::DPLL)::Union{Int, Nothing}
    best_var = 0
    best_score = typemax(Int)
    
    for clause in solver.clauses
        is_sat = false
        for lit in clause.literals
            if is_satisfied(solver, lit)
                is_sat = true
                break
            end
        end
        if is_sat
            continue
        end
        
        unassigned = Int[]
        for lit in clause.literals
            if is_unassigned(solver, lit)
                push!(unassigned, abs(lit))
            end
        end
        
        if !isempty(unassigned) && length(unassigned) < best_score
            best_score = length(unassigned)
            best_var = unassigned[1]
        end
    end
    
    if best_var == 0
        for var in 1:solver.num_vars
            if solver.assignment[var] == 0
                return var
            end
        end
        return nothing
    end
    
    return best_var
end

function solve!(solver::DPLL)::Bool
    while true
        unit_lit = find_unit_clause(solver)
        if isnothing(unit_lit)
            break
        end
        
        var = abs(unit_lit)
        value = unit_lit > 0
        assign!(solver, var, value)
        
        if !propagate!(solver, unit_lit)
            return false
        end
    end
    
    if all_satisfied(solver)
        return true
    end
    
    branch_var = pick_branching_variable(solver)
    if isnothing(branch_var)
        return all_satisfied(solver)
    end
    
    decision_point = length(solver.assignment_stack)
    assign!(solver, branch_var, true)
    
    if propagate!(solver, branch_var)
        if solve!(solver)
            return true
        end
    end
    
    backtrack!(solver, decision_point)
    assign!(solver, branch_var, false)
    
    if propagate!(solver, -branch_var)
        if solve!(solver)
            return true
        end
    end
    
    backtrack!(solver, decision_point)
    return false
end

function get_solution(solver::DPLL)::Dict{Int, Bool}
    solution = Dict{Int, Bool}()
    for var in 1:solver.num_vars
        if solver.assignment[var] != 0
            solution[var] = solver.assignment[var] == 1
        else
            solution[var] = true
        end
    end
    return solution
end

function run_dpll(instance::SATInstance)::Union{Dict{Int, Bool}, Nothing}
    try
        solver = DPLL(instance)
        if solve!(solver)
            return get_solution(solver)
        else
            return nothing
        end
    catch e
        if occursin("Empty clause", string(e))
            return nothing
        end
        rethrow(e)
    end
end

end # module DPLLSolver
