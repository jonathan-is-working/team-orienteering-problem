# Solve one Chao instance and print the tours found by each method.
#   julia --project=. scripts/solve.jl p4.2.j [all|algo1|algo2|milp] [MILP_TIME_LIMIT]
using TopAI09
using Printf

const CHAO = joinpath(@__DIR__, "..", "data", "benchmarks", "chao")

function read_bks(name)
    for line in readlines(joinpath(CHAO, "bks.csv"))[2:end]
        key, value = split(line, ',')
        key == name && return parse(Float64, value)
    end
    return NaN
end

# Clients are numbered 1..n as in the instance file (Julia index 2 is client 1).
route_text(route) = join(["d"; string.(route .- 1); "a"], " → ")

function report(instance, label, solution, seconds, bks; note="")
    check = validate_solution(instance, solution)
    check.valid || error("$label returned an invalid solution: $(check.errors)")
    gap = bks > 0 ? @sprintf("%.2f %%", 100 * (bks - check.profit) / bks) : "--"
    @printf("\n%s%s\n  profit %g   écart à la BKS %s   temps %.3f s\n", label, note, check.profit, gap, seconds)
    for (k, route) in enumerate(solution.routes)
        @printf("  véhicule %d (durée %.1f / %.1f) : %s\n", k, check.durations[k], instance.limit, route_text(route))
    end
    isempty(solution.routes) && println("  aucune tournée")
end

function main(args)
    isempty(args) && error("usage: julia --project=. scripts/solve.jl INSTANCE [all|algo1|algo2|milp] [MILP_TIME_LIMIT]")
    name = replace(args[1], ".txt" => "")
    method = length(args) >= 2 ? lowercase(args[2]) : "all"
    limit = length(args) >= 3 ? parse(Float64, args[3]) : 60.0
    method in ("all", "algo1", "algo2", "milp") || error("unknown method $method")
    path = joinpath(CHAO, "$name.txt")
    isfile(path) || error("instance $name not found in data/benchmarks/chao")

    instance = read_chao_instance(path)
    bks = read_bks(name)
    @printf("Instance %s : %d clients, %d véhicules, durée maximale %g, BKS %g\n",
            name, length(clients(instance)), instance.m, instance.limit, bks)

    if method in ("all", "algo1")
        t = @elapsed s = insertion_vnd(instance)
        report(instance, "Algo 1 (meilleure insertion + VND)", s, t, bks)
    end
    if method in ("all", "algo2")
        t = @elapsed s = giant_split(instance; starts=100, seed=1)
        report(instance, "Algo 2 (tour géant + split + VND, 100 départs, seed 1)", s, t, bks)
    end
    if method in ("all", "milp")
        r = exact_solve(instance; time_limit=limit)
        note = r.optimal ? " - optimum prouvé" : " - arrêté à $(round(Int, limit)) s, optimum non prouvé"
        if isnothing(r.solution)
            println("\nPLNE (HiGHS)$note\n  aucune solution trouvée")
        else
            report(instance, "PLNE (HiGHS)", r.solution, r.solve_time, bks; note)
        end
    end
end

main(ARGS)
