using Test
using TopAI09

@testset "Chao format and source mapping" begin
    root = joinpath(@__DIR__, "..", "data", "benchmarks", "chao")
    instance = read_chao_instance(joinpath(root, "p2.2.a.txt"))
    @test instance.name == "p2.2.a"
    @test length(clients(instance)) == 19
    @test instance.m == 2
    @test instance.limit == 7.5
    @test instance.start == 1 && instance.finish == 21
    @test instance.ids[2] == "client-0"
    @test instance.ids[end-1] == "client-18"
    @test instance.profits[[1,2,end]] == [0,20,0]
    @test instance.coordinates[1,:] == [4.6,7.1]
    @test instance.costs[1,2] == hypot(4.6-5.7, 7.1-11.4)
    @test instance.costs[1,2] != round(instance.costs[1,2]; digits=2)
    @test validate_solution(instance, TOPSolution()).valid
    for filename in filter(name -> endswith(name, ".txt"), readdir(root))
        item = read_chao_instance(joinpath(root, filename))
        @test item.start != item.finish
        @test item.costs == transpose(item.costs)
        @test item.profits[item.start] == item.profits[item.finish] == 0
    end
    mktempdir() do directory
        path = joinpath(directory, "instance.txt")
        valid = "n;4\nm;1\ntmax;4\n0;0;0\n1;0;3\n2;0;5\n0;0;0\n"
        write(path, valid)
        same_place = read_chao_instance(path; name="same place")
        @test same_place.name == "same place"
        @test same_place.start != same_place.finish
        @test same_place.coordinates[1,:] == same_place.coordinates[end,:]
        @test validate_solution(same_place, TOPSolution([[2,3]])).valid
        for broken in ("", replace(valid, "n;4"=>"n;3"), replace(valid, "n;4"=>"n;4.5"),
                       replace(valid, "m;1"=>"vehicles;1"), replace(valid, "m;1"=>"m;-1"),
                       replace(valid, "tmax;4"=>"tmax;NaN"), replace(valid, "1;0;3"=>"1;;3"),
                       replace(valid, "1;0;3"=>"1;0;-3"), replace(valid, "1;0;3"=>"1;0;3;0"),
                       replace(valid, "0;0;0\n1"=>"0;0;2\n1"), valid * "0;0;0\n")
            write(path, broken)
            @test_throws ArgumentError read_chao_instance(path)
        end
    end
end
