# Full benchmark on the Chao instances (all instances with a positive BKS).
#   julia --project=. scripts/benchmark.jl chao   # heuristics, all instances
#   julia --project=. scripts/benchmark.jl milp p2 [CHUNK NCHUNKS]   # MILP, one family
# Raw results go to results/raw/. Every solution is checked by the validator.
using TopAI09

const ROOT = joinpath(@__DIR__, "..")
const CHAO = joinpath(ROOT, "data", "benchmarks", "chao")
const RAW = joinpath(ROOT, "results", "raw")
const SEEDS = 1:5
const STARTS = 100

function read_bks()
    rows = split.(readlines(joinpath(CHAO, "bks.csv"))[2:end], ',')
    Dict(String(r[1]) => parse(Float64, r[2]) for r in rows)
end

load(name) = read_chao_instance(joinpath(CHAO, "$name.txt"))

function timed(f, instance)
    t = @elapsed out = f()
    s, trace = out isa Tuple ? out : (out, Float64[])
    report = validate_solution(instance, s)
    report.valid || error("$(instance.name): invalid solution $(report.errors)")
    return report.profit, t, trace
end

function run_chao()
    mkpath(RAW)
    bks = read_bks()
    names = sort([k for (k, v) in bks if v > 0])
    # warm-up (compilation is excluded from timings)
    let w = load("p2.2.a")
        best_insertion(w); insertion_vnd(w); giant_split(w; starts=2); insertion_multistart(w; starts=2)
    end
    open(joinpath(RAW, "chao_runs.csv"), "w") do io
        open(joinpath(RAW, "chao_traces.csv"), "w") do tio
            println(io, "instance,family,n,m,L,bks,variant,seed,profit,time")
            println(tio, "instance,family,variant,start,profit,bks")
            for (idx, name) in enumerate(names)
                inst = load(name)
                fam, n, b = name[1:2], length(clients(inst)), bks[name]
                row(v, seed, p, t) = println(io, join((name, fam, n, inst.m, inst.limit, b, v, seed, p, round(t; digits=6)), ','))
                p, t, _ = timed(() -> best_insertion(inst), inst); row("A1-construction", 0, p, t)
                p, t, _ = timed(() -> insertion_vnd(inst), inst); row("A1", 0, p, t)
                p, t, _ = timed(() -> giant_split(inst; starts=STARTS, seed=1, improve=false), inst)
                row("A2-split", 1, p, t)
                for seed in SEEDS
                    for (v, f) in (("A2", () -> giant_split(inst; starts=STARTS, seed=seed, history=true)),
                                   ("Controle", () -> insertion_multistart(inst; starts=STARTS, seed=seed, history=true)))
                        p, t, trace = timed(f, inst)
                        row(v, seed, p, t)
                        seed == 1 && for (s, q) in enumerate(trace)
                            println(tio, join((name, fam, v, s, q, b), ','))
                        end
                    end
                end
                flush(io)
                idx % 20 == 0 && println("$idx/$(length(names)) $name")
            end
        end
    end
end

function run_milp(; family="p2", chunk=1, nchunks=1, time_limit=60.0)
    mkpath(RAW)
    bks = read_bks()
    names = sort([k for (k, v) in bks if startswith(k, family * ".") && v > 0])
    names = names[chunk:nchunks:end]
    out = "milp_runs_$(family)_$(chunk).csv"
    exact_solve(load("p2.2.a"); time_limit=5.0)  # warm-up
    open(joinpath(RAW, out), "w") do io
        println(io, "instance,n,m,L,bks,status,profit,upper_bound,time")
        for name in names
            inst = load(name)
            r = exact_solve(inst; time_limit=time_limit)
            isnothing(r.solution) || validate_solution(inst, r.solution).valid || error("invalid MILP solution")
            println(io, join((name, length(clients(inst)), inst.m, inst.limit, bks[name], r.status,
                              something(r.profit, NaN), something(r.upper_bound, NaN),
                              round(r.solve_time; digits=3)), ','))
            flush(io)
            println("$name $(r.status) $(r.profit) / bks $(bks[name]) in $(round(r.solve_time; digits=1))s")
        end
    end
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    mode = isempty(ARGS) ? "chao" : ARGS[1]
    if mode == "chao"
        run_chao()
    elseif mode == "milp"   # milp [FAMILY [CHUNK NCHUNKS]]
        family = length(ARGS) >= 2 ? ARGS[2] : "p2"
        chunk, nchunks = length(ARGS) >= 4 ? parse.(Int, ARGS[3:4]) : (1, 1)
        run_milp(; family, chunk, nchunks)
    else
        error("mode must be chao or milp")
    end
end
