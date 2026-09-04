"""
The number of ERA5 model levels. Level 1 is the model top and level 137 sits at
the surface.
"""
const N_MODEL_LEVELS = 137

"""
MARS parameter IDs for the model-level atmosphere state, as
(parameter id => NetCDF short name). From `MODEL_LEVEL_PARAM_IDS_FULL` in
WeatherQuest `era5_variables.py`. Rain and snow water content, `75` and `76`,
are archived on model levels too, but WeatherQuest does not request them.
See https://www.ecmwf.int/en/forecasts/datasets/set-i.
"""
const MODEL_LEVEL_PARAMS = [
    "130" => "t",
    "131" => "u",
    "132" => "v",
    "133" => "q",
    "135" => "w",
    "246" => "clwc",
    "247" => "ciwc",
]

"""
    model_levels_request(date)

The request for the model-level atmosphere state.

`reanalysis-era5-complete` is a MARS dataset, so the request takes
`levtype`, `levelist`, and `param` rather than the `variable` and
`pressure_level` of the ordinary ERA5 datasets, a date without separators, and
a two digit hour. Port of `download_model_level_data` in WeatherQuest
`get_initial_conditions.py`.

Asks for the levels as `1/to/137` rather than as an explicit list, because
WeatherQuest found that a long explicit list can come back truncated to its
first level alone. Validation catches that if it happens anyway.

`surface_pressure` and `geopotential` come from the single-level request rather
than from the model-level `lnsp` and level-1 `z`, which hold the same two
fields. That leaves one MARS request instead of two: `z` and `lnsp` are
archived only on level 1, so asking for them alongside `1/to/137` collapses the
whole response to level 1 and they need a request of their own.
"""
function model_levels_request(date)
    return Dict{String, Any}(
        "stream" => "oper",
        "type" => "an",
        "expver" => "1",
        "levtype" => "ml",
        "levelist" => "1/to/$(N_MODEL_LEVELS)",
        "param" => join(first.(MODEL_LEVEL_PARAMS), "/"),
        "date" => Dates.format(date, "yyyymmdd"),
        "time" => Dates.format(date, "HH"),
        "area" => [90, -180, -90, 180],
        # CDS needs an explicit regular lat/lon grid to answer MARS in NetCDF
        "grid" => "0.25/0.25",
        "data_format" => "netcdf",
    )
end

"""
Single-level variables, as (CDS request name => NetCDF short name). These all
come from the `reanalysis-era5-single-levels` dataset, not from ERA5-Land.
One request covers the surface, ocean, and land fields. A subset of the
WeatherQuest `era5_variables.py` sets: this module requests only the variables
that a consumer reads.
"""
const SINGLE_LEVEL_VARIABLES = [
    # Atmosphere surface state, for the raw atmosphere file
    "surface_pressure" => "sp",
    "skin_temperature" => "skt",
    "geopotential" => "z",
    # Ocean and sea ice. ISTL1 is the near-surface layer that the prescribed
    # sea ice model uses as a surface temperature proxy.
    "sea_surface_temperature" => "sst",
    "sea_ice_cover" => "siconc",
    "ice_temperature_layer_1" => "istl1",
    # Land
    "volumetric_soil_water_layer_1" => "swvl1",
    "volumetric_soil_water_layer_2" => "swvl2",
    "volumetric_soil_water_layer_3" => "swvl3",
    "volumetric_soil_water_layer_4" => "swvl4",
    "soil_temperature_level_1" => "stl1",
    "soil_temperature_level_2" => "stl2",
    "soil_temperature_level_3" => "stl3",
    "soil_temperature_level_4" => "stl4",
    "snow_depth" => "sd",
    "temperature_of_snow_layer" => "tsn",
    "skin_reservoir_content" => "src",
    "forecast_albedo" => "fal",
]

function base_request(date)
    return Dict{String, Any}(
        "product_type" => ["reanalysis"],
        "year" => Dates.format(date, "yyyy"),
        "month" => Dates.format(date, "mm"),
        "day" => Dates.format(date, "dd"),
        "time" => Dates.format(date, "HH:MM"),
        "area" => [90, -180, -90, 180],
        "data_format" => "netcdf",
    )
end

function single_levels_request(date)
    request = base_request(date)
    request["variable"] = first.(SINGLE_LEVEL_VARIABLES)
    return request
end

# ============================================================================
# Credentials
# ============================================================================

"""
    credentials_available()

Whether CDS credentials are available, either from the `CDSAPI_URL` and
`CDSAPI_KEY` environment variables or from `~/.cdsapirc`.
"""
function credentials_available()
    haskey(ENV, "CDSAPI_URL") && haskey(ENV, "CDSAPI_KEY") && return true
    return isfile(joinpath(homedir(), ".cdsapirc"))
end

function assert_credentials()
    credentials_available() && return nothing
    error(
        "No CDS credentials found. Register at " *
        "https://cds.climate.copernicus.eu, accept the ERA5 licence, and " *
        "either create ~/.cdsapirc or set the CDSAPI_URL and CDSAPI_KEY " *
        "environment variables. See " *
        "https://cds.climate.copernicus.eu/how-to-api for instructions. The " *
        "model-level atmosphere state comes from the ERA5-complete dataset, " *
        "which has a licence of its own to accept at " *
        "https://cds.climate.copernicus.eu/datasets/reanalysis-era5-complete.",
    )
end
