include("sat_instance.jl")

module DimacsParser

using ..Main: SATInstance, add_variable!, add_clause!

export parse_cnf_file

function parse_cnf_file(filename::String)::Union{SATInstance, Nothing}
    sat_instance = nothing
    
    try
        lines = readlines(filename)
        
        iterator = Iterators.Stateful(lines)
        line = nothing
        tokens = nothing
        
        # Skip comments
        while true
            if isempty(iterator)
                break
            end
            
            line = strip(popfirst!(iterator))
            if isempty(line)
                continue
            end
            
            tokens = split(line)
            if tokens[1] != "c"
                break
            end
        end
        
        # Parse problem line
        if isnothing(tokens) || isempty(tokens) || tokens[1] != "p"
            error("Error: DIMACS file does not have problem line")
        end
        
        if tokens[2] != "cnf"
            println("Error: DIMACS file format is not cnf")
            return nothing
        end
        
        num_vars = parse(Int, tokens[3])
        num_clauses = parse(Int, tokens[4])
        sat_instance = SATInstance(num_vars, num_clauses)
        
        # Parse clauses from the rest of the file
        clause_lines = collect(iterator)
        
        function token_generator()
            Channel() do channel
                for l in clause_lines
                    l = strip(l)
                    if isempty(l)
                        continue
                    end
                    if startswith(l, "c")
                        continue
                    end
                    for t in split(l)
                        put!(channel, t)
                    end
                end
            end
        end
        
        current_clause = Set{Int}()
        for token in token_generator()
            if token == "0"
                # End of clause
                if !isempty(current_clause)
                    add_clause!(sat_instance, current_clause)
                end
                current_clause = Set{Int}()
            elseif token == "%"
                # End of file marker
                break
            else
                literal = parse(Int, token)
                push!(current_clause, literal)
                add_variable!(sat_instance, literal)
            end
        end
        
        return sat_instance
        
    catch e
        if isa(e, SystemError) && e.errnum == 2  # File not found
            error("Error: DIMACS file is not found $filename")
        else
            rethrow(e)
        end
    end
end

end  # module