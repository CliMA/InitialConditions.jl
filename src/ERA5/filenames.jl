"""
The name of the model-level atmosphere state file for `date`.
"""
raw_filename(date) = "era5_raw_$(datestamp(date))_0000.nc"

"""
The name of the sea surface temperature file for `date`.
"""
sst_filename(date) = "sst_processed_$(datestamp(date))_0000.nc"

"""
The name of the sea ice file for `date`.
"""
sic_filename(date) = "sic_processed_$(datestamp(date))_0000.nc"

"""
The name of the integrated-land initial condition file for `date`.
"""
land_filename(date) = "era5_land_processed_$(datestamp(date))_0000.nc"

"""
The name of the bucket initial condition file for `date`.
"""
bucket_filename(date) = "era5_bucket_processed_$(datestamp(date))_0000.nc"

"""
The name of the albedo file for `date`.
"""
albedo_filename(date) = "albedo_processed_$(datestamp(date))_0000.nc"

lock_filename(date) = "era5_ic_$(datestamp(date)).lock"

"""
The prefix of the temporary download directories a fetch creates.
"""
const TMPDIR_PREFIX = "tmp_era5_"

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
