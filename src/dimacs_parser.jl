include("sat_instance.jl")

module DimacsParser

using ..Main: SATInstance, add_clause!

export parse_cnf_file

function parse_cnf_file(filename::String)::Union{SATInstance, Nothing}
    sat_instance = nothing
    
    try
        open(filename, "r") do io
            num_vars = 0
            num_clauses = 0

            for line in eachline(io)
                line = strip(line)
                if isempty(line) || line[1] == 'c'
                    continue
                end
                if line[1] == 'p'
                    tokens = split(line)
                    if tokens[2] != "cnf"
                        println("Error: DIMACS file format is not cnf")
                        return nothing
                    end
                    num_vars = parse(Int, tokens[3])
                    num_clauses = parse(Int, tokens[4])
                    sat_instance = SATInstance(num_vars, num_clauses)
                    break
                end
            end

            if isnothing(sat_instance)
                error("Error: DIMACS file does not have problem line")
            end

            current_clause = Int[]
            for line in eachline(io)
                line = strip(line)
                if isempty(line) || line[1] == 'c'
                    continue
                end
                if line[1] == '%'
                    break
                end
                for t in split(line)
                    lit = parse(Int, t)
                    if lit == 0
                        if !isempty(current_clause)
                            add_clause!(sat_instance, current_clause)
                            current_clause = Int[]
                        end
                    else
                        push!(current_clause, lit)
                    end
                end
            end
            if !isempty(current_clause)
                add_clause!(sat_instance, current_clause)
            end
        end
        
        return sat_instance
        
    catch e
        if isa(e, SystemError) && e.errnum == 2
            error("Error: DIMACS file is not found $filename")
        else
            rethrow(e)
        end
    end
end

end  # module
