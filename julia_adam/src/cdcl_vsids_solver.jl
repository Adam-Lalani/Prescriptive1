include("sat_instance.jl")

# ──────────────────────────────────────────────────────────────────────────────
# Literal helpers
#   variable v  ∈ 1..n
#   positive literal  v  → index 2v
#   negative literal -v  → index 2v-1
# ──────────────────────────────────────────────────────────────────────────────

@inline lit_index(lit::Int)::Int = lit > 0 ? 2 * lit : 2 * (-lit) - 1
@inline lit_sign(lit::Int)::Bool = lit > 0
@inline lit_var(lit::Int)::Int = abs(lit)
@inline lit_neg(lit::Int)::Int = -lit

# ──────────────────────────────────────────────────────────────────────────────
# Variable-activity max-heap for VSIDS
# ──────────────────────────────────────────────────────────────────────────────

mutable struct VarHeap
    heap::Vector{Int}           # heap storage (variable ids)
    indices::Vector{Int}        # indices[v] = position in heap (-1 if absent)
    activity::Vector{Float64}   # reference to solver activity array (shared)
end

function VarHeap(n::Int, activity::Vector{Float64})
    VarHeap(Int[], fill(-1, n), activity)
end

@inline heap_parent(i::Int) = div(i, 2)
@inline heap_left(i::Int)   = 2 * i
@inline heap_right(i::Int)  = 2 * i + 1

function heap_swap!(h::VarHeap, i::Int, j::Int)
    h.indices[h.heap[i]] = j
    h.indices[h.heap[j]] = i
    h.heap[i], h.heap[j] = h.heap[j], h.heap[i]
end

function heap_sift_up!(h::VarHeap, pos::Int)
    v = h.heap[pos]
    while pos > 1
        p = heap_parent(pos)
        if h.activity[h.heap[p]] >= h.activity[v]
            break
        end
        heap_swap!(h, pos, p)
        pos = p
    end
end

function heap_sift_down!(h::VarHeap, pos::Int)
    sz = length(h.heap)
    while true
        best = pos
        l = heap_left(pos)
        r = heap_right(pos)
        if l <= sz && h.activity[h.heap[l]] > h.activity[h.heap[best]]
            best = l
        end
        if r <= sz && h.activity[h.heap[r]] > h.activity[h.heap[best]]
            best = r
        end
        if best == pos
            break
        end
        heap_swap!(h, pos, best)
        pos = best
    end
end

function heap_insert!(h::VarHeap, v::Int)
    if h.indices[v] != -1
        return  # already in heap
    end
    push!(h.heap, v)
    pos = length(h.heap)
    h.indices[v] = pos
    heap_sift_up!(h, pos)
end

function heap_remove_max!(h::VarHeap)::Int
    v = h.heap[1]
    h.indices[v] = -1
    last = pop!(h.heap)
    if !isempty(h.heap)
        h.heap[1] = last
        h.indices[last] = 1
        heap_sift_down!(h, 1)
    end
    return v
end

function heap_update!(h::VarHeap, v::Int)
    pos = h.indices[v]
    if pos == -1
        return
    end
    heap_sift_up!(h, pos)
    heap_sift_down!(h, h.indices[v])
end

function heap_contains(h::VarHeap, v::Int)::Bool
    return h.indices[v] != -1
end

# ──────────────────────────────────────────────────────────────────────────────
# Watched-literal entry: stores the other literal for fast checking
# ──────────────────────────────────────────────────────────────────────────────

struct Watcher
    clause_idx::Int   # which clause
    blocker::Int      # the other watched literal (quick sat check)
end

# ──────────────────────────────────────────────────────────────────────────────
# CDCLSolver
# ──────────────────────────────────────────────────────────────────────────────

mutable struct CDCLSolver
    num_vars::Int
    clauses::Vector{Vector{Int}}

    # 2-Watched Literals: watches[lit_index(l)] = watchers for literal l
    watches::Vector{Vector{Watcher}}

    # Per-variable arrays (indexed 1..num_vars)
    values::Vector{Int8}       # 0 = unassigned, 1 = true, -1 = false
    levels::Vector{Int}        # decision level of assignment
    reasons::Vector{Int}       # antecedent clause index (0 = decision / unassigned)
    polarity::Vector{Bool}     # phase saving
    seen::Vector{Bool}         # scratch for conflict analysis

    # Trail
    trail::Vector{Int}         # assigned literals in order
    trail_lim::Vector{Int}     # trail index at start of each decision level
    qhead::Int                 # next position in trail to propagate

    # VSIDS
    activity::Vector{Float64}
    var_inc::Float64
    var_decay::Float64
    order_heap::VarHeap

    # Bookkeeping
    num_original_clauses::Int
    num_conflicts::Int
    num_decisions::Int
    num_propagations::Int
end

# ──────────────────────────────────────────────────────────────────────────────
# Constructor
# ──────────────────────────────────────────────────────────────────────────────

function CDCLSolver(instance::SATInstance)
    n = instance.numVars
    num_lits = 2 * n

    watches  = [Watcher[] for _ in 1:num_lits]
    values   = zeros(Int8, n)
    levels   = zeros(Int, n)
    reasons  = zeros(Int, n)
    polarity = fill(false, n)
    seen     = fill(false, n)
    activity = zeros(Float64, n)

    order_heap = VarHeap(n, activity)

    solver = CDCLSolver(
        n,
        Vector{Int}[],          # clauses (filled below)
        watches,
        values, levels, reasons, polarity, seen,
        Int[], Int[], 0,        # trail, trail_lim, qhead
        activity, 1.0, 0.95, order_heap,
        0, 0, 0, 0             # bookkeeping
    )

    # Add original clauses
    for clause_set in instance.clauses
        c = collect(clause_set)
        add_clause!(solver, c, true)
    end

    solver.num_original_clauses = length(solver.clauses)

    # Insert all variables into the heap
    for v in 1:n
        heap_insert!(solver.order_heap, v)
    end

    return solver
end

# ──────────────────────────────────────────────────────────────────────────────
# Value helpers
# ──────────────────────────────────────────────────────────────────────────────

@inline function lit_value(solver::CDCLSolver, lit::Int)::Int8
    v = lit_var(lit)
    val = solver.values[v]
    if val == 0
        return Int8(0)
    end
    return lit > 0 ? val : -val
end

@inline current_level(solver::CDCLSolver) = length(solver.trail_lim)

# ──────────────────────────────────────────────────────────────────────────────
# Clause management
# ──────────────────────────────────────────────────────────────────────────────

function add_clause!(solver::CDCLSolver, lits::Vector{Int}, original::Bool)::Int
    push!(solver.clauses, lits)
    cidx = length(solver.clauses)

    if length(lits) >= 2
        # Watch first two literals
        push!(solver.watches[lit_index(lits[1])], Watcher(cidx, lits[2]))
        push!(solver.watches[lit_index(lits[2])], Watcher(cidx, lits[1]))
    end

    return cidx
end

# ──────────────────────────────────────────────────────────────────────────────
# Enqueue: assign a literal at the current decision level
# ──────────────────────────────────────────────────────────────────────────────

function enqueue!(solver::CDCLSolver, lit::Int, reason::Int)::Bool
    v = lit_var(lit)
    if solver.values[v] != 0
        return solver.values[v] == (lit > 0 ? Int8(1) : Int8(-1))
    end
    solver.values[v]  = lit > 0 ? Int8(1) : Int8(-1)
    solver.levels[v]  = current_level(solver)
    solver.reasons[v] = reason
    push!(solver.trail, lit)
    return true
end

# ──────────────────────────────────────────────────────────────────────────────
# New decision level
# ──────────────────────────────────────────────────────────────────────────────

function new_decision_level!(solver::CDCLSolver)
    push!(solver.trail_lim, length(solver.trail))
end

# ──────────────────────────────────────────────────────────────────────────────
# 2-Watched-Literal Boolean Constraint Propagation
# Returns 0 if no conflict, or the conflict clause index
# ──────────────────────────────────────────────────────────────────────────────

function propagate!(solver::CDCLSolver)::Int
    while solver.qhead < length(solver.trail)
        solver.qhead += 1
        p = solver.trail[solver.qhead]          # literal that became true
        solver.num_propagations += 1

        false_lit = lit_neg(p)                   # this literal is now false
        fidx = lit_index(false_lit)

        ws = solver.watches[fidx]
        new_ws = Watcher[]                       # rebuilt watch list

        i = 1
        conflict = 0
        while i <= length(ws)
            w = ws[i]

            # Quick check: if blocker is satisfied, clause is satisfied
            if lit_value(solver, w.blocker) == Int8(1)
                push!(new_ws, w)
                i += 1
                continue
            end

            clause = solver.clauses[w.clause_idx]
            clen = length(clause)

            # Make sure false_lit is at clause[2] (swap if needed)
            if clen >= 2
                if clause[1] == false_lit
                    clause[1], clause[2] = clause[2], clause[1]
                end
            end

            # If first literal is satisfied, update blocker and keep watching
            if clen >= 1 && lit_value(solver, clause[1]) == Int8(1)
                push!(new_ws, Watcher(w.clause_idx, clause[1]))
                i += 1
                continue
            end

            # Look for a new literal to watch (from clause[3] onward)
            found_new = false
            if clen >= 3
                for k in 3:clen
                    if lit_value(solver, clause[k]) != Int8(-1)
                        # Swap clause[2] and clause[k]
                        clause[2], clause[k] = clause[k], clause[2]
                        # Add watcher to the new literal's list
                        push!(solver.watches[lit_index(clause[2])],
                              Watcher(w.clause_idx, clause[1]))
                        found_new = true
                        break
                    end
                end
            end

            if found_new
                i += 1
                continue
            end

            # No replacement found: clause is unit or conflicting
            if clen >= 1 && lit_value(solver, clause[1]) == Int8(-1)
                # Conflict: all literals false
                conflict = w.clause_idx
                # Copy remaining watchers
                push!(new_ws, w)
                for j in (i+1):length(ws)
                    push!(new_ws, ws[j])
                end
                solver.watches[fidx] = new_ws
                return conflict
            end

            # Unit propagation: clause[1] is the only non-false literal
            push!(new_ws, Watcher(w.clause_idx, clause[1]))
            if clen >= 1
                if !enqueue!(solver, clause[1], w.clause_idx)
                    # Conflict during enqueue (shouldn't happen with correct 2WL)
                    conflict = w.clause_idx
                    for j in (i+1):length(ws)
                        push!(new_ws, ws[j])
                    end
                    solver.watches[fidx] = new_ws
                    return conflict
                end
            end
            i += 1
        end

        solver.watches[fidx] = new_ws
    end

    return 0  # no conflict
end

# ──────────────────────────────────────────────────────────────────────────────
# VSIDS: bump variable activity
# ──────────────────────────────────────────────────────────────────────────────

function var_bump_activity!(solver::CDCLSolver, v::Int)
    solver.activity[v] += solver.var_inc
    # Rescale if activities get too large
    if solver.activity[v] > 1e100
        for i in 1:solver.num_vars
            solver.activity[i] *= 1e-100
        end
        solver.var_inc *= 1e-100
    end
    if heap_contains(solver.order_heap, v)
        heap_update!(solver.order_heap, v)
    end
end

function var_decay_activity!(solver::CDCLSolver)
    solver.var_inc *= (1.0 / solver.var_decay)
end

# ──────────────────────────────────────────────────────────────────────────────
# Conflict analysis – 1-UIP scheme
# Returns (learned_clause, backtrack_level)
# The asserting literal is placed at learned_clause[1]
# ──────────────────────────────────────────────────────────────────────────────

function analyze(solver::CDCLSolver, conflict::Int)::Tuple{Vector{Int}, Int}
    learned = Int[]
    trail_idx = length(solver.trail)
    counter = 0          # number of literals at current level still to resolve
    p = 0                # literal being resolved
    reason = conflict    # current reason clause

    fill!(solver.seen, false)

    while true
        clause = solver.clauses[reason]
        for lit in clause
            v = lit_var(lit)
            if v == lit_var(p) && p != 0
                continue  # skip the pivot literal
            end
            if solver.seen[v]
                continue
            end
            solver.seen[v] = true
            var_bump_activity!(solver, v)

            if solver.levels[v] == current_level(solver)
                counter += 1
            else
                # Literal at a lower level goes into the learned clause
                push!(learned, lit)
            end
        end

        # Walk the trail backwards to find the next seen literal at the current level
        while true
            p = solver.trail[trail_idx]
            trail_idx -= 1
            if solver.seen[lit_var(p)]
                break
            end
        end
        counter -= 1
        if counter == 0
            break
        end
        reason = solver.reasons[lit_var(p)]
    end

    # p is the 1-UIP literal; negate it for the learned clause
    pushfirst!(learned, lit_neg(p))

    # Compute backtrack level = highest level among non-asserting literals
    bt_level = 0
    if length(learned) > 1
        # Find the literal with the highest level (among learned[2:end])
        max_idx = 2
        max_lvl = solver.levels[lit_var(learned[2])]
        for i in 3:length(learned)
            lvl = solver.levels[lit_var(learned[i])]
            if lvl > max_lvl
                max_lvl = lvl
                max_idx = i
            end
        end
        # Swap it to position 2 so watched-literal setup works correctly
        learned[2], learned[max_idx] = learned[max_idx], learned[2]
        bt_level = max_lvl
    end

    var_decay_activity!(solver)

    return (learned, bt_level)
end

# ──────────────────────────────────────────────────────────────────────────────
# Backtrack (cancel) to a given decision level
# ──────────────────────────────────────────────────────────────────────────────

function backtrack!(solver::CDCLSolver, level::Int)
    if current_level(solver) <= level
        return
    end
    target = solver.trail_lim[level + 1]  # 1-indexed; level 0 → trail_lim[1]
    while length(solver.trail) > target
        lit = pop!(solver.trail)
        v = lit_var(lit)
        solver.polarity[v] = lit > 0
        solver.values[v]  = Int8(0)
        solver.reasons[v] = 0
        # Re-insert into VSIDS heap
        if !heap_contains(solver.order_heap, v)
            heap_insert!(solver.order_heap, v)
        end
    end
    solver.qhead = length(solver.trail)
    resize!(solver.trail_lim, level)
end

# ──────────────────────────────────────────────────────────────────────────────
# Pick branching variable using VSIDS heap
# ──────────────────────────────────────────────────────────────────────────────

function pick_branching_var(solver::CDCLSolver)::Union{Int, Nothing}
    while !isempty(solver.order_heap.heap)
        v = heap_remove_max!(solver.order_heap)
        if solver.values[v] == Int8(0)
            return v
        end
    end
    return nothing
end

# ──────────────────────────────────────────────────────────────────────────────
# Luby restart sequence
# ──────────────────────────────────────────────────────────────────────────────

function luby(y::Float64, x::Int)::Float64
    sz = 1
    seq = 0
    while sz < x + 1
        seq += 1
        sz = 2 * sz + 1
    end
    while sz - 1 != x
        sz = div(sz - 1, 2)
        seq -= 1
        if x >= sz
            x -= sz
        end
    end
    return y^seq
end

# ──────────────────────────────────────────────────────────────────────────────
# Main CDCL solve entry point
# ──────────────────────────────────────────────────────────────────────────────

function cdcl_solve(instance::SATInstance)::Union{Dict{Int, Bool}, Nothing}
    if instance === nothing
        return nothing
    end

    # Check for empty clauses
    for clause in instance.clauses
        if isempty(clause)
            return nothing
        end
    end

    solver = CDCLSolver(instance)

    # Handle unit clauses at level 0 — enqueue them before the first propagation
    for (cidx, clause) in enumerate(solver.clauses)
        if length(clause) == 1
            lit = clause[1]
            if lit_value(solver, lit) == Int8(-1)
                return nothing  # conflicting unit clauses
            end
            if lit_value(solver, lit) == Int8(0)
                enqueue!(solver, lit, cidx)
            end
        end
    end

    # Initial BCP
    if propagate!(solver) != 0
        return nothing  # UNSAT at root
    end

    # Restart parameters
    restart_base = 100
    restart_count = 1
    conflicts_until_restart = restart_base

    # Main CDCL loop
    while true
        conflict = propagate!(solver)

        if conflict != 0
            solver.num_conflicts += 1

            # Conflict at decision level 0 → UNSAT
            if current_level(solver) == 0
                return nothing
            end

            # 1-UIP conflict analysis
            learned_clause, bt_level = analyze(solver, conflict)

            # Non-chronological backjump
            backtrack!(solver, bt_level)

            # Add learned clause
            if length(learned_clause) == 1
                # Unit learned clause: just enqueue
                enqueue!(solver, learned_clause[1], 0)
            else
                cidx = add_clause!(solver, learned_clause, false)
                enqueue!(solver, learned_clause[1], cidx)
            end

            # Restart check
            conflicts_until_restart -= 1
            if conflicts_until_restart <= 0
                restart_count += 1
                conflicts_until_restart = round(Int, luby(2.0, restart_count) * restart_base)
                backtrack!(solver, 0)
            end
        else
            # No conflict – pick a new decision variable
            var = pick_branching_var(solver)
            if var === nothing
                # All variables assigned → SAT
                result = Dict{Int, Bool}()
                for v in 1:solver.num_vars
                    result[v] = solver.values[v] == Int8(1)
                end
                return result
            end

            solver.num_decisions += 1
            new_decision_level!(solver)
            # Use phase-saving for polarity
            lit = solver.polarity[var] ? var : -var
            enqueue!(solver, lit, 0)
        end
    end
end
