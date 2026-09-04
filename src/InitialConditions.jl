"""
    InitialConditions

Download, process, and cache initial conditions for CliMA simulations.

Each data source is a submodule. Today there is one:

  - `InitialConditions.ERA5`: ERA5 reanalysis from the Copernicus Climate Data
    Store, for weather and subseasonal runs.

```julia
import InitialConditions.ERA5
import Dates

dir = ERA5.fetch_initial_conditions(Dates.DateTime(2010, 1, 1))
```

Files are cached in a Scratch.jl directory, one subdirectory per source, so
later runs for the same date do not use the network. Set
`INITIAL_CONDITIONS_CACHE_DIR` to cache somewhere else, for example a shared
directory on a cluster.

The top level holds what a source needs but does not own: the cache layout,
NetCDF reading and writing helpers, gap filling, and validation helpers. These
are internal for now. A second source will show which of them belong in a
public shared API.
"""
module InitialConditions

import Dates
import FileWatching.Pidfile
import NCDatasets
import Scratch

export ERA5

# Shared internals, used by the source submodules
include("cache.jl")
include("netcdf.jl")
include("fields.jl")
include("checks.jl")

# Data sources
include("ERA5/ERA5.jl")

end # module InitialConditions
