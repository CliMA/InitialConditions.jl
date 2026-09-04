"""
    cache_root()

The directory that holds every cached initial condition, one subdirectory per
data source. This is a Scratch.jl directory, or `INITIAL_CONDITIONS_CACHE_DIR`
if you set it. Reads the environment on each call, so setting the variable
after loading the package still works.
"""
function cache_root()
    return get(ENV, "INITIAL_CONDITIONS_CACHE_DIR") do
        Scratch.@get_scratch!("initial_conditions")
    end
end

"""
    cache_dir(source)

The cache directory for one data source, for example `cache_dir("era5")`. Does
not create it, because the fetch does that.
"""
cache_dir(source::AbstractString) = joinpath(cache_root(), source)

"""
    datetimestamp(date)

A date as `YYYYMMDD_HHMM`, the stamp that initial condition file names use.
The same format as the WeatherQuest `DATETIME_FMT`.
"""
datetimestamp(date::Dates.DateTime) =
    Dates.format(date, Dates.dateformat"yyyymmdd_HHMM")
