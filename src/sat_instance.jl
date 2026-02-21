mutable struct SATInstance
    numVars::Int
    numClauses::Int
    clauses::Vector{Vector{Int}}
    
    function SATInstance(numVars::Int, numClauses::Int, 
                         clauses::Vector{Vector{Int}}=Vector{Int}[])
        new(numVars, numClauses, clauses)
    end
end

function add_clause!(instance::SATInstance, clause::Vector{Int})
    push!(instance.clauses, clause)
end

function Base.show(io::IO, instance::SATInstance)
    println(io, "Number of variables: $(instance.numVars)")
    println(io, "Number of clauses: $(instance.numClauses)")
end
