module CDCLBasic

import ..SATInstance

using Random

# ──────────────────────────────────────────────────────────────────────────────
# Literal helpers
# ──────────────────────────────────────────────────────────────────────────────

@inline lit_index(lit::Int)::Int = lit > 0 ? 2 * lit : 2 * (-lit) - 1
@inline lit_var(lit::Int)::Int   = abs(lit)
@inline lit_neg(lit::Int)::Int   = -lit

# ──────────────────────────────────────────────────────────────────────────────
# Watched-literal entry
# ──────────────────────────────────────────────────────────────────────────────

struct Watcher
    clause_idx::Int
    blocker::Int
end

# ──────────────────────────────────────────────────────────────────────────────
# Solver state (no VSIDS, no restarts)
# ──────────────────────────────────────────────────────────────────────────────

mutable struct Solver
    num_vars::Int
    clauses::Vector{Vector{Int}}
    watches::Vector{Vector{Watcher}}

    values::Vector{Int8}
    levels::Vector{Int}
    reasons::Vector{Int}
    polarity::Vector{Bool}
    seen::Vector{Bool}

    trail::Vector{Int}
    trail_lim::Vector{Int}
    qhead::Int

    num_conflicts::Int
    num_decisions::Int
    num_propagations::Int
end

function Solver(instance::SATInstance)
    n = instance.numVars
    watches = [Watcher[] for _ in 1:(2*n)]
    Random.seed!(12345)

    solver = Solver(
        n,
        Vector{Int}[],
        watches,
        zeros(Int8, n), zeros(Int, n), zeros(Int, n),
        fill(true, n), fill(false, n),
        Int[], Int[], 0,
        0, 0, 0
    )

    for clause in instance.clauses
        add_clause!(solver, copy(clause))
    end

    return solver
end

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

@inline function lit_value(s::Solver, lit::Int)::Int8
    @inbounds val = s.values[lit_var(lit)]
    val == 0 ? Int8(0) : (lit > 0 ? val : -val)
end

@inline current_level(s::Solver) = length(s.trail_lim)

function add_clause!(s::Solver, lits::Vector{Int})::Int
    push!(s.clauses, lits)
    cidx = length(s.clauses)
    if length(lits) >= 2
        push!(s.watches[lit_index(lits[1])], Watcher(cidx, lits[2]))
        push!(s.watches[lit_index(lits[2])], Watcher(cidx, lits[1]))
    end
    return cidx
end

function enqueue!(s::Solver, lit::Int, reason::Int)::Bool
    v = lit_var(lit)
    @inbounds begin
        if s.values[v] != 0
            return s.values[v] == (lit > 0 ? Int8(1) : Int8(-1))
        end
        s.values[v]  = lit > 0 ? Int8(1) : Int8(-1)
        s.levels[v]  = current_level(s)
        s.reasons[v] = reason
    end
    push!(s.trail, lit)
    return true
end

function new_decision_level!(s::Solver)
    push!(s.trail_lim, length(s.trail))
end

# ──────────────────────────────────────────────────────────────────────────────
# 2-Watched-Literal BCP
# ──────────────────────────────────────────────────────────────────────────────

function propagate!(s::Solver)::Int
    while s.qhead < length(s.trail)
        s.qhead += 1
        @inbounds p = s.trail[s.qhead]
        s.num_propagations += 1

        false_lit = lit_neg(p)
        fidx = lit_index(false_lit)
        @inbounds ws = s.watches[fidx]
        n_ws = length(ws)
        i = 1; j = 1

        while i <= n_ws
            @inbounds w = ws[i]

            if lit_value(s, w.blocker) == Int8(1)
                @inbounds ws[j] = w; j += 1; i += 1; continue
            end

            @inbounds clause = s.clauses[w.clause_idx]
            clen = length(clause)

            @inbounds if clen >= 2 && clause[1] == false_lit
                clause[1], clause[2] = clause[2], clause[1]
            end

            @inbounds val1 = lit_value(s, clause[1])
            if val1 == Int8(1)
                @inbounds ws[j] = Watcher(w.clause_idx, clause[1])
                j += 1; i += 1; continue
            end

            found_new = false
            @inbounds if clen >= 3
                for k in 3:clen
                    if lit_value(s, clause[k]) != Int8(-1)
                        clause[2], clause[k] = clause[k], clause[2]
                        push!(s.watches[lit_index(clause[2])],
                              Watcher(w.clause_idx, clause[1]))
                        found_new = true
                        break
                    end
                end
            end

            if found_new
                i += 1; continue
            end

            if val1 == Int8(-1)
                @inbounds ws[j] = w; j += 1; i += 1
                @inbounds while i <= n_ws; ws[j] = ws[i]; j += 1; i += 1; end
                resize!(ws, j - 1)
                return w.clause_idx
            end

            @inbounds ws[j] = Watcher(w.clause_idx, clause[1]); j += 1
            @inbounds if !enqueue!(s, clause[1], w.clause_idx)
                i += 1
                while i <= n_ws; ws[j] = ws[i]; j += 1; i += 1; end
                resize!(ws, j - 1)
                return w.clause_idx
            end
            i += 1
        end

        resize!(ws, j - 1)
    end
    return 0
end

# ──────────────────────────────────────────────────────────────────────────────
# 1-UIP conflict analysis (no VSIDS bumping)
# ──────────────────────────────────────────────────────────────────────────────

function analyze(s::Solver, conflict::Int)::Tuple{Vector{Int}, Int}
    learned = Int[]
    trail_idx = length(s.trail)
    counter = 0
    p = 0
    reason = conflict
    cl = current_level(s)

    fill!(s.seen, false)

    while true
        @inbounds clause = s.clauses[reason]
        for lit in clause
            v = lit_var(lit)
            if v == lit_var(p) && p != 0; continue; end
            @inbounds if s.seen[v]; continue; end
            @inbounds s.seen[v] = true

            @inbounds if s.levels[v] == cl
                counter += 1
            else
                push!(learned, lit)
            end
        end

        @inbounds while true
            p = s.trail[trail_idx]
            trail_idx -= 1
            if s.seen[lit_var(p)]; break; end
        end
        counter -= 1
        if counter == 0; break; end
        @inbounds reason = s.reasons[lit_var(p)]
    end

    pushfirst!(learned, lit_neg(p))

    bt_level = 0
    if length(learned) > 1
        @inbounds begin
            max_idx = 2
            max_lvl = s.levels[lit_var(learned[2])]
            for i in 3:length(learned)
                lvl = s.levels[lit_var(learned[i])]
                if lvl > max_lvl
                    max_lvl = lvl
                    max_idx = i
                end
            end
            learned[2], learned[max_idx] = learned[max_idx], learned[2]
        end
        bt_level = max_lvl
    end

    return (learned, bt_level)
end

# ──────────────────────────────────────────────────────────────────────────────
# Backtrack to a given decision level
# ──────────────────────────────────────────────────────────────────────────────

function backtrack!(s::Solver, level::Int)
    if current_level(s) <= level; return; end
    @inbounds target = s.trail_lim[level + 1]
    while length(s.trail) > target
        lit = pop!(s.trail)
        v = lit_var(lit)
        @inbounds begin
            s.polarity[v] = lit > 0
            s.values[v]   = Int8(0)
            s.reasons[v]  = 0
        end
    end
    s.qhead = length(s.trail)
    resize!(s.trail_lim, level)
end

# ──────────────────────────────────────────────────────────────────────────────
# Branching: first unassigned variable (no VSIDS)
# ──────────────────────────────────────────────────────────────────────────────

function pick_branching_var(s::Solver)::Union{Int, Nothing}
    for v in 1:s.num_vars
        @inbounds if s.values[v] == Int8(0)
            return v
        end
    end
    return nothing
end

# ──────────────────────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────────────────────

function cdcl_solve(instance::SATInstance)::Union{Dict{Int, Bool}, Nothing}
    if instance === nothing; return nothing; end

    for clause in instance.clauses
        if isempty(clause); return nothing; end
    end

    solver = Solver(instance)

    for (cidx, clause) in enumerate(solver.clauses)
        if length(clause) == 1
            lit = clause[1]
            if lit_value(solver, lit) == Int8(-1); return nothing; end
            if lit_value(solver, lit) == Int8(0)
                enqueue!(solver, lit, cidx)
            end
        end
    end

    if propagate!(solver) != 0; return nothing; end

    while true
        conflict = propagate!(solver)

        if conflict != 0
            solver.num_conflicts += 1
            if current_level(solver) == 0; return nothing; end

            learned_clause, bt_level = analyze(solver, conflict)
            backtrack!(solver, bt_level)

            if length(learned_clause) == 1
                enqueue!(solver, learned_clause[1], 0)
            else
                cidx = add_clause!(solver, learned_clause)
                enqueue!(solver, learned_clause[1], cidx)
            end
        else
            var = pick_branching_var(solver)
            if var === nothing
                result = Dict{Int, Bool}()
                for v in 1:solver.num_vars
                    result[v] = solver.values[v] == Int8(1)
                end
                return result
            end

            solver.num_decisions += 1
            new_decision_level!(solver)
            lit = solver.polarity[var] ? var : -var
            enqueue!(solver, lit, 0)
        end
    end
end

end # module CDCLBasic
