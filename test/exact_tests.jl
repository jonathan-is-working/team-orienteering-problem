using Test
using Random

# Independent oracle: enumerate every ordered nonempty client subset, including
# prefixes that cannot yet reach the arrival depot (nonmetric costs).
function exhaustive_top_profit(instance)
    N = collect(clients(instance))
    options = Tuple{Set{Int},Float64}[]
    function visit(prefix, remaining)
        if !isempty(prefix) && route_duration(instance, prefix) <= instance.limit + 1e-9
            push!(options, (Set(prefix), sum(instance.profits[i] for i in prefix)))
        end
        for i in remaining
            visit(vcat(prefix, i), filter(!=(i), remaining))
        end
    end
    visit(Int[], N)
    function pack(used, remaining_vehicles)
        remaining_vehicles == 0 && return 0.0
        best = 0.0
        for (selected, profit) in options
            isempty(intersect(used, selected)) || continue
            best = max(best, profit + pack(union(used, selected), remaining_vehicles - 1))
        end
        return best
    end
    pack(Set{Int}(), instance.m)
end

@testset "Flow MILP exact solver" begin
    # Only one client fits in each route, and some vehicles may stay unused.
    costs = fill(9.0, 5, 5)
    for i in 1:5
        costs[i, i] = 0.0
    end
    for i in 2:4
        costs[1, i] = costs[i, 5] = 1.0
    end
    for m in (0, 1, 2, 4)
        instance = TOPInstance("separate routes", [0, 3, 8, 5, 0], costs, m, 2.0)
        result = exact_solve(instance)
        @test result.optimal
        @test result.status == "OPTIMAL"
        @test result.solution !== nothing
        @test validate_solution(instance, result.solution).valid
        @test result.profit ≈ exhaustive_top_profit(instance)
        @test result.upper_bound ≈ result.profit
        @test result.relative_gap ≈ 0.0 atol=1e-8
    end

    # Degree constraints alone could append the profitable 3<->4 cycle to
    # the cheap route 1->2->5. The auxiliary flow must exclude that cycle.
    cycle_costs = fill(100.0, 5, 5)
    cycle_costs[1, 2] = cycle_costs[2, 5] = 1.0
    cycle_costs[3, 4] = cycle_costs[4, 3] = 0.0
    instance = TOPInstance("disconnected cycle", [0, 1, 50, 50, 0], cycle_costs, 1, 2.0)
    result = exact_solve(instance)
    @test result.optimal
    @test result.profit == 1.0
    @test result.solution.routes == [[2]]

    # No client is accessible alone, yet the sequence 2->3 is feasible.
    nonmetric = [0.0 1 9 9; 9 0 1 9; 9 9 0 1; 9 9 9 0]
    instance = TOPInstance("nonmetric", [0, 4, 7, 0], nonmetric, 1, 3.0)
    result = exact_solve(instance)
    @test result.optimal
    @test result.profit == 11.0
    @test result.solution.routes == [[2, 3]]

    rng = MersenneTwister(54)
    for trial in 1:4
        matrix = Float64.(rand(rng, 0:9, 6, 6))
        profits = vcat(0.0, Float64.(rand(rng, 0:10, 4)), 0.0)
        instance = TOPInstance("directed $trial", profits, matrix, 2, 9.0)
        result = exact_solve(instance)
        @test result.optimal
        @test result.profit ≈ exhaustive_top_profit(instance)
        @test validate_solution(instance, result.solution).valid
    end

    empty_instance = TOPInstance("empty", [0, 0], zeros(2, 2), 2, 0.0)
    result = exact_solve(empty_instance)
    @test result.optimal
    @test result.profit == 0.0
    @test isempty(result.solution.routes)
    @test_throws ArgumentError exact_solve(empty_instance; time_limit=0.0)
    @test_throws ArgumentError exact_solve(empty_instance; threads=0)

    # A run stopped before finding any solution reports no solution and no optimum.
    limited = TOPInstance("time limited", vcat(0.0, ones(16), 0.0),
        Float64.(rand(MersenneTwister(2), 1:100, 18, 18)), 3, 160.0)
    interrupted = exact_solve(limited; time_limit=1e-9)
    @test interrupted.status == "TIME_LIMIT"
    @test !interrupted.optimal
    @test interrupted.solution === nothing
    @test interrupted.profit === nothing
end
