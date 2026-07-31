# InitialConditions.jl

Downloads, processes, and caches the initial conditions that CliMA simulations
start from. Each data source is a submodule. Today there is one:

  - [`ERA5`](@ref era5): ERA5 reanalysis from the
    [Copernicus Climate Data Store](https://cds.climate.copernicus.eu) (CDS), for
    weather and subseasonal runs.

## [ERA5](@id era5)

For a start date, `ERA5` downloads the reanalysis, processes it into the NetCDF
files that ClimaCoupler, ClimaAtmos, and ClimaLand read, validates it, and
caches it. Later runs for the same date do not use the network.

One call does everything and returns the directory holding the six output files
for that date:

```julia
import InitialConditions.ERA5
import Dates

date = Dates.DateTime(2010, 1, 1)
dir = ERA5.fetch_initial_conditions(date)

ERA5.output_filenames(date)
# 6-element Vector{String}:
#  "era5_raw_20100101_0000.nc"
#  "sst_processed_20100101_0000.nc"
#  "sic_processed_20100101_0000.nc"
#  "era5_land_processed_20100101_0000.nc"
#  "era5_bucket_processed_20100101_0000.nc"
#  "albedo_processed_20100101_0000.nc"
```

Build a path with the matching helper rather than with `readdir`, since one
cache directory can hold many dates:

```julia
sst_path = joinpath(dir, ERA5.sst_filename(date))

import NCDatasets
NCDatasets.NCDataset(sst_path) do ds
    keys(ds)          # ("lon", "lat", "time", "SST")
    size(ds["SST"])   # (1440, 721, 4)
end
```

[Output files](@ref) says what each file holds and which model reads it. A run
normally does not touch these paths: ClimaCoupler resolves the directory and
hands the right file to each component model.

### Credentials

The CDS download needs a free CDS account:

 1. Register at [cds.climate.copernicus.eu](https://cds.climate.copernicus.eu)
    and accept the ERA5 licence ("Licence to use Copernicus Products").

 2. Create `~/.cdsapirc` with your personal access token, as described in the
    [CDS API instructions](https://cds.climate.copernicus.eu/how-to-api):

    ```
    url: https://cds.climate.copernicus.eu/api
    key: <your-personal-access-token>
    ```

    You can set the `CDSAPI_URL` and `CDSAPI_KEY` environment variables
    instead.

The Copernicus servers queue the requests. A download usually takes minutes,
but it can take hours when the queue is busy. Each date is about 1 to 2 GB.

### Running under MPI

`fetch_initial_conditions` knows nothing about MPI. Call it on the root
process only, then barrier and let the other processes confirm the files are
there:

```julia
if ClimaComms.iamroot(comms_ctx)
    ERA5.fetch_initial_conditions(start_date; dir)
end
ClimaComms.barrier(comms_ctx)
ERA5.files_complete(dir, start_date) ||
    error("the root process failed to fetch ERA5 initial conditions")
```

ClimaCoupler does this in `Input.resolve_era5_dir`, where it also decides
between an explicit directory, the `wxquest_initial_conditions` artifact, and a
download.

### Caching

The files go to a per-package
[Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) directory and stay
there across runs. Set the `INITIAL_CONDITIONS_CACHE_DIR` environment variable to use a
different directory, such as a shared cache on a cluster.

The download goes to a temporary directory, and the files only move into the
cache after validation. An interrupted run leaves no partial cache. To delete
and download a date again, pass `force = true` to
[`fetch_initial_conditions`](@ref InitialConditions.ERA5.fetch_initial_conditions).

A per-date lock file serializes concurrent fetches. When several simulations
share a cache directory and need the same date, one downloads and the others
wait, then reuse its files. A lock left by a killed process goes stale and
breaks after a timeout.

### Output files

For a start date `YYYYMMDD`, the package writes these files:

| File                                     | Holds                                                                                                          | Read by                                   |
|:---------------------------------------- |:-------------------------------------------------------------------------------------------------------------- |:----------------------------------------- |
| `era5_raw_YYYYMMDD_0000.nc`              | `u`, `v`, `w`, `t`, `q`, `z`, cloud condensate on 37 pressure levels, plus `skt`, `sp`, `surface_geopotential` | ClimaAtmos `WeatherModel`                 |
| `sst_processed_YYYYMMDD_0000.nc`         | `SST` in Celsius, land filled by nearest neighbor                                                              | prescribed ocean                          |
| `sic_processed_YYYYMMDD_0000.nc`         | `SEAICE` in percent, and `ISTL1` in Kelvin                                                                     | prescribed sea ice                        |
| `era5_land_processed_YYYYMMDD_0000.nc`   | `skt`, `tsn`, `swe`, `swvl`, `stl`, with 0 over ocean                                                          | ClimaLand integrated land                 |
| `era5_bucket_processed_YYYYMMDD_0000.nc` | `W`, `Ws`, `S`, `T`, `tsn`, `skt`                                                                              | bucket land                               |
| `albedo_processed_YYYYMMDD_0000.nc`      | `sw_alb_clr`, the ERA5 forecast albedo                                                                         | bucket, when `bucket_albedo_type: "era5"` |

ClimaAtmos interpolates the atmosphere state onto its own grid, including
vertically. That interpolation assumes the vertical coordinate increases, so the
levels run from the surface up: pressure decreases and altitude increases with
the level index. [`validate_dir`](@ref InitialConditions.ERA5.validate_dir) enforces it, because getting it
backwards produces a plausible file that silently initializes the whole column
from the model top.

The processing follows the [WeatherQuest](https://github.com/CliMA/WeatherQuest)
pipeline that produced the `wxquest_initial_conditions` artifact, with one
difference: the atmosphere state uses the 37 ERA5 pressure levels rather than
the 137 model levels.

### Testing

The default test suite replaces `CDSAPI.retrieve` with a fake that writes small
fixture files, so it makes no network requests and runs in seconds:

```
julia --project=test test/runtests.jl
```

To exercise the real CDS path, which needs credentials and can queue for hours:

```
ERA5_NETWORK_TESTS=true julia --project=test test/network_tests.jl
```

That test downloads a date, processes and validates it, checks the cache hit on
a second call, and asserts the preconditions ClimaAtmos relies on. Real CDS
output is the only thing that can break those, for example if CDS changes its
dimension names or its level order.

## API

### Fetching

```@docs
InitialConditions.ERA5.fetch_initial_conditions
InitialConditions.ERA5.cache_dir
InitialConditions.ERA5.credentials_available
InitialConditions.ERA5.files_complete
```

### Processing

Each of these reads one downloaded ERA5 file and writes one output file, and
returns the output path. They make no network requests, so a caller that
already has ERA5 downloads can use them on their own:

```julia
process_land("era5_land_20100101.nc", "era5_land_processed_20100101_0000.nc")
process_sst("era5_surface_20100101.nc", "sst_processed_20100101_0000.nc")
```

They read by variable name rather than by file layout, so they work whether the
surface, ocean, and land fields arrive in one file or several.

Two conventions are fixed rather than arguments. Soil depths come from the ERA5
layer midpoints `[0.035, 0.175, 0.64, 1.945]`, and the output is always
Float32. Both could become keywords later without a breaking release.

`build_raw` is the exception to the shape above: it merges two source files, the
pressure-level and single-level downloads, into the atmosphere state file.

```@docs
InitialConditions.ERA5.build_raw
InitialConditions.ERA5.process_sst
InitialConditions.ERA5.process_sic
InitialConditions.ERA5.process_land
InitialConditions.ERA5.process_bucket
InitialConditions.ERA5.process_albedo
```

### Validation and file names

```@docs
InitialConditions.ERA5.validate_dir
InitialConditions.ERA5.output_filenames
InitialConditions.ERA5.raw_filename
InitialConditions.ERA5.sst_filename
InitialConditions.ERA5.sic_filename
InitialConditions.ERA5.land_filename
InitialConditions.ERA5.bucket_filename
InitialConditions.ERA5.albedo_filename
```
