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

The model-level state comes from
[`reanalysis-era5-complete`](https://cds.climate.copernicus.eu/datasets/reanalysis-era5-complete),
which has a licence of its own to accept alongside the ERA5 one.

The Copernicus servers queue the requests. A download usually takes minutes,
but it can take hours when the queue is busy. A date is roughly 4 GB, most of
it the seven model-level fields on 137 levels.

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

For a start time `YYYYMMDD_HHMM`, the package writes these files. ERA5 is
archived hourly, so the start time has to land on the hour; `00:00` is the
usual one and the only one the ClimaCoupler and ClimaAtmos path lookups accept
today.

| File                                     | Holds                                                                                                          | Read by                                   |
|:---------------------------------------- |:-------------------------------------------------------------------------------------------------------------- |:----------------------------------------- |
| `era5_raw_YYYYMMDD_HHMM.nc`              | `u`, `v`, `w`, `t`, `q`, `clwc`, `ciwc` on the 137 ERA5 model levels, plus `skt`, `sp`, `surface_geopotential` | WeatherQuest `to_z_levels_3d_model`       |
| `sst_processed_YYYYMMDD_HHMM.nc`         | `SST` in Celsius, land filled by nearest neighbor                                                              | prescribed ocean                          |
| `sic_processed_YYYYMMDD_HHMM.nc`         | `SEAICE` in percent, and `ISTL1` in Kelvin                                                                     | prescribed sea ice                        |
| `era5_land_processed_YYYYMMDD_HHMM.nc`   | `skt`, `tsn`, `swe`, `swvl`, `stl`, with 0 over ocean                                                          | ClimaLand integrated land                 |
| `era5_bucket_processed_YYYYMMDD_HHMM.nc` | `W`, `Ws`, `S`, `T`, `tsn`, `skt`                                                                              | bucket land                               |
| `albedo_processed_YYYYMMDD_HHMM.nc`      | `sw_alb_clr`, the ERA5 forecast albedo                                                                         | bucket, when `bucket_albedo_type: "era5"` |

The atmosphere state comes from `reanalysis-era5-complete`, the MARS archive,
on the 137 native model levels. Levels keep the order MARS delivers them, level
1 at the model top and level 137 at the surface; `to_z_levels_3d_model` reads
that order off the `model_level` coordinate and flips it itself, and the hybrid
coefficients that turn levels into pressures are indexed by level number.

Run WeatherQuest `processing/preprocessing.jl --groups atmos` over the cache
directory to turn the raw file into the `era5_init_processed_internal_*.nc`
that ClimaAtmos reads. That is the only atmosphere path WeatherQuest has:
`to_z_levels_3d_model` takes model levels and rejects pressure levels.
Everything it needs is in the raw file except the L137 hybrid `a`/`b`
coefficients, which `read_hybrid_coeffs` takes from its bundled
`processing/l137_hybrid_ab.txt`.

ClimaAtmos cannot read the raw file on its own. `weather_model_data_path` falls
back to `to_z_levels_1d` when no processed file is present, and that fallback
asserts a `pressure_level` dimension, so WeatherQuest has to run in between.

!!! note "The atmosphere stops one step short"

    Every other output here is the file a component model reads. The
    atmosphere is not: it stops at `era5_raw_*.nc`, one step before the
    `era5_init_processed_internal_*.nc` that ClimaAtmos opens. Closing the gap
    means porting `to_z_levels_3d_model`, which reconstructs pressure from the
    IFS hybrid coefficients, integrates geopotential hydrostatically, and
    interpolates each column onto the target grid. That is a much larger job
    than the rest of the processing here, so it is left for a follow-up.

MARS can answer a `1/to/137` request with level 1 alone.
[`validate_dir`](@ref InitialConditions.ERA5.validate_dir) rejects that, because
the truncated file is otherwise plausible and would initialize the whole column
from a single level near the model top.

### Differences from WeatherQuest

The processing follows the [WeatherQuest](https://github.com/CliMA/WeatherQuest)
pipeline that produced the `wxquest_initial_conditions` artifact, and
WeatherQuest `processing/preprocessing.jl` now calls these `process_*` functions
rather than its own copies. The remaining differences are deliberate:

  - The model-level state takes one MARS request, not two. WeatherQuest asks
    separately for `z` and `lnsp`, which are archived on level 1 alone, and
    merges them in. They hold the same surface geopotential and surface
    pressure that the single-level request already supplies as
    `surface_geopotential` and `sp`, which is what `to_z_levels_3d_model`
    reads, so the second request is dropped. Neither `crwc` nor `cswc` is
    requested, matching `MODEL_LEVEL_PARAM_IDS_FULL`.

  - The files hold only the variables a consumer reads. Dropped, with the
    consumer checked in each case: `si` and `sie` from the land file, which
    ClimaLand derives from `swvl` and `stl`; `lai`, which ClimaLand takes from
    MODIS; `ISTL2` to `ISTL4`, since the prescribed sea ice model reads only
    `ISTL1`; and `fsr` and `flsr` from the albedo file. The raw atmosphere file
    carries the model-level fields plus `skt`, `sp`, and
    `surface_geopotential`, rather than everything both downloads contain.

  - One single-level request covers the surface, ocean, and land fields, where
    WeatherQuest splits them across a `surface` and a `land` request. Every
    variable requested is an instantaneous field, so CDS answers with one
    NetCDF file rather than a zip archive of one file per step type.

  - `subsurface_water_z_max` defaults to 0.5 m, which is what the WeatherQuest
    `--subsurface-water-z-max` flag defaults to, not the 1.0 m default of its
    `interpolate_bucket`.

### Testing

The default test suite replaces `CDSAPI.retrieve` with a fake that writes small
fixture files, so it makes no network requests and runs in seconds:

```
julia --project -e 'using Pkg; Pkg.test()'
```

The network tests skip themselves unless you ask for them. They need CDS
credentials, and a CDS request can queue for hours:

```
ERA5_NETWORK_TESTS=true julia --project -e 'using Pkg; Pkg.test()'
```

They download a date, process and validate it, check the cache hit on a second
call, and assert the preconditions the model-level preprocessing relies on.
Real CDS output is the only thing that can break those, for example if CDS
changes its dimension names or its level order.

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
model-level and single-level downloads, into the atmosphere state file.

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
