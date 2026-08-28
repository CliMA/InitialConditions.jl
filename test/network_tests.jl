# End-to-end test of the CDS download path. This test is not in the default
# test suite, because it needs CDS credentials and network access, and because
# CDS requests can queue for a long time. Run it with:
#
#     ERA5_NETWORK_TESTS=true julia --project=test test/network_tests.jl

import Test: @test, @testset
import Dates
import NCDatasets
import InitialConditions as IC
import InitialConditions.ERA5

run_network_tests = get(ENV, "ERA5_NETWORK_TESTS", "false") == "true"

if !run_network_tests
    @info "Skipping the ERA5 network tests. Set ERA5_NETWORK_TESTS=true to run them."
elseif !ERA5.credentials_available()
    error(
        "The ERA5 network tests need CDS credentials in ~/.cdsapirc or in CDSAPI_URL and CDSAPI_KEY",
    )
else
    DATE = Dates.DateTime(2023, 6, 1)

    @testset "ERA5 CDS download end to end" begin
        mktempdir() do dir
            fetched_dir = ERA5.fetch_initial_conditions(DATE; dir, wait = 30.0)
            @test fetched_dir == dir
            @test ERA5.files_complete(dir, DATE)
            ERA5.validate_dir(dir, DATE)

            # The second call is a cache hit
            ERA5.fetch_initial_conditions(DATE; dir)
            @test ERA5.files_complete(dir, DATE)

            # The raw file meets the preconditions that the model-level
            # preprocessing asserts. `validate_dir` checks these, but assert
            # them here too
            NCDatasets.NCDataset(joinpath(dir, ERA5.raw_filename(DATE))) do ds
                for dim in ("longitude", "latitude", "model_level", "valid_time")
                    @test haskey(ds.dim, dim)
                end
                for name in ("u", "v", "w", "t", "q", "skt", "sp", "surface_geopotential")
                    @test haskey(ds, name)
                end
                # MARS can answer `1/to/137` with level 1 alone, and only a
                # real request can tell us whether it did
                @test Array(ds["model_level"]) == collect(1:137)
            end

            # The single-level fields landed on the grids the readers expect
            NCDatasets.NCDataset(joinpath(dir, ERA5.sst_filename(DATE))) do ds
                lon = Array(ds["lon"])
                @test issorted(lon)
                @test all(lon .>= 0)
                sst = Array(ds["SST"])
                # Celsius, not Kelvin
                @test minimum(sst) > -60
                @test maximum(sst) < 60
            end
            NCDatasets.NCDataset(joinpath(dir, ERA5.land_filename(DATE))) do ds
                @test issorted(Array(ds["lat"]))
                @test issorted(Array(ds["z"]))
                # Ocean points are 0, which is how the ClimaLand reader masks
                @test minimum(Array(ds["stl"])) == 0
            end
        end
    end

    @testset "default cache directory is used when dir is not given" begin
        mktempdir() do cache_dir
            withenv("INITIAL_CONDITIONS_CACHE_DIR" => cache_dir) do
                @test ERA5.cache_dir() == cache_dir
                dir = ERA5.fetch_initial_conditions(DATE)
                @test dir == cache_dir
                @test ERA5.files_complete(dir, DATE)
                ERA5.validate_dir(dir, DATE)
            end
        end
    end
end
