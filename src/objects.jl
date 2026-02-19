mutable struct Node
    id_to_clause::Dict{Int, Set{Int}}
    var_to_clause_ids::Dict{Int, Set{Int}}
    sat_vars_to_assignment::Dict{Int, Bool}
    unit_clauses::Set{Int}
    pure_vars::Set{Int}
    
    function Node(id_to_clause::Dict{Int, Set{Int}}, 
                  var_to_clause_ids::Dict{Int, Set{Int}},
                  sat_vars_to_assignment::Dict{Int, Bool},
                  unit_clauses::Set{Int},
                  pure_vars::Set{Int})
        new(id_to_clause, var_to_clause_ids, sat_vars_to_assignment, 
            unit_clauses, pure_vars)
    end
end