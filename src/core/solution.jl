"""
Routes contain client indices only: departure and arrival are implicit.
An unused vehicle has no route; empty routes are rejected by the validator.
If given, `claimed_profit` is compared by the validator with the recomputed profit.
"""
struct TOPSolution
    routes::Vector{Vector{Int}}
    claimed_profit::Union{Nothing,Float64}
    function TOPSolution(routes::AbstractVector=Vector{Int}[]; claimed_profit=nothing)
        claim = isnothing(claimed_profit) ? nothing : Float64(claimed_profit)
        new([Int.(route) for route in routes], claim)
    end
end

Base.copy(solution::TOPSolution) = TOPSolution(deepcopy(solution.routes); claimed_profit=solution.claimed_profit)
