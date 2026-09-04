const LON_DIM_NAMES = ("longitude", "lon")
const LAT_DIM_NAMES = ("latitude", "lat")
const TIME_DIM_NAMES = ("valid_time", "time")
const EXPVER_DIM_NAMES = ("expver",)

"""
Attributes that you must not copy when you write decoded data.
"""
const ENCODING_ATTRIBUTES = ("scale_factor", "add_offset", "_FillValue", "missing_value")

function clean_attributes(var)
    return Dict(
        String(k) => v for (k, v) in var.attrib if !(String(k) in ENCODING_ATTRIBUTES)
    )
end

function find_dim(dims, candidates, what)
    idx = findfirst(d -> d in candidates, dims)
    isnothing(idx) && error("No $what dimension found among $(dims)")
    return idx
end

"""
    drop_expver(data, dims)

`data` with any `expver` dimension collapsed onto its last index, and the
dimension names that are left.

CDS returns two experiment versions for a date inside the ERA5T window, `1` for
final ERA5 and `5` for the preliminary ERA5T, and only one of them holds data.
Taking the first index would silently give an all-missing field for a recent
date. Port of `_resolve_expver_conflict` in WeatherQuest
`get_initial_conditions.py`, which selects the largest `expver` and drops the
coordinate.
"""
function drop_expver(data, dims)
    idx = findfirst(in(EXPVER_DIM_NAMES), dims)
    isnothing(idx) && return data, dims
    slices = ntuple(i -> i == idx ? size(data, idx) : Colon(), ndims(data))
    return data[slices...], Tuple(d for (i, d) in enumerate(dims) if i != idx)
end

"""
    read_surface_field(ds, name)

Read the 2D field `name` as a `(lon, lat)` matrix of
`Union{Missing, Float64}`. Drops the singleton time dimension.
"""
function read_surface_field(ds, name)
    haskey(ds, name) || error("Variable $name not found in $(NCDatasets.path(ds))")
    var = ds[name]
    data, dims = drop_expver(Array(var), NCDatasets.dimnames(var))
    lon_idx = find_dim(dims, LON_DIM_NAMES, "longitude")
    lat_idx = find_dim(dims, LAT_DIM_NAMES, "latitude")
    slices = ntuple(i -> (i == lon_idx || i == lat_idx) ? Colon() : 1, ndims(data))
    field = data[slices...]
    lon_idx_2d = lon_idx < lat_idx ? 1 : 2
    lon_idx_2d == 1 || (field = permutedims(field))
    return Array{Union{Missing, Float64}}(field)
end

function first_present_name(ds, names)
    for name in names
        haskey(ds, name) && return name
    end
    return nothing
end

function read_lonlat(ds)
    lon_name = first_present_name(ds, LON_DIM_NAMES)
    lat_name = first_present_name(ds, LAT_DIM_NAMES)
    (isnothing(lon_name) || isnothing(lat_name)) &&
        error("No longitude/latitude coordinates found in $(NCDatasets.path(ds))")
    return Float64.(Array(ds[lon_name])), Float64.(Array(ds[lat_name]))
end

"""
    reference_date(ds, fallback = nothing)

The analysis date of a downloaded file, taken from its time coordinate. Every
ERA5 download has one, so `fallback` is only for a file that does not. Errors
if the file has no time coordinate and `fallback` is `nothing`.
"""
function reference_date(ds, fallback = nothing)
    for name in TIME_DIM_NAMES
        haskey(ds, name) || continue
        times = Array(ds[name])
        isempty(times) && continue
        return Dates.DateTime(first(times))
    end
    isnothing(fallback) && error(
        "$(NCDatasets.path(ds)) has no time coordinate (looked for " *
        "$(join(TIME_DIM_NAMES, ", "))). Pass `date` to supply one.",
    )
    return fallback
end
