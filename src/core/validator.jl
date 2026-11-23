struct ValidationReport
    valid::Bool
    errors::Vector{String}
    profit::Float64
    durations::Vector{Float64}
end

"Recompute feasibility and objective from node sequences, independently of algorithm caches."
function validate_solution(instance::TOPInstance, solution::TOPSolution; tolerance::Real=1e-9)
    isfinite(tolerance) && tolerance >= 0 || throw(ArgumentError("tolerance must be finite and nonnegative"))
    errors = String[]
    length(solution.routes) <= instance.m || push!(errors, "too many active vehicles")
    allowed = Set(clients(instance))
    visited = Set{Int}()
    profit = 0.0
    durations = Float64[]
    for (k, route) in enumerate(solution.routes)
        isempty(route) && push!(errors, "route $k is empty; omit unused vehicles")
        indices_valid = true
        for client in route
            if !(client in allowed)
                push!(errors, "route $k contains non-client node $client")
                indices_valid = false
            elseif client in visited
                push!(errors, "client $client is visited more than once")
            else
                push!(visited, client)
                profit += instance.profits[client]
            end
        end
        # Deliberately sum arcs here, without calling the cached evaluator.
        if indices_valid && !isempty(route)
            duration = instance.costs[instance.start, route[1]]
            for j in 2:length(route)
                duration += instance.costs[route[j - 1], route[j]]
            end
            duration += instance.costs[route[end], instance.finish]
            push!(durations, duration)
            duration <= instance.limit + tolerance || push!(errors, "route $k exceeds duration limit")
        elseif isempty(route)
            push!(durations, 0.0)
        else
            push!(durations, NaN)
        end
    end
    if !isnothing(solution.claimed_profit)
        isfinite(solution.claimed_profit) && abs(solution.claimed_profit - profit) <= tolerance ||
            push!(errors, "claimed profit differs from recomputed profit")
    end
    ValidationReport(isempty(errors), errors, profit, durations)
end
