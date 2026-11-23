# Turn results/raw/*.csv into the LaTeX tables and pgfplots data used by the report
# (results/tables, results/plots).
#   julia --project=. scripts/analyze.jl
using TopAI09
using Printf

const ROOT = joinpath(@__DIR__, "..")
const RAW = joinpath(ROOT, "results", "raw")
const TAB = joinpath(ROOT, "results", "tables")
const PLT = joinpath(ROOT, "results", "plots")
mkpath(TAB); mkpath(PLT)

function readcsv(path)
    lines = readlines(path)
    isempty(lines) && return Dict{String,String}[]
    header = split(lines[1], ',')
    [Dict(String(h) => String(v) for (h, v) in zip(header, split(l, ','))) for l in lines[2:end]]
end
num(r, k) = parse(Float64, r[k])
mean(v) = isempty(v) ? NaN : sum(v) / length(v)
gap(p, b) = 100 * (b - p) / b
fmt(x; d=2) = isnan(x) ? "--" : @sprintf("%.*f", d, x)
const VARIANTS = ["A1-construction", "A1", "A2-split", "A2", "Controle"]
const FAMILIES = ["p1", "p2", "p3", "p4", "p5", "p6", "p7"]

runs = readcsv(joinpath(RAW, "chao_runs.csv"))
instances = sort(unique(r["instance"] for r in runs))
info = Dict(r["instance"] => (fam=r["family"], n=Int(num(r, "n")), m=Int(num(r, "m")), bks=num(r, "bks")) for r in runs)

# per (instance, variant): mean gap over seeds, best gap, mean time
by = Dict{Tuple{String,String},Vector{Dict{String,String}}}()
for r in runs
    push!(get!(by, (r["instance"], r["variant"]), Dict{String,String}[]), r)
end
meangap(i, v) = mean([gap(num(r, "profit"), info[i].bks) for r in by[(i, v)]])
bestgap(i, v) = minimum(gap(num(r, "profit"), info[i].bks) for r in by[(i, v)])
meantime(i, v) = mean([num(r, "time") for r in by[(i, v)]])

# ---------- Key numbers used in the text ----------
open(joinpath(TAB, "numbers.tex"), "w") do io
    N = length(instances)
    hit(v) = count(i -> bestgap(i, v) <= 1e-9, instances)
    println(io, "\\newcommand{\\NbInst}{$N}")
    for (v, tag) in zip(VARIANTS, ["AC", "AUn", "AS", "ADeux", "Ctrl"])
        println(io, "\\newcommand{\\Hit$(tag)}{$(hit(v))}")
        println(io, "\\newcommand{\\Gap$(tag)}{$(fmt(mean([meangap(i, v) for i in instances])))}")
        println(io, "\\newcommand{\\Max$(tag)}{$(fmt(maximum(meangap(i, v) for i in instances); d=1))}")
        println(io, "\\newcommand{\\Time$(tag)}{$(fmt(mean([meantime(i, v) for i in instances]); d=3))}")
    end
    a2better = count(i -> meangap(i, "A2") < meangap(i, "Controle") - 1e-9, instances)
    ctrlbetter = count(i -> meangap(i, "Controle") < meangap(i, "A2") - 1e-9, instances)
    println(io, "\\newcommand{\\ADeuxBetter}{$a2better}\n\\newcommand{\\CtrlBetter}{$ctrlbetter}")
    # seed robustness for A2: mean over instances of (max - min) profit across seeds, in % of BKS
    spread = mean([100 * (maximum(num(r, "profit") for r in by[(i, "A2")]) -
                          minimum(num(r, "profit") for r in by[(i, "A2")])) / info[i].bks for i in instances])
    println(io, "\\newcommand{\\SpreadADeux}{$(fmt(spread))}")
end

# ---------- Fig: convergence (mean gap vs number of starts, seed 1) ----------
traces = readcsv(joinpath(RAW, "chao_traces.csv"))
acc = Dict{Tuple{String,String,Int},Vector{Float64}}()
for r in traces
    g = gap(num(r, "profit"), num(r, "bks"))
    for grp in ("all", r["family"] in ("p4", "p5", "p7") ? "large" : "small")
        push!(get!(acc, (grp, r["variant"], parse(Int, r["start"])), Float64[]), g)
    end
end
open(joinpath(PLT, "convergence.csv"), "w") do io
    println(io, "start,A2all,CTRLall,A2large,CTRLlarge,A2small,CTRLsmall")
    for s in 1:maximum(k[3] for k in keys(acc))
        vals = [fmt(mean(get(acc, (g, v, s), Float64[])); d=3) for g in ("all", "large", "small") for v in ("A2", "Controle")]
        println(io, join([string(s); vals], ','))
    end
end

# ---------- Table 1: MILP (families p2, p1, p3) ----------
milp_files = filter(f -> startswith(f, "milp_runs_") && endswith(f, ".csv"), readdir(RAW))
if !isempty(milp_files)
    # One row per instance: if an instance was solved in several campaigns, the most recent file wins.
    milp_files = sort(milp_files; by=f -> mtime(joinpath(RAW, f)))
    milp = collect(values(Dict(r["instance"] => r for f in milp_files for r in readcsv(joinpath(RAW, f)))))
    fam(r) = r["instance"][1:2]
    a2profit(i) = mean([num(r, "profit") for r in by[(i, "A2")]])
    open(joinpath(TAB, "milp_summary.tex"), "w") do io
        println(io, "\\begin{tabular}{|c|c|c|c|c|}\n\\hline")
        println(io, "\\textbf{Famille} & \\textbf{Clients} & \\textbf{Optimum prouvé} & \\textbf{Temps moyen} & \\textbf{Écart à la BKS} \\\\\n\\hline")
        for f in ("p2", "p1", "p3")
            R = [r for r in milp if fam(r) == f]
            isempty(R) && continue
            opt = [r for r in R if r["status"] == "OPTIMAL"]
            tl = [r for r in R if r["status"] != "OPTIMAL"]
            # Mean gap over the whole family (proven instances count for their optimum, i.e. 0 %).
            g_milp = mean([isnan(num(r, "profit")) ? 100.0 : gap(num(r, "profit"), num(r, "bks")) for r in R])
            println(io, join([f, Int(num(R[1], "n")), "$(length(opt))/$(length(R))",
                              "$(fmt(mean([num(r, "time") for r in opt]); d=1))~s", "$(fmt(g_milp; d=1))~\\%"], " & "), " \\\\\n\\hline")
        end
        println(io, "\\end{tabular}")
    end
    open(joinpath(TAB, "milp_numbers.tex"), "w") do io
        for f in ("p2", "p1", "p3")
            R = [r for r in milp if fam(r) == f]
            isempty(R) && continue
            opt = [r for r in R if r["status"] == "OPTIMAL"]
            tag = Dict("p1" => "Un", "p2" => "Deux", "p3" => "Trois")[f]
            println(io, "\\newcommand{\\MilpInst$tag}{$(length(R))}\\newcommand{\\MilpOpt$tag}{$(length(opt))}")
        end
        opt = [r for r in milp if r["status"] == "OPTIMAL"]
        tl = [r for r in milp if r["status"] != "OPTIMAL"]
        eq = count(r -> abs(num(r, "profit") - num(r, "bks")) < 1e-6, opt)
        worse = count(r -> isnan(num(r, "profit")) || num(r, "profit") < a2profit(r["instance"]) - 1e-6, tl)
        better = count(r -> !isnan(num(r, "profit")) && num(r, "profit") > a2profit(r["instance"]) + 1e-6, tl)
        # heuristics on proven instances
        a1opt = count(r -> meangap(r["instance"], "A1") < 1e-9, opt)
        a2opt = count(r -> bestgap(r["instance"], "A2") < 1e-9, opt)
        println(io, "\\newcommand{\\MilpInst}{$(length(milp))}\\newcommand{\\MilpOpt}{$(length(opt))}\\newcommand{\\MilpEq}{$eq}")
        println(io, "\\newcommand{\\MilpTL}{$(length(tl))}\\newcommand{\\MilpWorse}{$worse}\\newcommand{\\MilpBetter}{$better}")
        println(io, "\\newcommand{\\MilpAUnOpt}{$a1opt}\\newcommand{\\MilpADeuxOpt}{$a2opt}")
        found = count(r -> !isnan(num(r, "profit")) && abs(num(r, "profit") - num(r, "bks")) < 1e-6, tl)
        println(io, "\\newcommand{\\MilpFoundTL}{$found}")
    end
end

# ---------- Boxed per-algorithm tables ----------
function boxed(io, header, rows)
    cols = length(header)
    println(io, "\\begin{tabular}{|" * join(fill("c", cols), "|") * "|}\n\\hline")
    println(io, join(["\\textbf{$h}" for h in header], " & "), " \\\\\n\\hline")
    for r in rows
        r[1] == "Total" && println(io, "\\hline")
        println(io, join(r, " & "), " \\\\\n\\hline")
    end
    println(io, "\\end{tabular}")
end
famrows(f) = [(fam, [i for i in instances if info[i].fam == fam]) for fam in FAMILIES] |> v -> [v; [("Total", instances)]]
hitcount(I, v) = count(i -> bestgap(i, v) <= 1e-9, I)

open(joinpath(TAB, "algo1_table.tex"), "w") do io
    rows = [[f, f == "Total" ? "--" : string(info[I[1]].n), string(length(I)),
             fmt(mean([meangap(i, "A1-construction") for i in I])), fmt(mean([meangap(i, "A1") for i in I])),
             "$(hitcount(I, "A1"))/$(length(I))", fmt(1000 * mean([meantime(i, "A1") for i in I]); d=1)]
            for (f, I) in famrows(nothing)]
    boxed(io, ["Famille", "Clients", "Inst.", "Construction", "+ VND", "BKS atteinte", "Temps (ms)"], rows)
end
open(joinpath(TAB, "algo2_table.tex"), "w") do io
    rows = [[f, fmt(mean([meangap(i, "A2-split") for i in I])), fmt(mean([meangap(i, "A2") for i in I])),
             fmt(mean([meangap(i, "Controle") for i in I])),
             "$(hitcount(I, "A2"))/$(length(I))", fmt(mean([meantime(i, "A2") for i in I]); d=3),
             fmt(mean([meantime(i, "Controle") for i in I]); d=3)]
            for (f, I) in famrows(nothing)]
    boxed(io, ["Famille", "Split seul", "Algo 2", "Contrôle", "BKS atteinte", "Temps Algo 2", "Temps contr."], rows)
end

# ---------- Synthesis: all methods on the MILP subset (p1, p2, p3) + all instances ----------
if !isempty(milp_files)
    small = [r["instance"] for r in milp]
    milp_by = Dict(r["instance"] => r for r in milp)
    milp_gap(i) = (r = milp_by[i]; r["status"] == "OPTIMAL" ? 0.0 : (isnan(num(r, "profit")) ? 100.0 : gap(num(r, "profit"), num(r, "bks"))))
    milp_time(i) = num(milp_by[i], "time")
    methods = [("PLNE (60 s)", "exacte", nothing),
               ("Algo 1, construction seule", "heuristique", "A1-construction"),
               ("Algo 1 complet", "heuristique + descente", "A1"),
               ("Algo 2, split seul", "heuristique", "A2-split"),
               ("Algo 2 complet", "métaheuristique", "A2")]
    open(joinpath(PLT, "tradeoff.csv"), "w") do io
        println(io, "method,time,gap,label")
        short = Dict("PLNE (60 s)" => "PLNE (60 s)", "Algo 1, construction seule" => "Algo 1 construction",
                     "Algo 1 complet" => "Algo 1", "Algo 2, split seul" => "split seul",
                     "Algo 2 complet" => "Algo 2")
        for (name, _, v) in methods
            t = isnothing(v) ? mean(milp_time.(small)) : mean([meantime(i, v) for i in small])
            g = isnothing(v) ? mean(milp_gap.(small)) : mean([meangap(i, v) for i in small])
            println(io, "$(replace(name, r"[ :()+,]" => "")),$(t),$(g),{$(short[name])}")
        end
    end
    tfmt(t) = t < 1 ? fmt(1000t; d=1) * "~ms" : fmt(t; d=1) * "~s"
    open(joinpath(TAB, "synthesis_table.tex"), "w") do io
        println(io, "\\begin{tabular}{|l|l|c|c|c|c|}\n\\hline")
        println(io, "\\multirow{2}{*}{\\textbf{Méthode}} & \\multirow{2}{*}{\\textbf{Type}} & \\multicolumn{2}{c|}{\\textbf{p1 à p3 ($(length(small)))}} & \\multicolumn{2}{c|}{\\textbf{Toutes ($(length(instances)))}} \\\\\n\\cline{3-6}")
        println(io, " & & \\textbf{Écart} & \\textbf{Temps} & \\textbf{Écart} & \\textbf{Temps} \\\\\n\\hline")
        for (name, typ, v) in methods
            if isnothing(v)
                cells = [fmt(mean(milp_gap.(small))) * "~\\%", tfmt(mean(milp_time.(small))), "--", "--"]
            else
                cells = [fmt(mean([meangap(i, v) for i in small])) * "~\\%", tfmt(mean([meantime(i, v) for i in small])),
                         fmt(mean([meangap(i, v) for i in instances])) * "~\\%", tfmt(mean([meantime(i, v) for i in instances]))]
            end
            println(io, join([name, typ, cells...], " & "), " \\\\\n\\hline")
        end
        println(io, "\\end{tabular}")
    end
end

# French decimal comma in the LaTeX tables (the pgfplots data in results/plots keeps the dot).
for f in readdir(TAB; join=true)
    lines = [replace(l, r"(\d)\.(\d)" => s"\1{,}\2") for l in readlines(f)]
    write(f, join(lines, '\n') * '\n')
end
println("tables in $TAB, plot data in $PLT")
