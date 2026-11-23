const EPS = 1e-9

"""
    best_insertion(instance; rng=nothing, rcl=1) -> TOPSolution

Algorithm 1, phase 1: TSP "meilleure insertion" adapted to the TOP.

At each step, every free client `j` with positive profit is tried at every
position of every route, and as the first client of a new route while fewer
than `m` routes are open (parallel VRP construction). A placement is feasible
only if the route still respects `L`. The placement with the best ratio
`P_j / ΔC` is applied, where `ΔC = C_ij + C_jk - C_ik` is the TSP insertion
cost. Placements with `ΔC ≤ 0` (possible without triangle inequality) come
first. The loop stops when no feasible placement remains: the clients still
free at that point are not served.

With `rng` and `rcl > 1`, the applied placement is drawn among the `rcl` best
clients (randomised greedy); this is only used by the control experiment.
"""
function best_insertion(instance::TOPInstance; rng=nothing, rcl::Int=1)
    routes = Vector{Vector{Int}}()
    durations = Float64[]
    free = Set(j for j in clients(instance) if instance.profits[j] > 0)
    d, a, C, L = instance.start, instance.finish, instance.costs, instance.limit
    while true
        # best placement of each client, then the best client (or a random
        # one among the `rcl` best clients)
        candidates = Tuple{Tuple{Float64,Float64,Float64},NamedTuple}[]
        for j in sort!(collect(free))
            P = instance.profits[j]
            local bestkey = (-Inf, -Inf, -Inf)
            local placement = nothing
            consider(r, pos, δ) = begin
                # Larger key is better: ratio, then profit, then smaller ΔC.
                key = (δ <= EPS ? Inf : P / δ, P, -δ)
                if key > bestkey
                    bestkey = key
                    placement = (client=j, route=r, position=pos, delta=δ)
                end
            end
            for r in eachindex(routes), pos in 1:length(routes[r])+1
                δ = insertion_delta(instance, routes[r], j, pos)
                durations[r] + δ <= L + EPS && consider(r, pos, δ)
            end
            if length(routes) < instance.m
                δ = C[d, j] + C[j, a]
                δ <= L + EPS && consider(length(routes) + 1, 1, δ)
            end
            isnothing(placement) || push!(candidates, (bestkey, placement))
        end
        isempty(candidates) && break
        sort!(candidates; by=first, rev=true)
        pick = isnothing(rng) || rcl == 1 ? 1 : rand(rng, 1:min(rcl, length(candidates)))
        best = candidates[pick][2]
        if best.route > length(routes)
            push!(routes, [best.client])
            push!(durations, best.delta)
        else
            insert!(routes[best.route], best.position, best.client)
            durations[best.route] += best.delta
        end
        delete!(free, best.client)
    end
    return TOPSolution(routes)
end

"""
    insertion_vnd(instance) -> TOPSolution

Algorithm 1 - best insertion followed by the VND.
"""
insertion_vnd(instance::TOPInstance) = vnd(instance, best_insertion(instance))

"""
    insertion_multistart(instance; starts=100, rcl=3, seed=42, history=false)

Control experiment, not one of the two algorithms: same GRASP scheme as
algorithm 2, but each start is a randomised best insertion + VND instead of a
giant tour + split. It shows what the giant tour and the split add over plain restarts.
"""
function insertion_multistart(instance::TOPInstance; starts::Int=100, rcl::Int=3,
                              seed::Integer=42, history::Bool=false)
    rng = MersenneTwister(seed)
    best, trace = TOPSolution(), Float64[]
    for s in 1:starts
        candidate = vnd(instance, best_insertion(instance; rng=rng, rcl=s == 1 ? 1 : rcl))
        key(x) = (solution_profit(instance, x), -total_duration(instance, x))
        key(candidate) > key(best) && (best = candidate)
        push!(trace, solution_profit(instance, best))
    end
    return history ? (best, trace) : best
end
