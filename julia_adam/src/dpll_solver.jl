include("sat_instance.jl")

# Track which two literals each clause watches
struct ClauseWatch
    watch1::Int  # First watched literal value
    watch2::Int  # Second watched literal value (0 if unit clause)
end

mutable struct Solver
    # Clauses as vectors for indexed access
    clauses::Vector{Vector{Int}}
    # For each clause, which literals it watches
    clause_watches::Vector{ClauseWatch}
    # For each literal, list of clause indices watching it
    watches::Dict{Int, Vector{Int}}
    # Current variable assignments (var -> true/false)
    assignment::Dict{Int, Bool}
    # Trail of assigned variables (for backtracking)
    trail::Vector{Int}
    # Decision level markers in trail
    trail_lim::Vector{Int}
    # Current decision level
    decision_level::Int
    # Propagation queue (literals to propagate)
    prop_queue::Vector{Int}
    # Propagation queue start index
    prop_qhead::Int
end

function Solver(instance::SATInstance)
    # Convert clauses from Set{Int} to Vector{Int}
    clauses = [collect(clause) for clause in instance.clauses]
    
    # Initialize watches
    watches = Dict{Int, Vector{Int}}()
    clause_watches = ClauseWatch[]
    
    for (idx, clause) in enumerate(clauses)
        if length(clause) == 0
            push!(clause_watches, ClauseWatch(0, 0))
            # Empty clause means UNSAT, but we'll handle it during solve
            continue
        elseif length(clause) == 1
            # Unit clause: watch the only literal
            lit = clause[1]
            if !haskey(watches, lit)
                watches[lit] = Int[]
            end
            push!(watches[lit], idx)
            push!(clause_watches, ClauseWatch(lit, 0))
        else
            # Watch first two literals
            lit1 = clause[1]
            lit2 = clause[2]
            if !haskey(watches, lit1)
                watches[lit1] = Int[]
            end
            if !haskey(watches, lit2)
                watches[lit2] = Int[]
            end
            push!(watches[lit1], idx)
            push!(watches[lit2], idx)
            push!(clause_watches, ClauseWatch(lit1, lit2))
        end
    end
    
    Solver(
        clauses,
        clause_watches,
        watches,
        Dict{Int, Bool}(),
        Int[],
        Int[],
        0,
        Int[],
        0
    )
end

# Check if a literal is satisfied (true) under current assignment
function is_satisfied(solver::Solver, lit::Int)::Bool
    var = abs(lit)
    if !haskey(solver.assignment, var)
        return false
    end
    return (lit > 0) == solver.assignment[var]
end

# Check if a literal is falsified (false) under current assignment
function is_falsified(solver::Solver, lit::Int)::Bool
    var = abs(lit)
    if !haskey(solver.assignment, var)
        return false
    end
    return (lit > 0) != solver.assignment[var]
end

# Assign a variable and add to trail
function assign!(solver::Solver, var::Int, val::Bool)
    if haskey(solver.assignment, var)
        return  # Already assigned
    end
    solver.assignment[var] = val
    push!(solver.trail, var)
    # Add to propagation queue
    lit = val ? var : -var
    push!(solver.prop_queue, lit)
end

# Propagate using 2-watched literals
# Returns (conflict_clause_idx, true) if conflict found, (nothing, false) otherwise
function propagate!(solver::Solver)::Tuple{Union{Int, Nothing}, Bool}
    while solver.prop_qhead < length(solver.prop_queue)
        lit = solver.prop_queue[solver.prop_qhead + 1]
        solver.prop_qhead += 1
        falsified_lit = -lit  # The literal that just became false
        
        # Get clauses watching this falsified literal
        if !haskey(solver.watches, falsified_lit)
            continue
        end
        
        watch_list = copy(solver.watches[falsified_lit])  # Copy to avoid modification during iteration
        for clause_idx in watch_list
            clause = solver.clauses[clause_idx]
            watch = solver.clause_watches[clause_idx]
            
            # Skip if clause is already satisfied
            if watch.watch1 != 0 && is_satisfied(solver, watch.watch1)
                continue
            end
            if watch.watch2 != 0 && is_satisfied(solver, watch.watch2)
                continue
            end
            
            # Find which watched literal was falsified
            if watch.watch1 != falsified_lit && watch.watch2 != falsified_lit
                continue  # This clause isn't watching the falsified literal
            end
            
            # Find the other watched literal
            other_watch = (watch.watch1 == falsified_lit) ? watch.watch2 : watch.watch1
            
            # Check if other watched literal is satisfied
            if other_watch != 0 && is_satisfied(solver, other_watch)
                continue  # Clause is satisfied
            end
            
            # Look for a new literal to watch
            new_watch = nothing
            for lit in clause
                if lit == falsified_lit || lit == other_watch
                    continue
                end
                if !is_falsified(solver, lit)
                    new_watch = lit
                    break
                end
            end
            
            if new_watch !== nothing
                # Found replacement: update watches
                # Remove from old watch list
                watch_list_orig = solver.watches[falsified_lit]
                filter!(x -> x != clause_idx, watch_list_orig)
                # Add to new watch list
                if !haskey(solver.watches, new_watch)
                    solver.watches[new_watch] = Int[]
                end
                push!(solver.watches[new_watch], clause_idx)
                # Update clause watch
                if watch.watch1 == falsified_lit
                    solver.clause_watches[clause_idx] = ClauseWatch(new_watch, watch.watch2)
                else
                    solver.clause_watches[clause_idx] = ClauseWatch(watch.watch1, new_watch)
                end
            else
                # No replacement found - need to propagate or conflict
                if other_watch != 0 && !is_falsified(solver, other_watch)
                    # Unit clause: propagate other_watch
                    var = abs(other_watch)
                    val = other_watch > 0
                    if haskey(solver.assignment, var)
                        if solver.assignment[var] != val
                            # Conflict!
                            return (clause_idx, true)
                        end
                    else
                        assign!(solver, var, val)
                    end
                else
                    # Conflict: both watched literals are false (or unit clause with no replacement)
                    return (clause_idx, true)
                end
            end
        end
    end
    
    return (nothing, false)
end

# Pick next variable to branch on (simple heuristic: first unassigned)
function pick_branching_var(solver::Solver, all_vars::Set{Int})::Union{Int, Nothing}
    for var in all_vars
        if !haskey(solver.assignment, var)
            return var
        end
    end
    return nothing
end

# Backtrack to a given decision level
function backtrack!(solver::Solver, level::Int)
    if level < 0
        level = 0
    end
    # trail_lim[i] stores trail length at start of decision level i-1
    # So for level L, we need trail_lim[L+1] (1-indexed)
    target_len = 0
    if level == 0
        target_len = 0
    elseif level + 1 <= length(solver.trail_lim)
        target_len = solver.trail_lim[level + 1]
    else
        # Level doesn't exist yet, use current trail length
        target_len = length(solver.trail)
    end
    
    while length(solver.trail) > target_len
        var = pop!(solver.trail)
        delete!(solver.assignment, var)
    end
    solver.prop_qhead = target_len
    solver.decision_level = level
    # Resize trail_lim to keep only up to level (level+1 elements since 1-indexed)
    if length(solver.trail_lim) > level + 1
        resize!(solver.trail_lim, level + 1)
    end
end

# Main DPLL solve function
function solve(instance::SATInstance)::Union{Dict{Int, Bool}, Nothing}
    if instance === nothing
        return nothing
    end
    
    # Check for empty clauses (immediate UNSAT)
    for clause in instance.clauses
        if isempty(clause)
            return nothing  # UNSAT
        end
    end
    
    solver = Solver(instance)
    
    # Initial unit propagation
    solver.decision_level = 0
    push!(solver.trail_lim, 0)
    conflict_clause, has_conflict = propagate!(solver)
    if has_conflict
        return nothing  # UNSAT
    end
    
    # Main DPLL loop
    while true
        # Check if all variables are assigned
        if length(solver.assignment) >= length(instance.vars)
            # Complete assignment for all variables
            result = Dict{Int, Bool}()
            for var in instance.vars
                if haskey(solver.assignment, var)
                    result[var] = solver.assignment[var]
                else
                    result[var] = true  # Default assignment
                end
            end
            return result
        end
        
        # Pick branching variable
        var = pick_branching_var(solver, instance.vars)
        if var === nothing
            # All variables assigned
            result = Dict{Int, Bool}()
            for v in instance.vars
                result[v] = haskey(solver.assignment, v) ? solver.assignment[v] : true
            end
            return result
        end
        
        # Try assigning var = true
        old_level = solver.decision_level
        solver.decision_level += 1
        push!(solver.trail_lim, length(solver.trail))
        assign!(solver, var, true)
        
        conflict_clause, has_conflict = propagate!(solver)
        if !has_conflict
            continue  # Continue with this branch
        end
        
        # Conflict with var = true, backtrack and try var = false
        backtrack!(solver, old_level)
        solver.decision_level = old_level + 1
        push!(solver.trail_lim, length(solver.trail))
        assign!(solver, var, false)
        
        conflict_clause, has_conflict = propagate!(solver)
        if !has_conflict
            continue  # Continue with this branch
        end
        
        # Conflict with both assignments, backtrack to previous level
        if old_level == 0
            # Can't backtrack further, UNSAT
            return nothing
        end
        
        # Backtrack to previous decision level
        backtrack!(solver, old_level - 1)
        solver.decision_level = old_level - 1
    end
end
