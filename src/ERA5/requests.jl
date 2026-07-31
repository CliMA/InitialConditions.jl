#! format: off
"""
The 37 ERA5 pressure levels, in hPa.
"""
const PRESSURE_LEVELS = [
    "1", "2", "3", "5", "7", "10", "20", "30", "50", "70",
    "100", "125", "150", "175", "200", "225", "250", "300", "350", "400",
    "450", "500", "550", "600", "650", "700", "750", "775", "800", "825",
    "850", "875", "900", "925", "950", "975", "1000",
]
#! format: on

"""
Pressure-level variables for the atmosphere initial condition, as
(CDS request name => NetCDF short name). From WeatherQuest
`era5_variables.py`.
"""
const PRESSURE_LEVEL_VARIABLES = [
    "geopotential" => "z",
    "temperature" => "t",
    "specific_humidity" => "q",
    "u_component_of_wind" => "u",
    "v_component_of_wind" => "v",
    "vertical_velocity" => "w",
    "specific_cloud_liquid_water_content" => "clwc",
    "specific_cloud_ice_water_content" => "ciwc",
    "specific_rain_water_content" => "crwc",
    "specific_snow_water_content" => "cswc",
]

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
        "time" => "00:00",
        "area" => [90, -180, -90, 180],
        "data_format" => "netcdf",
    )
end

function pressure_levels_request(date)
    request = base_request(date)
    request["variable"] = first.(PRESSURE_LEVEL_VARIABLES)
    request["pressure_level"] = PRESSURE_LEVELS
    return request
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
        "https://cds.climate.copernicus.eu/how-to-api for instructions.",
    )
end
