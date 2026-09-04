"""
    cache_dir()

The directory that holds the cached ERA5 initial conditions, an `era5`
subdirectory of the `InitialConditions` cache root.
"""
cache_dir() = IC.cache_dir("era5")

"""
    files_complete(dir, date)

Whether the cache at `dir` holds all the output files for `date`. Files only
move into the cache after validation, so their presence means the set is
complete.
"""
function files_complete(dir, date)
    return all(name -> isfile(joinpath(dir, name)), output_filenames(date))
end

function remove_cached_files(dir, date)
    for name in output_filenames(date)
        path = joinpath(dir, name)
        isfile(path) && rm(path)
    end
    return nothing
end

"""
    fetch_initial_conditions(start_date; dir, force, retrieve_fn, wait)

A directory that holds the complete set of ERA5 initial condition files for
`start_date`. Downloads and processes the files from the CDS API if the cache
does not have them.

# Arguments

  - `start_date`: the simulation start time, a `Date` or a `DateTime`. ERA5 is
    archived hourly, so it has to land on the hour. The file names stamp it as
    `YYYYMMDD_HHMM`, so `DateTime(2010, 1, 1)` gives `..._20100101_0000.nc` and
    `DateTime(2010, 1, 1, 6)` gives `..._20100101_0600.nc`.
  - `dir`: the cache directory, [`cache_dir`](@ref) by default.
  - `force`: delete the cached files for this date and fetch them again.
  - `retrieve_fn`: the retrieval function, `CDSAPI.retrieve` by default. Tests
    replace it with a fake.
  - `wait`: the seconds between CDS job status checks.

The download goes to a temporary directory inside `dir`, and the files only
move into place after validation. An interrupted fetch leaves no partial
cache. A per-date lock file makes concurrent fetches take turns: processes
that share a cache directory download once, and the others wait, then reuse
the result.

This function knows nothing about MPI. Under MPI, call it on the root process
only, then barrier and check [`files_complete`](@ref) on the others.
"""
function fetch_initial_conditions(
    start_date;
    dir = cache_dir(),
    force = false,
    retrieve_fn = CDSAPI.retrieve,
    wait = 30.0,
)
    date = Dates.DateTime(start_date)
    date == Dates.floor(date, Dates.Hour) || error(
        "ERA5 is archived hourly, so start_date has to land on the hour, got " *
        "$(start_date)",
    )
    mkpath(dir)
    if !force && files_complete(dir, date)
        @info "Using cached ERA5 initial conditions" dir date
        return dir
    end
    # One writer per cache and date: concurrent fetches wait here, then find
    # the finished files and skip the download. The holder refreshes the lock
    # file while alive, and a lock left by a killed process goes stale after
    # `LOCK_STALE_AGE` seconds.
    Pidfile.mkpidlock(joinpath(dir, lock_filename(date)); stale_age = LOCK_STALE_AGE) do
        download_and_cache(date, dir; force, retrieve_fn, wait)
    end
    return dir
end

"""
    cleanup_tmpdirs(dir, date)

Remove the download directories under `dir` that no fetch is using, left behind
by killed fetches.

The ones for `date` go unconditionally, because the caller holds that date's
lock and so is the only process that could have a live one. The ones for
another date go only if that date's lock is free, which means no fetch is
running for it.

Age is not a safe test in its place. A directory waiting on a CDS queue keeps
the modification time it was created with, since nothing writes into it until
the download lands, so a queue longer than the cutoff would make a live
directory look abandoned.
"""
function cleanup_tmpdirs(dir, date)
    own = tmpdir_prefix(date)
    for name in readdir(dir)
        path = joinpath(dir, name)
        (startswith(name, TMPDIR_PREFIX) && isdir(path)) || continue
        if startswith(name, own)
            rm(path; recursive = true)
            continue
        end
        other = tmpdir_date(name)
        isnothing(other) && continue
        # Returns false without waiting when a fetch for `other` holds the lock
        Pidfile.trymkpidlock(
            joinpath(dir, lock_filename(other));
            stale_age = LOCK_STALE_AGE,
        ) do
            rm(path; recursive = true)
        end
    end
    return nothing
end

"""
    download_and_cache(date, dir; force, retrieve_fn, wait)

Download, process, validate, and move the files for `date` into the cache at
`dir`. Call this only while holding the per-date lock.
"""
function download_and_cache(date, dir; force, retrieve_fn, wait)
    force && remove_cached_files(dir, date)
    if files_complete(dir, date)
        @info "Using cached ERA5 initial conditions" dir date
        return nothing
    end
    # A fake retrieve_fn needs no credentials
    retrieve_fn === CDSAPI.retrieve && assert_credentials()
    cleanup_tmpdirs(dir, date)
    mktempdir(dir; prefix = tmpdir_prefix(date)) do tmpdir
        files = download_source_files(date, tmpdir; retrieve_fn, wait)
        @info "Preprocessing ERA5 initial conditions" date
        build_raw(files.model, files.surface, joinpath(tmpdir, raw_filename(date)))
        process_sst(files.surface, joinpath(tmpdir, sst_filename(date)); date)
        process_sic(files.surface, joinpath(tmpdir, sic_filename(date)); date)
        process_land(files.surface, joinpath(tmpdir, land_filename(date)))
        process_bucket(files.surface, joinpath(tmpdir, bucket_filename(date)))
        process_albedo(files.surface, joinpath(tmpdir, albedo_filename(date)); date)
        validate_dir(tmpdir, date)
        for name in output_filenames(date)
            mv(joinpath(tmpdir, name), joinpath(dir, name); force = true)
        end
    end
    @info "ERA5 initial conditions ready" dir date
    return nothing
end
