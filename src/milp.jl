import JuMP
import HiGHS

const _MOI = JuMP.MOI

"""Result of a MILP run. `optimal` is true only when HiGHS proved optimality."""
struct ExactResult
    solution::Union{Nothing,TOPSolution}
    profit::Union{Nothing,Float64}
    upper_bound::Union{Nothing,Float64}
    status::String
    solve_time::Float64
    optimal::Bool
    relative_gap::Union{Nothing,Float64}
end

"""
    exact_solve(instance; time_limit=60.0, silent=true, threads=1) -> ExactResult

Solve the flow formulation of the report (section 2) with JuMP and HiGHS.
`solve_time` is the solver time only, without model construction. When the
time limit is reached, the best solution found so far is returned with
`optimal = false`. The returned routes are checked by the validator.
"""
function exact_solve(instance::TOPInstance; time_limit::Real=60.0,
                     silent::Bool=true, threads::Integer=1)
    isfinite(time_limit) && time_limit > 0 ||
        throw(ArgumentError("time_limit must be finite and positive"))
    threads > 0 || throw(ArgumentError("threads must be positive"))
    N = clients(instance)
    n = length(N)
    # HiGHS rejects a model without variables: with no client or no vehicle the optimum is 0.
    if n == 0 || instance.m == 0
        solution = TOPSolution(Vector{Int}[]; claimed_profit=0.0)
        validate_solution(instance, solution).valid || error("Invalid empty solution")
        return ExactResult(solution, 0.0, 0.0, "OPTIMAL", 0.0, true, 0.0)
    end
    K = 1:instance.m
    d, a = instance.start, instance.finish
    arcs = vcat([(d, j) for j in N],
                [(i, j) for i in N for j in N if i != j],
                [(i, a) for i in N])
    E = eachindex(arcs)
    incoming = Dict(i => [e for e in E if arcs[e][2] == i] for i in N)
    outgoing = Dict(i => [e for e in E if arcs[e][1] == i] for i in N)
    departures = [e for e in E if arcs[e][1] == d]
    arrivals = [e for e in E if arcs[e][2] == a]
    flow_arcs = [e for e in E if arcs[e][2] != a]
    flow_outgoing = Dict(i => [e for e in outgoing[i] if arcs[e][2] != a] for i in N)

    model = JuMP.Model(HiGHS.Optimizer)
    silent && JuMP.set_silent(model)
    JuMP.set_time_limit_sec(model, Float64(time_limit))
    JuMP.set_optimizer_attribute(model, "threads", Int(threads))
    # Only stop on a proven optimum (zero gap) or on the time limit.
    JuMP.set_optimizer_attribute(model, "mip_rel_gap", 0.0)
    JuMP.set_optimizer_attribute(model, "mip_abs_gap", 0.0)
    JuMP.@variable(model, x[E, K], Bin)
    JuMP.@variable(model, y[N, K], Bin)
    JuMP.@variable(model, z[K], Bin)
    JuMP.@variable(model, f[flow_arcs, K] >= 0)
    JuMP.@objective(model, Max, sum(instance.profits[i] * y[i, k] for i in N, k in K))
    JuMP.@constraint(model, [i in N], sum(y[i, k] for k in K) <= 1)
    JuMP.@constraint(model, [k in K], sum(x[e, k] for e in departures) == z[k])
    JuMP.@constraint(model, [k in K], sum(x[e, k] for e in arrivals) == z[k])
    JuMP.@constraint(model, [i in N, k in K], sum(x[e, k] for e in incoming[i]) == y[i, k])
    JuMP.@constraint(model, [i in N, k in K], sum(x[e, k] for e in outgoing[i]) == y[i, k])
    JuMP.@constraint(model, [i in N, k in K], y[i, k] <= z[k])
    JuMP.@constraint(model, [k in K],
        sum(instance.costs[arcs[e]...] * x[e, k] for e in E) <= instance.limit * z[k])
    JuMP.@constraint(model, [k in K], sum(f[e, k] for e in departures) == sum(y[i, k] for i in N))
    JuMP.@constraint(model, [i in N, k in K],
        sum(f[e, k] for e in incoming[i]) - sum(f[e, k] for e in flow_outgoing[i]) == y[i, k])
    JuMP.@constraint(model, [e in flow_arcs, k in K], f[e, k] <= n * x[e, k])
    JuMP.optimize!(model)

    status = JuMP.termination_status(model)
    elapsed = JuMP.solve_time(model)
    bound_value = JuMP.objective_bound(model)
    bound = isfinite(bound_value) ? Float64(bound_value) : nothing
    if !JuMP.has_values(model) || JuMP.primal_status(model) != _MOI.FEASIBLE_POINT
        return ExactResult(nothing, nothing, bound, string(status), elapsed, false, nothing)
    end

    # Rebuild each route by following the selected arcs from d to a.
    routes = Vector{Int}[]
    tol = 1e-5
    for k in K
        binary_values = vcat([JuMP.value(x[e, k]) for e in E],
                             [JuMP.value(y[i, k]) for i in N], [JuMP.value(z[k])])
        all(v -> isfinite(v) && abs(v - round(v)) <= tol, binary_values) ||
            error("Nonintegral incumbent returned for vehicle $k")
        selected = Set(e for e in E if JuMP.value(x[e, k]) > 0.5)
        expected = Set(i for i in N if JuMP.value(y[i, k]) > 0.5)
        if JuMP.value(z[k]) < 0.5
            isempty(selected) && isempty(expected) || error("Inactive vehicle has selected visits")
            continue
        end
        route = Int[]
        used = Set{Int}()
        current = d
        while current != a
            next_edges = [e for e in selected if arcs[e][1] == current]
            length(next_edges) == 1 || error("Missing or branching successor in vehicle $k")
            e = only(next_edges)
            e in used && error("Cycle detected while extracting vehicle $k")
            push!(used, e)
            current = arcs[e][2]
            if current != a
                current in route && error("Repeated client while extracting vehicle $k")
                push!(route, current)
            end
        end
        !isempty(route) && used == selected && Set(route) == expected ||
            error("Disconnected arcs or inconsistent visits in vehicle $k")
        push!(routes, route)
    end
    incumbent = Float64(JuMP.objective_value(model))
    solution = TOPSolution(routes; claimed_profit=incumbent)
    report = validate_solution(instance, solution)
    report.valid || error("MILP incumbent rejected by validator: $(join(report.errors, "; "))")
    isapprox(report.profit, incumbent; atol=1e-6, rtol=1e-8) ||
        error("Extracted profit disagrees with MILP objective")
    gap = bound === nothing ? nothing : max(0.0, bound - report.profit) / max(abs(report.profit), 1e-10)
    return ExactResult(solution, report.profit, bound, string(status), elapsed,
                       status == _MOI.OPTIMAL, gap)
end
