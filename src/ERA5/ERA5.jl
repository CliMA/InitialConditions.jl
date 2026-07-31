"""
    InitialConditions.ERA5

Initial conditions from ERA5 reanalysis, downloaded from the Copernicus
Climate Data Store (CDS).

[`fetch_initial_conditions`](@ref) runs the whole pipeline for a start date:
download, process, validate, cache. The `process_*` functions are public too,
so a caller that downloads ERA5 some other way can use the processing on its
own.

CDS credentials come from the `CDSAPI_URL` and `CDSAPI_KEY` environment
variables or from `~/.cdsapirc`. See
https://cds.climate.copernicus.eu/how-to-api.

The requests and the processing are ported from the private
[CliMA/WeatherQuest](https://github.com/CliMA/WeatherQuest) repository, which
builds the `wxquest_initial_conditions` artifact. Ported functions name their
WeatherQuest source in their docstring.
"""
module ERA5

import CDSAPI
import Dates
import FileWatching.Pidfile
import NCDatasets

import ..InitialConditions as IC
using ..InitialConditions:
    check_no_nan,
    check_present,
    clean_attributes,
    datestamp,
    define_lonlat_time!,
    find_dim,
    monthly_time_points,
    nearest_neighbor_fill,
    permute_along,
    read_lonlat,
    read_surface_field,
    reference_date,
    roll_longitudes,
    write_replicated_time_var!,
    zero_fill

export fetch_initial_conditions,
    cache_dir,
    credentials_available,
    files_complete,
    validate_dir,
    output_filenames,
    raw_filename,
    sst_filename,
    sic_filename,
    land_filename,
    bucket_filename,
    albedo_filename,
    build_raw,
    process_sst,
    process_sic,
    process_land,
    process_bucket,
    process_albedo

include("filenames.jl")
include("requests.jl")
include("download.jl")
include("soil.jl")
include("processing_ocean.jl")
include("processing_land.jl")
include("processing_atmos.jl")
include("validation.jl")
include("fetch.jl")

end # module ERA5
