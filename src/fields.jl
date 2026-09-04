"""
    zero_fill(field)

Replace `missing` and `NaN` with 0. Use this for masked fields that must be 0
outside the mask, such as soil moisture, soil temperature, and snow.
"""
zero_fill(field) = Float64[(ismissing(x) || isnan(x)) ? 0.0 : Float64(x) for x in field]

"""
    nearest_neighbor_fill(field)

Replace `missing` and `NaN` cells with the value of the nearest valid cell.
The distance is measured in index space with a multi-source breadth-first
search over the 8-connected grid. Use this for fields that must have a value
everywhere but have no meaningful fill value, such as SST over land and snow
temperature over ocean.

The search does not wrap around the edges of the array, so cells at the seam of
the longitude axis get their fill from the same side. Roll the longitudes
before filling, as WeatherQuest does, so both put that seam in the same place.
Port of `fill_nans_nearest_neighbor` in WeatherQuest `interpolate.jl`, with the
BFS in place of ScatteredInterpolation.
"""
function nearest_neighbor_fill(matrix::AbstractMatrix)
    filled = Float64[ismissing(x) ? NaN : Float64(x) for x in matrix]
    any(isnan, filled) || return filled
    all(isnan, filled) && error("Cannot fill a field with no valid values")
    (nx, ny) = size(filled)
    queue = Vector{Tuple{Int, Int}}()
    visited = falses(nx, ny)
    for j in 1:ny, i in 1:nx
        if !isnan(filled[i, j])
            push!(queue, (i, j))
            visited[i, j] = true
        end
    end
    head = 1
    while head <= length(queue)
        (i, j) = queue[head]
        head += 1
        for dj in -1:1, di in -1:1
            (di == 0 && dj == 0) && continue
            (ii, jj) = (i + di, j + dj)
            (1 <= ii <= nx && 1 <= jj <= ny) || continue
            visited[ii, jj] && continue
            visited[ii, jj] = true
            filled[ii, jj] = filled[i, j]
            push!(queue, (ii, jj))
        end
    end
    return filled
end

"""
    roll_longitudes(lon)

The longitudes converted to [0, 360) and sorted, with the permutation that
sorts them. The SST, SIC, and albedo files use a [0, 360) longitude axis.
Port of the longitude roll in WeatherQuest `interpolate.jl`.
"""
function roll_longitudes(lon)
    lon360 = mod.(lon, 360)
    perm = sortperm(lon360)
    return lon360[perm], perm
end

"""
    monthly_time_points(date)

Four monthly time points [date - 1 month, date, date + 1 month,
date + 2 months], as seconds since 1970-01-01. The SST, SIC, and albedo
files copy one field to all four points, so time interpolation gives a
constant value across a subseasonal run. Port of the time axis in
WeatherQuest `preprocess_sst`.
"""
function monthly_time_points(date)
    points = [date - Dates.Month(1), date, date + Dates.Month(1), date + Dates.Month(2)]
    epoch = Dates.DateTime(1970, 1, 1)
    return [Dates.value(Dates.Second(t - epoch)) for t in points]
end

const TIME_ATTRIB = Dict(
    "standard_name" => "time",
    "long_name" => "time",
    "units" => "seconds since 1970-01-01",
    "calendar" => "proleptic_gregorian",
)

const LON_ATTRIB = Dict(
    "standard_name" => "longitude",
    "long_name" => "Longitude",
    "units" => "degrees_east",
    "axis" => "X",
)

const LAT_ATTRIB = Dict(
    "standard_name" => "latitude",
    "long_name" => "Latitude",
    "units" => "degrees_north",
    "axis" => "Y",
)

"""
    lat_attributes(lat)

The latitude attributes, with the `stored_direction` that WeatherQuest writes.
ERA5 stores latitude decreasing, and only the integrated-land file sorts it, so
read the direction off the axis rather than hard coding it.
"""
function lat_attributes(lat)
    direction = issorted(lat) ? "increasing" : "decreasing"
    return merge(LAT_ATTRIB, Dict("stored_direction" => direction))
end

"""
    define_lonlat_time!(ncout, lon, lat, time_points)

Define the lon and lat dimensions with their coordinate variables. Also
define a time dimension if `time_points` is not `nothing`.
"""
function define_lonlat_time!(ncout, lon, lat, time_points)
    NCDatasets.defDim(ncout, "lon", length(lon))
    NCDatasets.defDim(ncout, "lat", length(lat))
    lon_var = NCDatasets.defVar(ncout, "lon", Float32, ("lon",), attrib = LON_ATTRIB)
    lat_var =
        NCDatasets.defVar(ncout, "lat", Float32, ("lat",), attrib = lat_attributes(lat))
    lon_var[:] = lon
    lat_var[:] = lat
    if !isnothing(time_points)
        NCDatasets.defDim(ncout, "time", length(time_points))
        time_var = NCDatasets.defVar(ncout, "time", Int64, ("time",), attrib = TIME_ATTRIB)
        time_var[:] = time_points
    end
    return nothing
end

"""
    write_replicated_time_var!(ncout, name, field, ntimes; attrib)

Define the `(lon, lat, time)` variable `name` and write `field` to every time
slice.
"""
function write_replicated_time_var!(ncout, name, field, ntimes; attrib)
    var = NCDatasets.defVar(ncout, name, Float32, ("lon", "lat", "time"), attrib = attrib)
    for t in 1:ntimes
        var[:, :, t] = field
    end
    return nothing
end
