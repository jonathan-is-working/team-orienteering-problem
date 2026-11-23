"""
TOP data with distinct Julia node indices for the two depots.
`profits` and `costs` include both depots; only `clients(instance)` may be visited.
Coordinates are optional rows `(x,y)` and never override an explicit matrix.
"""
struct TOPInstance
    name::String
    profits::Vector{Float64}
    costs::Matrix{Float64}
    m::Int
    limit::Float64
    start::Int
    finish::Int
    coordinates::Union{Nothing,Matrix{Float64}}
    ids::Vector{String}
    function TOPInstance(name::AbstractString, profits::AbstractVector,
                         costs::AbstractMatrix, m::Integer, limit::Real;
                         start::Integer=1, finish::Integer=length(profits),
                         coordinates=nothing, ids=string.(1:length(profits)))
        p, c = Float64.(profits), Matrix{Float64}(costs)
        n = length(p)
        n >= 2 || throw(ArgumentError("two distinct depots are required"))
        size(c) == (n, n) || throw(ArgumentError("cost matrix dimensions differ from profits"))
        1 <= start <= n && 1 <= finish <= n && start != finish ||
            throw(ArgumentError("depots must be distinct valid node indices"))
        all(isfinite, p) && all(>=(0), p) || throw(ArgumentError("profits must be finite and nonnegative"))
        all(isfinite, c) && all(>=(0), c) || throw(ArgumentError("costs must be finite and nonnegative"))
        p[start] == 0 && p[finish] == 0 || throw(ArgumentError("depot profits must be zero"))
        m >= 0 || throw(ArgumentError("vehicle count must be nonnegative"))
        isfinite(limit) && limit >= 0 || throw(ArgumentError("duration limit must be finite and nonnegative"))
        labels = String.(ids)
        length(labels) == n && length(unique(labels)) == n || throw(ArgumentError("node identifiers must be unique"))
        xy = isnothing(coordinates) ? nothing : Matrix{Float64}(coordinates)
        isnothing(xy) || (size(xy) == (n, 2) && all(isfinite, xy)) ||
            throw(ArgumentError("coordinates must be a finite n by 2 matrix"))
        new(String(name), p, c, Int(m), Float64(limit), Int(start), Int(finish), xy, labels)
    end
end

clients(instance::TOPInstance) = [i for i in eachindex(instance.profits) if i != instance.start && i != instance.finish]
