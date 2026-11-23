using Random

"""
    giant_tour(instance, rng; rcl=1) -> Vector{Int}

Route-first step: one sequence visiting *every* positive-profit client, with
`L` and `m` relaxed. It is built by the TSP nearest-neighbour heuristic (PPV),
starting from `d`; with `rcl > 1` the next client is drawn at random among the
`rcl` nearest ones (randomised greedy, as in GRASP), which yields a different
tour at every restart. The open path `d → tour → a` is then improved by 2-opt.
"""
function giant_tour(instance::TOPInstance, rng::AbstractRNG; rcl::Int=1)
    C = instance.costs
    remaining = [j for j in clients(instance) if instance.profits[j] > 0]
    tour = Int[]
    current = instance.start
    while !isempty(remaining)
        order = sortperm(remaining; by=j -> C[current, j])
        pick = order[rand(rng, 1:min(rcl, length(order)))]
        current = remaining[pick]
        push!(tour, current)
        deleteat!(remaining, pick)
    end
    two_opt_path!(instance, tour)
    return tour
end

"""
    two_opt_path!(instance, tour)

TSP 2-opt on the open path `d → tour → a` (both end points fixed), first
improvement, until no crossing improves the length. O(1) gain for symmetric
costs; exact recomputation of the reversed segment otherwise.
"""
function two_opt_path!(instance::TOPInstance, tour::Vector{Int})
    C, n = instance.costs, length(tour)
    sym = C == permutedims(C)
    node(i) = i == 0 ? instance.start : i == n + 1 ? instance.finish : tour[i]
    improved = true
    while improved
        improved = false
        for i in 1:n-1, j in i+1:n
            u, x, y, v = node(i - 1), node(i), node(j), node(j + 1)
            gain = C[u, x] + C[y, v] - C[u, y] - C[x, v]
            if !sym
                for p in i:j-1
                    gain += C[node(p), node(p + 1)] - C[node(p + 1), node(p)]
                end
            end
            if gain > EPS
                reverse!(tour, i, j)
                improved = true
            end
        end
    end
    return tour
end

"""
    split_tour(instance, tour) -> TOPSolution

Cluster-second step: Beasley's optimal split adapted to the TOP.

Auxiliary graph on nodes 0..n (n = length(tour)). For i ≤ j, the arc (i−1, j)
exists if the route `d → tour[i] … tour[j] → a` lasts at most `L`; its value
is the profit of these clients. A skip arc (j−1, j) of value 0 leaves client
`tour[j]` unserved. The best solution is a longest path from 0 to n that uses
at most `m` route arcs:

    F[k, j] = max( F[k, j−1],                                 # skip tour[j]
                   F[k−1, j],                                 # one vehicle unused
                   max_{i ≤ j, arc (i−1,j)} F[k−1, i−1] + P(tour[i..j]) )

computed in O(m · number of arcs) ⊆ O(m n²). Routes are contiguous chunks of
the giant tour; the order inside a chunk is kept.
"""
function split_tour(instance::TOPInstance, tour::Vector{Int})
    C, P, L, m = instance.costs, instance.profits, instance.limit, instance.m
    d, a = instance.start, instance.finish
    n = length(tour)
    # arcs_to[j] = list of (i, profit) with a feasible route tour[i..j]
    arcs_to = [Tuple{Int,Float64}[] for _ in 1:n]
    for i in 1:n
        time, profit = C[d, tour[i]], 0.0
        for j in i:n
            j > i && (time += C[tour[j-1], tour[j]])
            time > L + EPS && break            # costs ≥ 0: longer chunks also fail
            profit += P[tour[j]]
            time + C[tour[j], a] <= L + EPS && push!(arcs_to[j], (i, profit))
        end
    end
    F = zeros(m + 1, n + 1)                    # F[k+1, j+1]
    choice = zeros(Int, m + 1, n + 1)          # 0 skip, -1 unused vehicle, i route start
    for k in 1:m, j in 1:n
        best, arg = F[k+1, j], 0               # skip tour[j]
        F[k, j+1] > best && ((best, arg) = (F[k, j+1], -1))
        for (i, profit) in arcs_to[j]
            value = F[k, i] + profit
            value > best + EPS && ((best, arg) = (value, i))
        end
        F[k+1, j+1], choice[k+1, j+1] = best, arg
    end
    routes = Vector{Int}[]
    k, j = m, n
    while k > 0 && j > 0
        c = choice[k+1, j+1]
        if c == 0
            j -= 1
        elseif c == -1
            k -= 1
        else
            pushfirst!(routes, tour[c:j])
            k, j = k - 1, c - 1
        end
    end
    return TOPSolution(routes)
end

_key(instance, s) = (solution_profit(instance, s), -total_duration(instance, s))

"""
    giant_split(instance; starts=100, rcl=3, seed=42, improve=true, history=false)

Algorithm 2 - multi-start route-first / cluster-second (GRASP scheme).
Each start builds a giant tour (`giant_tour`; the first start is the
deterministic nearest neighbour), splits it optimally (`split_tour`) and, when
`improve=true`, improves the split with the VND of algorithm 1. The best
solution over all starts is returned. With `history=true`, the best profit
after each start is also returned (convergence plots).
"""
function giant_split(instance::TOPInstance; starts::Int=100, rcl::Int=3, seed::Integer=42,
                     improve::Bool=true, history::Bool=false)
    rng = MersenneTwister(seed)
    best = TOPSolution()
    trace = Float64[]
    for s in 1:starts
        candidate = split_tour(instance, giant_tour(instance, rng; rcl=s == 1 ? 1 : rcl))
        improve && (candidate = vnd(instance, candidate))
        _key(instance, candidate) > _key(instance, best) && (best = candidate)
        push!(trace, solution_profit(instance, best))
    end
    return history ? (best, trace) : best
end

