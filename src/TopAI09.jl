module TopAI09

using Random
using TOML

include("core/instance.jl")
include("core/solution.jl")
include("core/evaluator.jl")
include("core/validator.jl")
include("io/instance_parser.jl")
include("io/chao_parser.jl")
include("local_search.jl")    # VND shared by both algorithms
include("insertion.jl")       # Algorithm 1: best insertion + VND
include("split.jl")           # Algorithm 2: giant tour + split + VND
include("milp.jl")            # MILP (section 2 of the report)

export TOPInstance, TOPSolution, ValidationReport, clients, route_duration,
       solution_profit, solution_durations, total_duration, unvisited_clients,
       insertion_delta, validate_solution, read_instance, read_chao_instance
export best_insertion, vnd, insertion_vnd, insertion_multistart
export giant_tour, two_opt_path!, split_tour, giant_split
export ExactResult, exact_solve

end
