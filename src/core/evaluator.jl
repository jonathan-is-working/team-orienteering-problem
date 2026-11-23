"Return directed travel time including the two depot connections. An unused route costs zero."
function route_duration(instance::TOPInstance, route::AbstractVector{<:Integer})
    isempty(route) && return 0.0
    duration = instance.costs[instance.start, first(route)]
    for position in 1:(length(route) - 1)
        duration += instance.costs[route[position], route[position + 1]]
    end
    duration + instance.costs[last(route), instance.finish]
end

solution_profit(instance::TOPInstance, solution::TOPSolution) =
    sum((instance.profits[i] for route in solution.routes for i in route); init=0.0)
solution_durations(instance::TOPInstance, solution::TOPSolution) =
    [route_duration(instance, route) for route in solution.routes]
total_duration(instance::TOPInstance, solution::TOPSolution) = sum(solution_durations(instance, solution); init=0.0)
unvisited_clients(instance::TOPInstance, solution::TOPSolution) =
    sort!(collect(setdiff(Set(clients(instance)), Set(i for route in solution.routes for i in route))))

"Full opening cost for an empty route; otherwise the three-arc insertion difference."
function insertion_delta(instance::TOPInstance, route::AbstractVector{<:Integer}, client::Integer, position::Integer)
    1 <= position <= length(route) + 1 || throw(BoundsError(route, position))
    isempty(route) && return instance.costs[instance.start, client] + instance.costs[client, instance.finish]
    before = position == 1 ? instance.start : route[position - 1]
    after = position == length(route) + 1 ? instance.finish : route[position]
    instance.costs[before, client] + instance.costs[client, after] - instance.costs[before, after]
end
