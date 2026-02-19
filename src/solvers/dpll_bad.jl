module DPLLBad

import ..SATInstance

# Highly optimized DPLL with multiple speed improvements
mutable struct WatchedClauseOptimized
    literals::Vector{Int32}  # Int32 for better cache efficiency
    watch1::Int32
    watch2::Int32
    
    function WatchedClauseOptimized(literals::Vector{Int})
        n = length(literals)
        if n == 0
            error("Empty clause - UNSAT")
        end
        lits = Int32.(literals)
        if n == 1
            new(lits, Int32(1), Int32(1))
        else
            new(lits, Int32(1), Int32(2))
        end
    end
end

mutable struct DPLL
    clauses::Vector{WatchedClauseOptimized}
    watch_list::Vector{Vector{Int32}}  # Indexed by literal encoding
    assignment::Vector{Int8}  # 0=unassigned, 1=true, -1=false
    assignment_stack::Vector{Int32}  # Just variables, value derived from assignment
    decision_level::Vector{Int32}  # Decision level for each assignment
    num_vars::Int32
    current_level::Int32
    
    # VSIDS heuristic data
    activity::Vector{Float32}  # Activity score for each variable
    activity_inc::Float32
    activity_decay::Float32
    heap::Vector{Int32}  # Max-heap for variable selection
    heap_pos::Vector{Int32}  # Position in heap for each variable
    heap_size::Int32
    
    # Statistics for adaptive restarts
    conflicts::Int32
    
    function DPLL(instance::SATInstance)
        num_vars = Int32(instance.numVars)
        clauses = WatchedClauseOptimized[]
        
        watch_list = [Int32[] for _ in 1:(2*num_vars + 2)]
        
        for clause_set in instance.clauses
            clause_vec = collect(clause_set)
            if isempty(clause_vec)
                error("Empty clause found - UNSAT")
            end
            push!(clauses, WatchedClauseOptimized(clause_vec))
        end
        
        # Initialize watch lists
        for (idx, clause) in enumerate(clauses)
            lit1 = clause.literals[clause.watch1]
            lit2 = clause.literals[clause.watch2]
            
            enc1 = encode_literal(lit1, num_vars)
            enc2 = encode_literal(lit2, num_vars)
            
            push!(watch_list[enc1], Int32(idx))
            if lit1 != lit2
                push!(watch_list[enc2], Int32(idx))
            end
        end
        
        assignment = zeros(Int8, num_vars + 1)
        assignment_stack = Int32[]
        decision_level = zeros(Int32, num_vars + 1)
        
        # Initialize VSIDS
        activity = zeros(Float32, num_vars + 1)
        heap = collect(Int32(1):num_vars)
        heap_pos = collect(Int32(1):num_vars)
        heap_pos[1] = Int32(0)
        
        new(clauses, watch_list, assignment, assignment_stack, decision_level,
            num_vars, Int32(0), activity, Float32(1.0), Float32(0.95),
            heap, heap_pos, num_vars, Int32(0))
    end
end

@inline function encode_literal(lit::Int32, num_vars::Int32)::Int32
    var = abs(lit)
    return lit > 0 ? Int32(var * 2) : Int32(var * 2 + 1)
end

@inline function encode_literal(lit::Int, num_vars::Int32)::Int32
    return encode_literal(Int32(lit), num_vars)
end

@inline function lit_value(solver::DPLL, lit::Int32)::Int8
    var = abs(lit)
    val = solver.assignment[var]
    if val == 0
        return Int8(0)
    end
    return (lit > 0) == (val == 1) ? Int8(1) : Int8(-1)
end

@inline function assign!(solver::DPLL, var::Int32, value::Bool)
    solver.assignment[var] = value ? Int8(1) : Int8(-1)
    solver.decision_level[var] = solver.current_level
    push!(solver.assignment_stack, var)
end

function backtrack!(solver::DPLL, level::Int32)
    while !isempty(solver.assignment_stack)
        var = solver.assignment_stack[end]
        if solver.decision_level[var] <= level
            break
        end
        pop!(solver.assignment_stack)
        solver.assignment[var] = Int8(0)
        solver.decision_level[var] = Int32(0)
    end
    solver.current_level = level
end

@inline function heap_parent(i::Int32)::Int32
    return i >> 1
end

@inline function heap_left(i::Int32)::Int32
    return i << 1
end

@inline function heap_right(i::Int32)::Int32
    return (i << 1) | Int32(1)
end

function heap_swap!(solver::DPLL, i::Int32, j::Int32)
    heap = solver.heap
    pos = solver.heap_pos
    
    var_i = heap[i]
    var_j = heap[j]
    
    heap[i] = var_j
    heap[j] = var_i
    
    pos[var_i] = j
    pos[var_j] = i
end

function heap_up!(solver::DPLL, i::Int32)
    heap = solver.heap
    activity = solver.activity
    
    while i > 1
        parent = heap_parent(i)
        if activity[heap[i]] <= activity[heap[parent]]
            break
        end
        heap_swap!(solver, i, parent)
        i = parent
    end
end

function heap_down!(solver::DPLL, i::Int32)
    heap = solver.heap
    activity = solver.activity
    size = solver.heap_size
    
    while true
        largest = i
        left = heap_left(i)
        right = heap_right(i)
        
        if left <= size && activity[heap[left]] > activity[heap[largest]]
            largest = left
        end
        if right <= size && activity[heap[right]] > activity[heap[largest]]
            largest = right
        end
        
        if largest == i
            break
        end
        
        heap_swap!(solver, i, largest)
        i = largest
    end
end

function heap_insert!(solver::DPLL, var::Int32)
    solver.heap_size += Int32(1)
    solver.heap[solver.heap_size] = var
    solver.heap_pos[var] = solver.heap_size
    heap_up!(solver, solver.heap_size)
end

function heap_remove_max!(solver::DPLL)::Int32
    if solver.heap_size == 0
        return Int32(0)
    end
    
    max_var = solver.heap[1]
    solver.heap_pos[max_var] = Int32(0)
    
    if solver.heap_size > 1
        solver.heap[1] = solver.heap[solver.heap_size]
        solver.heap_pos[solver.heap[1]] = Int32(1)
        solver.heap_size -= Int32(1)
        heap_down!(solver, Int32(1))
    else
        solver.heap_size = Int32(0)
    end
    
    return max_var
end

function bump_activity!(solver::DPLL, var::Int32)
    solver.activity[var] += solver.activity_inc
    
    if solver.activity[var] > Float32(1e20)
        for v in 1:solver.num_vars
            solver.activity[v] *= Float32(1e-20)
        end
        solver.activity_inc *= Float32(1e-20)
    end
    
    pos = solver.heap_pos[var]
    if pos > 0
        heap_up!(solver, pos)
    end
end

function decay_activity!(solver::DPLL)
    solver.activity_inc /= solver.activity_decay
end

function propagate!(solver::DPLL, lit::Int32)::Int32
    queue = Int32[lit]
    queue_head = 1
    
    while queue_head <= length(queue)
        curr_lit = queue[queue_head]
        queue_head += 1
        
        neg_lit_enc = encode_literal(-curr_lit, solver.num_vars)
        watching_clauses = solver.watch_list[neg_lit_enc]
        
        i = 1
        while i <= length(watching_clauses)
            clause_idx = watching_clauses[i]
            clause = solver.clauses[clause_idx]
            
            lit1 = clause.literals[clause.watch1]
            lit2 = clause.literals[clause.watch2]
            
            if lit1 != -curr_lit
                lit1, lit2 = lit2, lit1
                clause.watch1, clause.watch2 = clause.watch2, clause.watch1
            end
            
            val2 = lit_value(solver, lit2)
            if val2 == 1
                i += 1
                continue
            end
            
            found_new = false
            for j in Int32(1):Int32(length(clause.literals))
                if j == clause.watch1 || j == clause.watch2
                    continue
                end
                
                lit_j = clause.literals[j]
                val_j = lit_value(solver, lit_j)
                
                if val_j != -1
                    clause.watch1 = j
                    deleteat!(watching_clauses, i)
                    
                    enc_j = encode_literal(lit_j, solver.num_vars)
                    push!(solver.watch_list[enc_j], clause_idx)
                    
                    found_new = true
                    break
                end
            end
            
            if found_new
                continue
            end
            
            if val2 == -1
                return clause_idx
            end
            
            if val2 == 0
                var2 = abs(lit2)
                value2 = lit2 > 0
                assign!(solver, var2, value2)
                push!(queue, lit2)
            end
            
            i += 1
        end
    end
    
    return Int32(0)
end

function pick_branching_variable(solver::DPLL)::Int32
    while solver.heap_size > 0
        var = heap_remove_max!(solver)
        if solver.assignment[var] == 0
            return var
        end
    end
    return Int32(0)
end

function analyze_conflict!(solver::DPLL, conflict_clause_idx::Int32)::Int32
    clause = solver.clauses[conflict_clause_idx]
    
    for lit in clause.literals
        var = abs(lit)
        bump_activity!(solver, var)
    end
    
    decay_activity!(solver)
    solver.conflicts += Int32(1)
    
    if solver.current_level > 0
        return solver.current_level - Int32(1)
    end
    return Int32(-1)
end

function solve!(solver::DPLL)::Bool
    for clause in solver.clauses
        if length(clause.literals) == 1
            lit = clause.literals[1]
            var = abs(lit)
            
            if solver.assignment[var] != 0
                continue
            end
            
            value = lit > 0
            assign!(solver, var, value)
            
            conflict = propagate!(solver, lit)
            if conflict != 0
                return false
            end
        end
    end
    
    while true
        all_assigned = true
        for v in Int32(1):solver.num_vars
            if solver.assignment[v] == 0
                all_assigned = false
                break
            end
        end
        
        if all_assigned
            return true
        end
        
        branch_var = pick_branching_variable(solver)
        if branch_var == 0
            return true
        end
        
        solver.current_level += Int32(1)
        assign!(solver, branch_var, true)
        
        conflict = propagate!(solver, branch_var)
        
        if conflict != 0
            backtrack_level = analyze_conflict!(solver, conflict)
            
            if backtrack_level < 0
                return false
            end
            
            backtrack!(solver, backtrack_level)
            
            solver.current_level += Int32(1)
            assign!(solver, branch_var, false)
            
            conflict = propagate!(solver, -branch_var)
            
            if conflict != 0
                backtrack_level = analyze_conflict!(solver, conflict)
                if backtrack_level < 0
                    return false
                end
                backtrack!(solver, backtrack_level)
            end
        end
        
        if solver.conflicts % Int32(100) == 0 && solver.conflicts > 0
            backtrack!(solver, Int32(0))
        end
    end
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

end # module DPLLBad
