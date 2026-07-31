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
    datestamp(date)

A date as `YYYYMMDD`, the stamp that initial condition file names use.
"""
datestamp(date::Dates.DateTime) = Dates.format(date, Dates.dateformat"yyyymmdd")

"""
    cleanup_stale_tmpdirs(dir, prefix; max_age_seconds = 86400)

Remove the download directories under `dir` whose names start with `prefix`,
left behind by a killed fetch. Only removes directories older than
`max_age_seconds`. A per-date lock stops concurrent fetches for the same date,
but a fetch for another date can run at the same time, and the age guard keeps
its live download directory safe.
"""
function cleanup_stale_tmpdirs(dir, prefix; max_age_seconds = 86400)
    for name in readdir(dir)
        path = joinpath(dir, name)
        (startswith(name, prefix) && isdir(path)) || continue
        (time() - mtime(path)) > max_age_seconds || continue
        rm(path; recursive = true)
    end
    return nothing
end
