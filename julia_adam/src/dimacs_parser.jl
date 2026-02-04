include("sat_instance.jl")

module DimacsParser
    # Import SATInstance and its functions from parent scope
    import ..SATInstance
    import ..add_variable
    import ..add_clause

    function parse_cnf_file(filename::String)::Union{SATInstance, Nothing}
        try
            lines = readlines(filename)
            
            line_idx = 1
            tokens = nothing
            
            # Skip comments
            while line_idx <= length(lines)
                line = strip(lines[line_idx])
                if !isempty(line)
                    tokens = split(line)
                    if !isempty(tokens) && tokens[1] != "c"
                        break
                    end
                end
                line_idx += 1
            end
            
            # Parse problem line
            if tokens === nothing || isempty(tokens) || tokens[1] != "p"
                throw(ArgumentError("Error: DIMACS file does not have problem line"))
            end
            
            if length(tokens) < 4 || tokens[2] != "cnf"
                println("Error: DIMACS file format is not cnf")
                return nothing
            end
            
            num_vars = parse(Int, tokens[3])
            num_clauses = parse(Int, tokens[4])
            sat_instance = SATInstance(num_vars, num_clauses)
            
            # Parse clauses from the rest of the file
            clause_lines = lines[line_idx+1:end]
            
            current_clause = Set{Int}()
            for l in clause_lines
                l = strip(l)
                if isempty(l)
                    continue
                end
                if startswith(l, "c")
                    continue
                end
                
                for t in split(l)
                    if t == "0"
                        # End of clause
                        if !isempty(current_clause)  # Avoid empty clauses if 0 is standalone or repeated
                            add_clause(sat_instance, current_clause)
                        end
                        current_clause = Set{Int}()
                    elseif t == "%"
                        # End of file marker
                        return sat_instance
                    else
                        literal = parse(Int, t)
                        push!(current_clause, literal)
                        add_variable(sat_instance, literal)
                    end
                end
            end
            
            return sat_instance
            
        catch e
            if isa(e, SystemError) || isa(e, IOError)
                error("Error: DIMACS file is not found $filename")
            else
                rethrow(e)
            end
        end
    end
end
