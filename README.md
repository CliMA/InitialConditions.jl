# InitialConditions.jl

[![CI](https://github.com/CliMA/InitialConditions.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/CliMA/InitialConditions.jl/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs_are_here-click_me%21-blue.svg)](https://clima.github.io/InitialConditions.jl/dev/)

Downloads, processes, and caches the initial conditions that CliMA simulations
start from. Each data source is a submodule. Today there is one, `ERA5`, which
serves weather and subseasonal runs.

For a start date, this package downloads ERA5 data from the
[Copernicus Climate Data Store](https://cds.climate.copernicus.eu) (CDS) and
writes the NetCDF files that ClimaCoupler, ClimaAtmos, and ClimaLand read:

| File                                     | Contents                           |
|:---------------------------------------- |:---------------------------------- |
| `era5_raw_YYYYMMDD_0000.nc`              | model-level atmosphere state       |
| `sst_processed_YYYYMMDD_0000.nc`         | sea surface temperature, Celsius   |
| `sic_processed_YYYYMMDD_0000.nc`         | sea ice concentration, percent     |
| `era5_land_processed_YYYYMMDD_0000.nc`   | integrated land initial conditions |
| `era5_bucket_processed_YYYYMMDD_0000.nc` | bucket land initial conditions     |
| `albedo_processed_YYYYMMDD_0000.nc`      | surface albedo                     |

## Usage

```julia
import InitialConditions.ERA5
import Dates

dir = ERA5.fetch_initial_conditions(Dates.DateTime(2010, 1, 1))
```

The files are cached, so later calls for the same date make no network
requests. Set `INITIAL_CONDITIONS_CACHE_DIR` to cache somewhere other than the default
Scratch.jl directory, for example a shared directory on a cluster. A per-date
lock file lets several processes share one cache safely.

The `process_*` functions are public as well, so a caller that already has ERA5
downloads can use the processing without touching the network.

## Credentials

The download needs a free CDS account. Register at
[cds.climate.copernicus.eu](https://cds.climate.copernicus.eu), accept the ERA5
licence, and create `~/.cdsapirc` as described in the
[CDS API instructions](https://cds.climate.copernicus.eu/how-to-api). You can
set `CDSAPI_URL` and `CDSAPI_KEY` instead.

## Provenance

The requests and the processing are ported from the private
[CliMA/WeatherQuest](https://github.com/CliMA/WeatherQuest) repository, which
builds the `wxquest_initial_conditions` artifact. Ported functions name their
WeatherQuest source in their docstring, and WeatherQuest
`processing/preprocessing.jl` now calls the `process_*` functions here rather
than its own copies. The differences that remain are deliberate: the
model-level state takes one MARS request rather than two, and the files hold
only the variables that a consumer reads. The
[documentation](https://clima.github.io/InitialConditions.jl/dev/) lists them.

The atmosphere state is on the 137 native model levels, from the
`reanalysis-era5-complete` MARS archive, which has a licence of its own to
accept. Run WeatherQuest `processing/preprocessing.jl --groups atmos` over the
cache to turn it into the `era5_init_processed_internal_*.nc` that ClimaAtmos
reads; ClimaAtmos cannot read the raw file on its own.
