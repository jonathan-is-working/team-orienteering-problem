"""
    read_chao_instance(path; name=splitext(basename(path))[1])

Read the semicolon-separated Chao TOP format distributed by UTC. The header
`n` counts both depots; the first coordinate row is departure, the last arrival.
Source customer index zero maps to Julia index two. Costs are unrounded Float64
Euclidean distances. No optimum or BKS is inferred from an instance file.
"""
function read_chao_instance(path::AbstractString; name::AbstractString=splitext(basename(path))[1])
    lines = readlines(path)
    length(lines) >= 3 || throw(ArgumentError("Chao instance requires three header lines"))
    function header(index, expected, type)
        fields = strip.(split(lines[index], ';'; keepempty=true))
        length(fields) == 2 && fields[1] == expected ||
            throw(ArgumentError("line $index must be $expected;value"))
        value = tryparse(type, fields[2])
        isnothing(value) && throw(ArgumentError("invalid $expected value on line $index"))
        return value
    end
    n = header(1, "n", Int)
    m = header(2, "m", Int)
    limit = header(3, "tmax", Float64)
    n >= 2 || throw(ArgumentError("n must include at least two depots"))
    length(lines) == n + 3 || throw(ArgumentError("expected $n coordinate rows, found $(length(lines)-3)"))
    coordinates = Matrix{Float64}(undef, n, 2)
    profits = Vector{Float64}(undef, n)
    for row in 1:n
        fields = strip.(split(lines[row+3], ';'; keepempty=true))
        length(fields) == 3 || throw(ArgumentError("coordinate row $row must contain x;y;profit"))
        values = tryparse.(Float64, fields)
        all(!isnothing, values) || throw(ArgumentError("invalid numeric value in coordinate row $row"))
        coordinates[row, 1] = values[1]
        coordinates[row, 2] = values[2]
        profits[row] = values[3]
    end
    costs = [hypot(coordinates[i,1]-coordinates[j,1], coordinates[i,2]-coordinates[j,2]) for i in 1:n, j in 1:n]
    ids = ["departure"; ["client-$(i-2)" for i in 2:n-1]; "arrival"]
    return TOPInstance(name, profits, costs, m, limit;
        start=1, finish=n, coordinates=coordinates, ids=ids)
end
