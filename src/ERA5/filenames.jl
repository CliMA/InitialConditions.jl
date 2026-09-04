"""
The name of the model-level atmosphere state file for `date`.
"""
raw_filename(date) = "era5_raw_$(datetimestamp(date)).nc"

"""
The name of the sea surface temperature file for `date`.
"""
sst_filename(date) = "sst_processed_$(datetimestamp(date)).nc"

"""
The name of the sea ice file for `date`.
"""
sic_filename(date) = "sic_processed_$(datetimestamp(date)).nc"

"""
The name of the integrated-land initial condition file for `date`.
"""
land_filename(date) = "era5_land_processed_$(datetimestamp(date)).nc"

"""
The name of the bucket initial condition file for `date`.
"""
bucket_filename(date) = "era5_bucket_processed_$(datetimestamp(date)).nc"

"""
The name of the albedo file for `date`.
"""
albedo_filename(date) = "albedo_processed_$(datetimestamp(date)).nc"

lock_filename(date) = "era5_ic_$(datetimestamp(date)).lock"

"""
The seconds after which a lock left by a killed process counts as abandoned.
"""
const LOCK_STALE_AGE = 600.0

"""
The prefix that every temporary download directory shares.
"""
const TMPDIR_PREFIX = "tmp_era5_"

"""
    tmpdir_prefix(date)

The prefix of the temporary download directories a fetch for `date` creates.
The date is in the name so that `cleanup_tmpdirs` can tell whose a leftover
directory is.
"""
tmpdir_prefix(date) = "$(TMPDIR_PREFIX)$(datetimestamp(date))_"

const TMPDIR_PATTERN = Regex("^$(TMPDIR_PREFIX)(\\d{8}_\\d{4})_")

"""
    tmpdir_date(name)

The date that the download directory `name` belongs to, or `nothing` when the
name carries no readable one.
"""
function tmpdir_date(name)
    matched = match(TMPDIR_PATTERN, name)
    isnothing(matched) && return nothing
    return tryparse(Dates.DateTime, matched[1], Dates.dateformat"yyyymmdd_HHMM")
end

"""
The names of all six output files for `date`.
"""
output_filenames(date) = [
    raw_filename(date),
    sst_filename(date),
    sic_filename(date),
    land_filename(date),
    bucket_filename(date),
    albedo_filename(date),
]
