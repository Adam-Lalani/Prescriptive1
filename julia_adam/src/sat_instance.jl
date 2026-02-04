mutable struct SATInstance
    numVars::Int
    numClauses::Int
    vars::Set{Int}
    clauses::Vector{Set{Int}}
    
    function SATInstance(numVars::Int, numClauses::Int)
        new(numVars, numClauses, Set{Int}(), Vector{Set{Int}}())
    end
end

function add_variable(instance::SATInstance, literal::Int)
    push!(instance.vars, abs(literal))
end

function add_clause(instance::SATInstance, clause::Set{Int})
    push!(instance.clauses, clause)
end

function Base.show(io::IO, instance::SATInstance)
    println(io, "Number of variables: $(instance.numVars)")
    println(io, "Number of clauses: $(instance.numClauses)")
    println(io, "Variables: $(instance.vars)")
    for (i, clause) in enumerate(instance.clauses)
        println(io, "Clause $(i-1): $clause")
    end
end
