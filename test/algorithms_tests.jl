using Test
using Random
using TopAI09

# Brute force over every way to cut a fixed tour into <= m contiguous chunks,
# each chunk being served or skipped (the split's search space).
function brute_split(instance, tour)
    n, best = length(tour), 0.0
    function go(i, k, value)
        best = max(best, value)
        (i > n || k == 0) && return
        go(i + 1, k, value)                          # skip tour[i]
        for j in i:n
            route = tour[i:j]
            route_duration(instance, route) <= instance.limit + 1e-9 || continue
            go(j + 1, k - 1, value + sum(instance.profits[route]))
        end
    end
    go(1, instance.m, 0.0)
    best
end

function random_instance(rng, n, m, L)
    xy = rand(rng, 0:20, n + 2, 2) .* 1.0
    profits = [0.0; rand(rng, 1:10, n) .* 1.0; 0.0]
    C = [hypot(xy[i, 1] - xy[j, 1], xy[i, 2] - xy[j, 2]) for i in 1:n+2, j in 1:n+2]
    TOPInstance("random", profits, C, m, L)
end

@testset "Split is optimal for a fixed giant tour" begin
    rng = MersenneTwister(7)
    for trial in 1:40
        instance = random_instance(rng, rand(rng, 3:8), rand(rng, 1:3), 25.0 + 15rand(rng))
        tour = shuffle(rng, clients(instance))
        s = split_tour(instance, tour)
        @test validate_solution(instance, s).valid
        @test solution_profit(instance, s) ≈ brute_split(instance, tour)
        # every route is a contiguous chunk of the tour, in tour order
        positions = Dict(c => p for (p, c) in enumerate(tour))
        for r in s.routes
            @test [positions[c] for c in r] == collect(positions[r[1]]:positions[r[1]]+length(r)-1)
        end
    end
end

@testset "Both algorithms: feasible, monotone, bounded by the MILP optimum" begin
    rng = MersenneTwister(11)
    for trial in 1:12
        instance = random_instance(rng, 7, rand(rng, 1:3), 30.0 + 10rand(rng))
        optimum = exact_solve(instance; time_limit=30.0).profit
        c = best_insertion(instance)
        a1 = insertion_vnd(instance)
        a2 = giant_split(instance; starts=20, seed=trial)
        ctrl = insertion_multistart(instance; starts=20, seed=trial)
        for s in (c, a1, a2, ctrl)
            @test validate_solution(instance, s).valid
            @test solution_profit(instance, s) <= optimum + 1e-9
        end
        @test solution_profit(instance, a1) >= solution_profit(instance, c)
    end
end

@testset "VND never degrades and handles directed costs" begin
    instance = read_instance(joinpath(@__DIR__, "..", "data", "toy", "directed.toml"))
    for start in (TOPSolution(), TOPSolution([[4, 3, 2]][1:0]), best_insertion(instance))
        improved = vnd(instance, start)
        @test validate_solution(instance, improved).valid
        @test solution_profit(instance, improved) >= solution_profit(instance, start)
    end
    # 2-opt on an open path with asymmetric costs must use exact lengths.
    tour = [4, 3, 2]
    two_opt_path!(instance, tour)
    path(t) = route_duration(instance, t)
    @test path(tour) <= path([4, 3, 2])
end
