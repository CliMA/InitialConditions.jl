"""
    check_model_levels(ds, filename)

Check that the raw atmosphere file holds the whole 1 to 137 model-level column,
in that order.

MARS can answer a `1/to/137` request with level 1 alone, which WeatherQuest
`download_model_level_data` warns about. The result is a plausible file that
would initialize the model from a single level near the model top.
"""
function check_model_levels(ds, filename)
    levels = Array(ds["model_level"])
    levels == collect(1:N_MODEL_LEVELS) || error(
        "model_level in $filename holds $(length(levels)) levels running " *
        "$(isempty(levels) ? "nothing" : "$(first(levels)) to $(last(levels))"), " *
        "rather than the full 1 to $(N_MODEL_LEVELS). MARS can truncate a " *
        "`1/to/$(N_MODEL_LEVELS)` request to its first level.",
    )
    return nothing
end

function validate_raw(ds, filename)
    for dim in ("longitude", "latitude", "model_level", "valid_time")
        haskey(ds.dim, dim) || error("Missing dimension $dim in $filename")
    end
    check_present(ds, ["w"], filename)
    check_no_nan(ds, ["u", "v", "t", "q", "skt", "sp", "surface_geopotential"], filename)
    check_model_levels(ds, filename)
    return nothing
end

function validate_sst(ds, filename)
    check_no_nan(ds, ["SST"], filename)
    sst = Array(ds["SST"])
    (minimum(sst) > -60 && maximum(sst) < 60) ||
        error("SST in $filename is outside the plausible range in Celsius")
    return nothing
end

function validate_sic(ds, filename)
    check_no_nan(ds, ["SEAICE", "ISTL1"], filename)
    sic = Array(ds["SEAICE"])
    (minimum(sic) >= 0 && maximum(sic) <= 100) ||
        error("SEAICE in $filename is outside [0, 100] percent")
    return nothing
end

function validate_land(ds, filename)
    check_no_nan(ds, ["skt", "tsn", "swe", "swvl", "stl"], filename)
    stl = Array(ds["stl"])
    all(x -> x == 0 || x > 100, stl) || error(
        "stl in $filename has values that are neither 0 (ocean) nor a " *
        "plausible temperature in Kelvin",
    )
    return nothing
end

function validate_bucket(ds, filename)
    check_present(ds, ["tsn", "skt"], filename)
    check_no_nan(ds, ["W", "Ws", "S", "T"], filename)
    T = Array(ds["T"])
    minimum(T) > 100 || error("Bucket T in $filename has implausibly cold values")
    return nothing
end

function validate_albedo(ds, filename)
    check_no_nan(ds, ["sw_alb_clr"], filename)
    albedo = Array(ds["sw_alb_clr"])
    (minimum(albedo) >= 0 && maximum(albedo) <= 1) ||
        error("sw_alb_clr in $filename is outside [0, 1]")
    return nothing
end

"""
    validate_dir(dir, date)

Check that `dir` holds a complete and correct set of ERA5 initial condition
files for `date`. Errors on the first problem found.
"""
function validate_dir(dir, date)
    checks = (
        (raw_filename(date), validate_raw),
        (sst_filename(date), validate_sst),
        (sic_filename(date), validate_sic),
        (land_filename(date), validate_land),
        (bucket_filename(date), validate_bucket),
        (albedo_filename(date), validate_albedo),
    )
    for (filename, validate) in checks
        path = joinpath(dir, filename)
        isfile(path) || error("Missing ERA5 initial condition file $path")
        NCDatasets.NCDataset(ds -> validate(ds, filename), path)
    end
    return nothing
end
