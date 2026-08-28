import Test: @test, @testset, @test_throws
import Dates
import NCDatasets
import InitialConditions as IC
import InitialConditions.ERA5

const TEST_DATE = Dates.DateTime(2024, 3, 15)
const NLON = 8
const NLAT = 5
# The full ERA5 model-level column, because `check_model_levels` demands it
const NLEVELS = 137

# Longitudes as CDS delivers them for area [90, -180, -90, 180]
const TEST_LON = collect(range(-180.0, 135.0, length = NLON))
# Latitudes decreasing, as in ERA5 files
const TEST_LAT = collect(range(90.0, -90.0, length = NLAT))
# Model levels as CDS delivers them: 1 at the model top, 137 at the surface
const TEST_MODEL_LEVELS = collect(1:NLEVELS)

# The land mask for the fixtures: the first three longitudes are land
is_land(i, j) = i <= 3
is_ocean(i, j) = !is_land(i, j)

# CDS adds an `expver` dimension for a date inside the ERA5T window. Index 1 is
# final ERA5, which has no data there, and the last index is ERA5T.
const NEXPVER = 2

"""
Define the longitude, latitude, and valid_time coordinates that every CDS
download carries.
"""
function define_fake_coords!(ds)
    NCDatasets.defDim(ds, "longitude", NLON)
    NCDatasets.defDim(ds, "latitude", NLAT)
    NCDatasets.defDim(ds, "valid_time", 1)
    NCDatasets.defVar(ds, "longitude", TEST_LON, ("longitude",))
    NCDatasets.defVar(ds, "latitude", TEST_LAT, ("latitude",))
    NCDatasets.defVar(ds, "valid_time", [TEST_DATE], ("valid_time",))
    return nothing
end

"""
    fake_var_writer(ds, dims, expver)

Define the `expver` dimension on `ds` when `expver`, and return the function
that writes one field of the fixture on `dims`. With `expver` the field goes
into the last slice of that dimension and the rest is missing, which is how CDS
delivers a date inside the ERA5T window.
"""
function fake_var_writer(ds, dims, expver)
    if expver
        NCDatasets.defDim(ds, "expver", NEXPVER)
        NCDatasets.defVar(ds, "expver", collect(1:NEXPVER), ("expver",))
        dims = (dims..., "expver")
    end
    return function (name, field)
        if expver
            padded = Array{Union{Missing, Float64}}(missing, size(field)..., NEXPVER)
            selectdim(padded, ndims(padded), NEXPVER) .= field
            field = padded
        end
        return NCDatasets.defVar(ds, name, field, dims; fillvalue = -9.0e33)
    end
end

"""
Write a fake CDS model-levels download. With `expver = true` it carries the
extra `expver` dimension that CDS adds inside the ERA5T window. `levels`
overrides the model-level coordinate, to stand in for a truncated MARS
response.
"""
function write_fake_model_file(path; expver = false, levels = TEST_MODEL_LEVELS)
    NCDatasets.NCDataset(path, "c") do ds
        define_fake_coords!(ds)
        NCDatasets.defDim(ds, "model_level", length(levels))
        NCDatasets.defVar(ds, "model_level", levels, ("model_level",))
        dims = ("longitude", "latitude", "model_level", "valid_time")
        write_var! = fake_var_writer(ds, dims, expver)

        for (name, value) in (
            ("t", 280.0),
            ("q", 0.005),
            ("u", 10.0),
            ("v", -5.0),
            ("w", 0.1),
            ("clwc", 1.0e-5),
            ("ciwc", 1.0e-6),
        )
            write_var!(name, fill(value, NLON, NLAT, length(levels), 1))
        end
    end
    return path
end

"""
Write a fake CDS single-levels download. The ocean fields `sst`, `siconc`,
and `istl1` are missing over land. The soil fields are missing over ocean.
With `expver = true` it carries the extra `expver` dimension.
"""
function write_fake_surface_file(path; expver = false)
    NCDatasets.NCDataset(path, "c") do ds
        define_fake_coords!(ds)
        write_var! = fake_var_writer(ds, ("longitude", "latitude", "valid_time"), expver)

        for (name, value) in (("skt", 285.0), ("sp", 1.0e5), ("z", 100.0), ("fal", 0.2))
            write_var!(name, fill(value, NLON, NLAT, 1))
        end
        ocean_only = (("sst", 290.0), ("siconc", 0.5), ("istl1", 271.0))
        land_only = (
            ("swvl1", 0.3),
            ("swvl2", 0.32),
            ("swvl3", 0.34),
            ("swvl4", 0.36),
            ("stl1", 272.0),
            ("stl2", 281.0),
            ("stl3", 282.0),
            ("stl4", 283.0),
            ("sd", 0.1),
            ("src", 0.001),
            ("tsn", 265.0),
        )
        for (masked, fields) in ((is_land, ocean_only), (is_ocean, land_only))
            for (name, value) in fields
                write_var!(
                    name,
                    [masked(i, j) ? missing : value for i in 1:NLON, j in 1:NLAT, _ in 1:1],
                )
            end
        end
    end
    return path
end

"""
A fake `CDSAPI.retrieve` that writes fixture files instead of using the
network. Records the requests it receives.
"""
function make_fake_retrieve(recorded)
    return function (dataset, request, path; wait = 1.0)
        push!(recorded, (dataset, request))
        if haskey(request, "levelist")
            write_fake_model_file(path)
        else
            write_fake_surface_file(path)
        end
        return path
    end
end

@testset "filenames and cache bookkeeping" begin
    @test ERA5.raw_filename(TEST_DATE) == "era5_raw_20240315_0000.nc"
    @test ERA5.sst_filename(TEST_DATE) == "sst_processed_20240315_0000.nc"
    @test ERA5.sic_filename(TEST_DATE) == "sic_processed_20240315_0000.nc"
    @test ERA5.land_filename(TEST_DATE) == "era5_land_processed_20240315_0000.nc"
    @test ERA5.bucket_filename(TEST_DATE) == "era5_bucket_processed_20240315_0000.nc"
    @test ERA5.albedo_filename(TEST_DATE) == "albedo_processed_20240315_0000.nc"
    @test length(ERA5.output_filenames(TEST_DATE)) == 6
end

@testset "field helpers" begin
    field = Union{Missing, Float64}[1.0 missing; missing 4.0]
    filled = IC.nearest_neighbor_fill(field)
    @test !any(isnan, filled)
    @test filled[1, 1] == 1.0
    @test filled[2, 2] == 4.0

    @test IC.zero_fill(field) == [1.0 0.0; 0.0 4.0]

    lon360, perm = IC.roll_longitudes([-180.0, -90.0, 0.0, 90.0])
    @test lon360 == [0.0, 90.0, 180.0, 270.0]
    @test perm == [3, 4, 1, 2]

    points = IC.monthly_time_points(Dates.DateTime(2024, 3, 15))
    @test length(points) == 4
    @test points[2] == Dates.value(
        Dates.Second(Dates.DateTime(2024, 3, 15) - Dates.DateTime(1970, 1, 1)),
    )
    @test issorted(points)
end

@testset "requests" begin
    # A MARS request, so `param`/`levelist` rather than `variable`
    request = ERA5.model_levels_request(TEST_DATE)
    @test request["date"] == "20240315"
    @test request["time"] == "00"
    @test request["levtype"] == "ml"
    @test request["levelist"] == "1/to/137"
    @test request["data_format"] == "netcdf"
    # t, u, v, q, w, clwc, ciwc
    @test request["param"] == "130/131/132/133/135/246/247"

    surface = ERA5.single_levels_request(TEST_DATE)
    @test "sea_surface_temperature" in surface["variable"]
    @test "sea_ice_cover" in surface["variable"]
    @test "volumetric_soil_water_layer_1" in surface["variable"]
    @test "forecast_albedo" in surface["variable"]
    @test allunique(surface["variable"])
    # Every requested variable has a consumer, so nothing unused is downloaded
    @test !("2m_temperature" in surface["variable"])
    @test !("ice_temperature_layer_2" in surface["variable"])
end

@testset "zip downloads are reported" begin
    mktempdir() do dir
        path = joinpath(dir, "archive.nc")
        write(path, "PK\x03\x04rest of a zip archive")
        @test_throws Exception ERA5.assert_netcdf_download(path)
        # A real NetCDF file passes through
        nc_path = joinpath(dir, "real.nc")
        NCDatasets.NCDataset(nc_path, "c") do ds
            NCDatasets.defDim(ds, "x", 1)
        end
        @test ERA5.assert_netcdf_download(nc_path) == nc_path
    end
end

@testset "end-to-end fetch with fake retrieval" begin
    mktempdir() do dir
        recorded = []
        fetched_dir = ERA5.fetch_initial_conditions(
            TEST_DATE;
            dir,
            retrieve_fn = make_fake_retrieve(recorded),
        )
        @test fetched_dir == dir
        @test length(recorded) == 2
        @test ERA5.files_complete(dir, TEST_DATE)
        for name in ERA5.output_filenames(TEST_DATE)
            @test isfile(joinpath(dir, name))
        end
        # No temporary directories are left behind
        @test !any(startswith("tmp_era5_"), readdir(dir))

        # Validation passes on the complete cache
        ERA5.validate_dir(dir, TEST_DATE)

        # A second fetch hits the cache and makes no new requests
        ERA5.fetch_initial_conditions(
            TEST_DATE;
            dir,
            retrieve_fn = make_fake_retrieve(recorded),
        )
        @test length(recorded) == 2

        # force = true downloads again
        ERA5.fetch_initial_conditions(
            TEST_DATE;
            dir,
            force = true,
            retrieve_fn = make_fake_retrieve(recorded),
        )
        @test length(recorded) == 4

        # Raw file: dimensions and merged surface variables
        NCDatasets.NCDataset(joinpath(dir, ERA5.raw_filename(TEST_DATE))) do ds
            for dim in ("longitude", "latitude", "model_level", "valid_time")
                @test haskey(ds.dim, dim)
            end
            for name in ("u", "v", "w", "t", "q", "skt", "sp", "surface_geopotential")
                @test haskey(ds, name)
            end
            @test size(Array(ds["t"])) == (NLON, NLAT, NLEVELS, 1)
            @test all(Array(ds["surface_geopotential"]) .== 100.0f0)
            # The levels keep the order CDS delivers, 1 at the top
            @test Array(ds["model_level"]) == TEST_MODEL_LEVELS
        end

        # SST: Celsius, land filled, rolled longitudes, 4 time points
        NCDatasets.NCDataset(joinpath(dir, ERA5.sst_filename(TEST_DATE))) do ds
            sst = Array(ds["SST"])
            @test size(sst) == (NLON, NLAT, 4)
            @test all(sst .≈ 290.0 - 273.15)
            lon = Array(ds["lon"])
            @test issorted(lon)
            @test all(lon .>= 0)
            @test length(Array(ds["time"])) == 4
        end

        # SIC: percent, with missing values as 0 over land
        NCDatasets.NCDataset(joinpath(dir, ERA5.sic_filename(TEST_DATE))) do ds
            sic = Array(ds["SEAICE"])
            @test maximum(sic) ≈ 50.0
            @test minimum(sic) == 0.0
            @test haskey(ds, "ISTL1")
        end

        # Land: sorted latitude, zeros over ocean, sorted negative z
        NCDatasets.NCDataset(joinpath(dir, ERA5.land_filename(TEST_DATE))) do ds
            @test issorted(Array(ds["lat"]))
            z = Array(ds["z"])
            @test issorted(z)
            @test all(z .< 0)
            swvl = Array(ds["swvl"])
            stl = Array(ds["stl"])
            @test size(swvl) == (NLON, NLAT, 4)
            # Ocean points are exactly 0
            @test all(swvl[4:end, :, :] .== 0)
            @test all(stl[4:end, :, :] .== 0)
            # Layer 1 is the last z index after the reversal
            @test all(stl[1:3, :, 4] .≈ 272.0)
            @test all(Array(ds["swe"])[1:3, :] .≈ 0.1)
            @test all(Array(ds["tsn"])[1:3, :] .≈ 265.0)
        end

        # Bucket: W column sum with 0.5 m cutoff, filled T
        NCDatasets.NCDataset(joinpath(dir, ERA5.bucket_filename(TEST_DATE))) do ds
            W = Array(ds["W"])
            expected_W = 0.3 * 0.07 + 0.32 * 0.21 + 0.34 * 0.22
            @test all(W[1:3, :] .≈ expected_W)
            @test all(W[4:end, :] .== 0)
            T = Array(ds["T"])
            # The nearest-neighbor fill gives ocean points a land value
            @test minimum(T) > 100
            @test all(Array(ds["Ws"])[1:3, :] .≈ 0.001)
            @test all(Array(ds["S"])[1:3, :] .≈ 0.1)
        end

        # Albedo: fal renamed to sw_alb_clr, values in [0, 1]
        NCDatasets.NCDataset(joinpath(dir, ERA5.albedo_filename(TEST_DATE))) do ds
            albedo = Array(ds["sw_alb_clr"])
            @test size(albedo, 3) == 4
            @test all(albedo .≈ 0.2)
        end
    end
end

@testset "validation failure modes" begin
    mktempdir() do dir
        recorded = []
        ERA5.fetch_initial_conditions(
            TEST_DATE;
            dir,
            retrieve_fn = make_fake_retrieve(recorded),
        )

        # A missing file
        missing_dir = joinpath(dir, "incomplete")
        mkpath(missing_dir)
        @test_throws Exception ERA5.validate_dir(missing_dir, TEST_DATE)

        # Corrupt a file so SEAICE goes outside [0, 100]
        sic_path = joinpath(dir, ERA5.sic_filename(TEST_DATE))
        NCDatasets.NCDataset(sic_path, "a") do ds
            ds["SEAICE"][1, 1, 1] = 150.0
        end
        @test_throws Exception ERA5.validate_dir(dir, TEST_DATE)
    end
end

@testset "truncated MARS responses are caught" begin
    mktempdir() do dir
        # MARS can answer `1/to/137` with level 1 alone. The file looks fine
        # otherwise, so only the level coordinate gives it away.
        for levels in ([1], collect(1:(NLEVELS - 1)))
            path = write_fake_model_file(joinpath(dir, "truncated.nc"); levels)
            NCDatasets.NCDataset(path) do ds
                @test_throws Exception ERA5.check_model_levels(ds, path)
            end
            rm(path)
        end
        full = write_fake_model_file(joinpath(dir, "full.nc"))
        NCDatasets.NCDataset(ds -> ERA5.check_model_levels(ds, full), full)
    end
end

@testset "failed fetch leaves no partial cache" begin
    mktempdir() do dir
        throwing_retrieve = (dataset, request, path; wait = 1.0) -> error("network down")
        @test_throws Exception ERA5.fetch_initial_conditions(
            TEST_DATE;
            dir,
            retrieve_fn = throwing_retrieve,
        )
        @test !ERA5.files_complete(dir, TEST_DATE)
        for name in ERA5.output_filenames(TEST_DATE)
            @test !isfile(joinpath(dir, name))
        end
        # The lock is released on failure
        @test !isfile(joinpath(dir, ERA5.lock_filename(TEST_DATE)))
    end
end

@testset "concurrent fetches share one download" begin
    mktempdir() do dir
        recorded = []
        fake_retrieve = make_fake_retrieve(recorded)
        slow_retrieve = function (dataset, request, path; wait = 1.0)
            sleep(0.1)
            return fake_retrieve(dataset, request, path; wait)
        end
        tasks = [
            @async(
                ERA5.fetch_initial_conditions(
                    TEST_DATE;
                    dir,
                    retrieve_fn = slow_retrieve,
                )
            ) for _ in 1:3
        ]
        dirs = fetch.(tasks)
        @test all(==(dir), dirs)
        # Only one task downloads. The others wait on the per-date lock and
        # reuse the finished files.
        @test length(recorded) == 2
        @test ERA5.files_complete(dir, TEST_DATE)
        @test !isfile(joinpath(dir, ERA5.lock_filename(TEST_DATE)))
    end
end

@testset "credentials detection" begin
    withenv("CDSAPI_URL" => "https://example.invalid", "CDSAPI_KEY" => "x") do
        @test ERA5.credentials_available()
    end
end

@testset "processors run standalone" begin
    # This is how WeatherQuest uses the package: call one processor on one
    # already-downloaded file, with no network and no cache involved.
    mktempdir() do dir
        source = joinpath(dir, "era5_single_levels.nc")
        write_fake_surface_file(source)
        model = joinpath(dir, "era5_model_levels.nc")
        write_fake_model_file(model)

        singles = (
            (ERA5.process_sst, "sst.nc", "SST"),
            (ERA5.process_sic, "sic.nc", "SEAICE"),
            (ERA5.process_land, "land.nc", "swvl"),
            (ERA5.process_bucket, "bucket.nc", "W"),
            (ERA5.process_albedo, "albedo.nc", "sw_alb_clr"),
        )
        for (process, name, varname) in singles
            out = joinpath(dir, name)
            # Every processor takes (source, output) and returns the output
            @test process(source, out) == out
            NCDatasets.NCDataset(ds -> (@test haskey(ds, varname)), out)
        end

        raw = joinpath(dir, "raw.nc")
        @test ERA5.build_raw(model, source, raw) == raw
        @test isfile(raw)
    end
end

@testset "output attributes match WeatherQuest" begin
    mktempdir() do dir
        source = joinpath(dir, "era5_single_levels.nc")
        write_fake_surface_file(source)

        sic = ERA5.process_sic(source, joinpath(dir, "sic.nc"))
        NCDatasets.NCDataset(sic) do ds
            # The CF standard name, as WeatherQuest `preprocess_sic` writes it
            @test ds["SEAICE"].attrib["standard_name"] == "sea_ice_area_fraction"
            @test ds["ISTL1"].attrib["standard_name"] == "sea_ice_temperature"
            # ERA5 stores latitude decreasing and this file keeps that order
            @test !issorted(Array(ds["lat"]))
            @test ds["lat"].attrib["stored_direction"] == "decreasing"
        end

        # The integrated-land file is the one that sorts latitude
        land = ERA5.process_land(source, joinpath(dir, "land.nc"))
        NCDatasets.NCDataset(land) do ds
            @test issorted(Array(ds["lat"]))
            @test ds["lat"].attrib["stored_direction"] == "increasing"
        end
    end
end

@testset "ERA5T files select the later experiment version" begin
    # CDS returns an `expver` dimension for a date inside the ERA5T window, and
    # the final-ERA5 slice has no data there. Taking the first slice would give
    # an all-missing field, so every processor must take the last one.
    mktempdir() do dir
        surface = joinpath(dir, "surface_expver.nc")
        model = joinpath(dir, "model_expver.nc")
        write_fake_surface_file(surface; expver = true)
        write_fake_model_file(model; expver = true)
        processed = (process, name) -> process(surface, joinpath(dir, name))

        NCDatasets.NCDataset(processed(ERA5.process_sst, "sst.nc")) do ds
            @test all(Array(ds["SST"]) .≈ 290.0 - 273.15)
        end
        NCDatasets.NCDataset(processed(ERA5.process_sic, "sic.nc")) do ds
            @test maximum(Array(ds["SEAICE"])) ≈ 50.0
            @test all(Array(ds["ISTL1"]) .≈ 271.0)
        end
        NCDatasets.NCDataset(processed(ERA5.process_land, "land.nc")) do ds
            @test all(Array(ds["skt"]) .≈ 285.0)
            @test maximum(Array(ds["stl"])) ≈ 283.0
        end
        NCDatasets.NCDataset(processed(ERA5.process_bucket, "bucket.nc")) do ds
            @test minimum(Array(ds["T"])) > 100
            @test maximum(Array(ds["S"])) ≈ 0.1
        end
        NCDatasets.NCDataset(processed(ERA5.process_albedo, "albedo.nc")) do ds
            @test all(Array(ds["sw_alb_clr"]) .≈ 0.2)
        end

        # `build_raw` drops the dimension rather than carrying it forward,
        # because ClimaAtmos indexes the raw file positionally
        raw = ERA5.build_raw(model, surface, joinpath(dir, "raw.nc"))
        NCDatasets.NCDataset(raw) do ds
            @test !haskey(ds.dim, "expver")
            @test !haskey(ds, "expver")
            @test size(Array(ds["t"])) == (NLON, NLAT, NLEVELS, 1)
            @test all(Array(ds["t"]) .≈ 280.0f0)
            @test all(Array(ds["surface_geopotential"]) .== 100.0f0)
            # Decoded data carries no leftover encoding attributes
            for name in ("t", "q", "skt", "sp", "surface_geopotential")
                @test !haskey(ds[name].attrib, "_FillValue")
            end
        end
        NCDatasets.NCDataset(ds -> ERA5.validate_raw(ds, raw), raw)
    end
end

@testset "date keyword is a fallback, not a requirement" begin
    mktempdir() do dir
        # The fixture has valid_time, so the date is taken from the file and
        # passing one changes nothing
        source = joinpath(dir, "with_time.nc")
        write_fake_surface_file(source)
        a, b = joinpath(dir, "a.nc"), joinpath(dir, "b.nc")
        ERA5.process_sst(source, a)
        ERA5.process_sst(source, b; date = TEST_DATE)
        ta = NCDatasets.NCDataset(ds -> Array(ds["time"]), a)
        tb = NCDatasets.NCDataset(ds -> Array(ds["time"]), b)
        @test ta == tb

        # A file with no time coordinate needs the fallback
        timeless = joinpath(dir, "no_time.nc")
        NCDatasets.NCDataset(timeless, "c") do ds
            NCDatasets.defDim(ds, "longitude", NLON)
            NCDatasets.defDim(ds, "latitude", NLAT)
            NCDatasets.defVar(ds, "longitude", TEST_LON, ("longitude",))
            NCDatasets.defVar(ds, "latitude", TEST_LAT, ("latitude",))
            NCDatasets.defVar(ds, "sst", fill(290.0, NLON, NLAT), ("longitude", "latitude"))
        end
        out = joinpath(dir, "c.nc")
        @test_throws Exception ERA5.process_sst(timeless, out)
        @test ERA5.process_sst(timeless, out; date = TEST_DATE) == out
    end
end
