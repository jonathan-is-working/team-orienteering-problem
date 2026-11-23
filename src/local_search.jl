"""
Local search shared by both algorithms: a Variable Neighbourhood Descent (VND).

Neighbourhoods, in this order:
1. `insert`  : add a free client (TOP move, profit +P_j);
2. `replace` : swap a served client for a more profitable free one (TOP move);
3. `two_opt` : reverse a segment inside a route (TSP 2-opt);
4. `or_opt`  : move a chain of 1–3 consecutive clients, within a route or to
               another route (TSP Or-opt, inter-route relocate of the VRP);
5. `swap`    : exchange two clients of two routes (VRP exchange).

Moves 1–2 raise the profit. Moves 3–5 keep it and shorten the routes, which
frees time for later insertions. A move is accepted only if it is feasible and
improves `(profit, −total duration)` lexicographically; after any improvement
the descent restarts at neighbourhood 1, so the search ends in a solution that
is a local optimum for all five neighbourhoods.
"""
mutable struct _State
    routes::Vector{Vector{Int}}
    dur::Vector{Float64}
    free::Set{Int}
end

_before(inst, r, g) = g == 1 ? inst.start : r[g-1]       # node before gap g
_after(inst, r, g) = g == length(r) + 1 ? inst.finish : r[g]  # node after gap g

function _drop_empty!(s::_State)
    keep = .!isempty.(s.routes)
    s.routes, s.dur = s.routes[keep], s.dur[keep]
end

function _insert!(inst, s::_State)
    C, L = inst.costs, inst.limit
    for j in sort!(collect(s.free); by=j -> (-inst.profits[j], j))
        best, bestδ = nothing, Inf
        for (k, r) in enumerate(s.routes), g in 1:length(r)+1
            u, v = _before(inst, r, g), _after(inst, r, g)
            δ = C[u, j] + C[j, v] - C[u, v]
            δ < bestδ && s.dur[k] + δ <= L + EPS && ((best, bestδ) = ((k, g), δ))
        end
        if length(s.routes) < inst.m
            δ = C[inst.start, j] + C[j, inst.finish]
            δ < bestδ && δ <= L + EPS && ((best, bestδ) = ((0, 1), δ))
        end
        isnothing(best) && continue
        k, g = best
        if k == 0
            push!(s.routes, [j]); push!(s.dur, bestδ)
        else
            insert!(s.routes[k], g, j); s.dur[k] += bestδ
        end
        delete!(s.free, j)
        return true
    end
    return false
end

function _replace!(inst, s::_State)
    C, L, P = inst.costs, inst.limit, inst.profits
    best, bestgain = nothing, EPS
    for (k, r) in enumerate(s.routes), p in eachindex(r)
        i = r[p]
        u, v = _before(inst, r, p), _after(inst, r, p + 1)
        reduced = s.dur[k] - (C[u, i] + C[i, v] - C[u, v])
        base = deleteat!(copy(r), p)
        for j in s.free
            gain = P[j] - P[i]
            gain > bestgain || continue
            for g in 1:length(base)+1
                x, y = _before(inst, base, g), _after(inst, base, g)
                newdur = reduced + C[x, j] + C[j, y] - C[x, y]
                if newdur <= L + EPS
                    best, bestgain = (k, p, j, g, newdur), gain
                    break
                end
            end
        end
    end
    isnothing(best) && return false
    k, p, j, g, newdur = best
    push!(s.free, s.routes[k][p])
    deleteat!(s.routes[k], p)
    insert!(s.routes[k], g, j)
    s.dur[k] = newdur
    delete!(s.free, j)
    return true
end

function _two_opt!(inst, s::_State)
    for (k, r) in enumerate(s.routes), i in 1:length(r)-1, j in i+1:length(r)
        trial = reverse(r, i, j)
        newdur = route_duration(inst, trial)  # exact, also for asymmetric costs
        if newdur < s.dur[k] - EPS
            s.routes[k], s.dur[k] = trial, newdur
            return true
        end
    end
    return false
end

function _or_opt!(inst, s::_State)
    C, L = inst.costs, inst.limit
    for (k, r) in enumerate(s.routes), w in 1:3, i in 1:length(r)-w+1
        seg = r[i:i+w-1]
        first_, last_ = seg[1], seg[end]
        inner = sum((C[seg[p], seg[p+1]] for p in 1:w-1); init=0.0)
        u, v = _before(inst, r, i), _after(inst, r, i + w)
        removed = s.dur[k] - (C[u, first_] + inner + C[last_, v] - C[u, v])
        base = deleteat!(copy(r), i:i+w-1)
        removed = isempty(base) ? 0.0 : removed
        for (t, target) in enumerate(s.routes)
            route = t == k ? base : target
            start = t == k ? removed : s.dur[t]
            (t == k && isempty(base)) && continue
            for g in 1:length(route)+1
                t == k && g == i && continue  # original position
                x, y = _before(inst, route, g), _after(inst, route, g)
                newdur = start + C[x, first_] + inner + C[last_, y] - C[x, y]
                newdur <= L + EPS || continue
                before = t == k ? s.dur[k] : s.dur[k] + s.dur[t]
                after = t == k ? newdur : removed + newdur
                if after < before - EPS
                    if t == k
                        b = copy(base)
                        splice!(b, g:g-1, seg)
                        s.routes[k], s.dur[k] = b, newdur
                    else
                        splice!(s.routes[t], g:g-1, seg); s.dur[t] = newdur
                        s.routes[k], s.dur[k] = base, removed
                        _drop_empty!(s)
                    end
                    return true
                end
            end
        end
    end
    return false
end

function _swap!(inst, s::_State)
    C, L = inst.costs, inst.limit
    R = s.routes
    for k1 in eachindex(R), k2 in k1+1:length(R), p1 in eachindex(R[k1]), p2 in eachindex(R[k2])
        x, y = R[k1][p1], R[k2][p2]
        u1, v1 = _before(inst, R[k1], p1), _after(inst, R[k1], p1 + 1)
        u2, v2 = _before(inst, R[k2], p2), _after(inst, R[k2], p2 + 1)
        d1 = s.dur[k1] - C[u1, x] - C[x, v1] + C[u1, y] + C[y, v1]
        d2 = s.dur[k2] - C[u2, y] - C[y, v2] + C[u2, x] + C[x, v2]
        if d1 <= L + EPS && d2 <= L + EPS && d1 + d2 < s.dur[k1] + s.dur[k2] - EPS
            R[k1][p1], R[k2][p2] = y, x
            s.dur[k1], s.dur[k2] = d1, d2
            return true
        end
    end
    return false
end

const NEIGHBOURHOODS = (_insert!, _replace!, _two_opt!, _or_opt!, _swap!)

"""
    vnd(instance, solution; time_limit=Inf) -> TOPSolution

Improve `solution` with the VND described above. The returned solution is
always feasible and never worse than the input.
"""
function vnd(instance::TOPInstance, solution::TOPSolution; time_limit::Real=Inf)
    started = time_ns()
    routes = [copy(r) for r in solution.routes if !isempty(r)]
    served = Set(i for r in routes for i in r)
    free = Set(j for j in clients(instance) if instance.profits[j] > 0 && !(j in served))
    s = _State(routes, [route_duration(instance, r) for r in routes], free)
    k = 1
    while k <= length(NEIGHBOURHOODS)
        (time_ns() - started) / 1e9 >= time_limit && break
        k = NEIGHBOURHOODS[k](instance, s) ? 1 : k + 1
    end
    return TOPSolution(s.routes)
end
