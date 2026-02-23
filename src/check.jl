include("sat_instance.jl")
include("dimacs_parser.jl")

import Pkg
Pkg.add("JSON")

using JSON
using .DimacsParser

"""
    parse_solution(solution_str::String) -> Dict{Int, Bool}

Parse a solution string of the form:
"1 true 2 false 3 true ..."
into a dictionary mapping variable → assignment.
"""
function parse_solution(solution_str::String)
    tokens = split(strip(solution_str))
    @assert iseven(length(tokens)) "Malformed solution string"

    assignment = Dict{Int, Bool}()

    for i in 1:2:length(tokens)
        var = parse(Int, tokens[i])
        val = tokens[i + 1] == "true"
        assignment[var] = val
    end

    return assignment
end


"""
    parse_log_file(path::String) -> Dict{String, Dict{Int, Bool}}

Read a log file with one JSON object per line.
Returns a mapping: instance_name → assignment dictionary.
Only SAT instances are included.
"""
function parse_log_file(path::String)
    results = Dict{String, Dict{Int, Bool}}()

    open(path, "r") do io
        for (lineno, line) in enumerate(eachline(io))
            record = ""
            try
                record = JSON.parse(line)
            catch e
                @warn "Skipping invalid JSON" line=lineno error=e
                continue
            end

            if get(record, "Result", "") != "SAT"
                continue
            end

            input_file = "../input/" * record["Instance"]
            solution_str = record["Solution"]

            assignment = parse_solution(solution_str)
            # results[instance] = assignment

            filename = basename(input_file)
            instance = parse_cnf_file(input_file)
            good_instance = true

            for clause in instance.clauses
                valid_clause = false
                for lit in clause
                    var = abs(lit)
            
                    # If variable not assigned, treat as false (or throw if you prefer)
                    val = get(assignment, var, false)
            
                    # Evaluate literal
                    if (lit > 0 && val) || (lit < 0 && !val)
                        valid_clause = true
                        continue
                    end
                end
                if !valid_clause
                    good_instance = false
                    break
                end
            end
            if good_instance
                println("correct solution")
            else
                println(input_file * " has false solution!")
            end 
       end
    end

    return results
end


# -----------------------------
# Example usage
# -----------------------------
if abspath(PROGRAM_FILE) == @__FILE__
    log_path = "../results.log"
    results = parse_log_file(log_path)

    println("Parsed $(length(results)) SAT instances")

    # Example access
    for (instance, assignment) in first(results, 1)
        println("Instance: $instance")
        println("Variable 1 = ", assignment[1])
    end
end
