"Read an instance from a TOML file (used for the small test instances). Nodes keep the file order."
function read_instance(path::AbstractString)
    data = TOML.parsefile(path)
    profits = data["profits"]
    n = length(profits)
    xy = if haskey(data, "coordinates")
        rows = data["coordinates"]
        length(rows) == n && all(row -> length(row) == 2, rows) || throw(ArgumentError("invalid coordinate rows"))
        [Float64(rows[i][j]) for i in 1:n, j in 1:2]
    else
        nothing
    end
    costs = if haskey(data, "costs")
        rows = data["costs"]
        length(rows) == n && all(row -> length(row) == n, rows) || throw(ArgumentError("invalid cost matrix rows"))
        [Float64(rows[i][j]) for i in 1:n, j in 1:n]
    elseif !isnothing(xy)
        # No rounding: euclidean distances from the provided coordinates.
        [hypot(xy[i, 1] - xy[j, 1], xy[i, 2] - xy[j, 2]) for i in 1:n, j in 1:n]
    else
        throw(ArgumentError("an explicit cost matrix or coordinates are required"))
    end
    TOPInstance(get(data, "name", basename(path)), profits, costs, data["m"], data["limit"];
        start=get(data, "start", 1), finish=get(data, "finish", n),
        coordinates=xy, ids=get(data, "ids", string.(1:n)))
end
