using Test
using TopAI09

@testset "TOP infrastructure" begin
    instance = read_instance(joinpath(@__DIR__, "..", "data", "toy", "directed.toml"))
    @test clients(instance) == [2, 3, 4]
    @test instance.ids[2] == "A"
    @test route_duration(instance, [2, 3, 4]) == 6.0
    @test route_duration(instance, [4, 3, 2]) == 14.0
    @test route_duration(instance, Int[]) == 0.0
    solution = TOPSolution([[2, 3, 4]]; claimed_profit=19)
    report = validate_solution(instance, solution)
    @test report.valid
    @test report.profit == solution_profit(instance, solution) == 19.0
    @test report.durations == solution_durations(instance, solution) == [6.0]
    @test total_duration(instance, solution) == 6.0
    @test isempty(unvisited_clients(instance, solution))
    @test unvisited_clients(instance, TOPSolution([[3]])) == [2, 4]
    @test validate_solution(instance, TOPSolution()).valid
    @test validate_solution(instance, TOPSolution([[2], [3, 4]])).valid
    @test !validate_solution(instance, TOPSolution([[2], [3], [4]])).valid
    @test !validate_solution(instance, TOPSolution([[2, 2]])).valid
    @test !validate_solution(instance, TOPSolution([[2], [2]])).valid
    @test !validate_solution(instance, TOPSolution([[1, 2]])).valid
    @test !validate_solution(instance, TOPSolution([[2, 5]])).valid
    @test !validate_solution(instance, TOPSolution([[999]])).valid
    @test !validate_solution(instance, TOPSolution([Int[]])).valid
    @test !validate_solution(instance, TOPSolution([[4, 3, 2]])).valid
    @test !validate_solution(instance, TOPSolution([[2]]; claimed_profit=6)).valid
    @test !validate_solution(instance, TOPSolution([[2]]; claimed_profit=NaN)).valid
    @test_throws ArgumentError validate_solution(instance, solution; tolerance=-1)
    for route in [Int[], [2], [2, 4]], client in setdiff(clients(instance), route), position in 1:(length(route) + 1)
        extended = copy(route)
        insert!(extended, position, client)
        @test insertion_delta(instance, route, client, position) ≈ route_duration(instance, extended) - route_duration(instance, route)
    end
    @test_throws BoundsError insertion_delta(instance, [2], 3, 3)
    geometric = read_instance(joinpath(@__DIR__, "..", "data", "toy", "coordinates.toml"))
    @test geometric.start != geometric.finish
    @test geometric.coordinates[1, :] == geometric.coordinates[end, :]
    @test validate_solution(geometric, TOPSolution([[2, 3]])).valid # exactly L
    @test route_duration(geometric, [2, 3]) == geometric.limit == 4.0
    @test_throws ArgumentError TOPInstance("bad", [0, 1, 0], zeros(2, 2), 1, 2)
    @test_throws ArgumentError TOPInstance("bad", [0, -1, 0], zeros(3, 3), 1, 2)
    @test_throws ArgumentError TOPInstance("bad", [1, 1, 0], zeros(3, 3), 1, 2)
    @test_throws ArgumentError TOPInstance("bad", [0, 1, 0], fill(Inf, 3, 3), 1, 2)
    @test_throws ArgumentError TOPInstance("bad", [0, 1, 0], zeros(3, 3), 1, 2; start=1, finish=1)
    @test_throws ArgumentError TOPInstance("bad", [0, 1, 0], zeros(3, 3), -1, 2)
    @test_throws ArgumentError TOPInstance("bad", [0, 1, 0], zeros(3, 3), 1, -1)
    nofleet = TOPInstance("no-fleet", [0, 1, 0], zeros(3, 3), 0, 0)
    @test validate_solution(nofleet, TOPSolution()).valid
    @test !validate_solution(nofleet, TOPSolution([[2]])).valid
end

include("exact_tests.jl")
include("chao_tests.jl")
include("algorithms_tests.jl")
