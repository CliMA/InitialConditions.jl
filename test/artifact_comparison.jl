# Compare what this package writes against the wxquest_initial_conditions
# artifact that WeatherQuest built, for one date.
#
# This guards the port: every shared variable has to stay bit-identical apart
# from the differences we know about and accept. It needs the artifact on
# /groups/esm and CDS credentials, so it runs on the cluster rather than in
# GitHub Actions.
#
#     IC_ARTIFACT_DIR=... julia --project=. test/artifact_comparison.jl

import Test: @test, @testset
import Dates
import NCDatasets
import InitialConditions.ERA5

const ARTIFACT_DIR = get(
    ENV,
    "IC_ARTIFACT_DIR",
    "/groups/esm/ClimaArtifacts/artifacts/wxquest_initial_conditions",
)
const DATE = Dates.DateTime(get(ENV, "IC_TEST_DATE", "2010-01-01"))
const STAMP = Dates.format(DATE, "yyyymmdd_HHMM")

"""
Variables the artifact carries that this package deliberately leaves out, and
the reason each one is dropped. Documented in `docs/src/index.md`.
"""
const EXPECTED_MISSING = Dict(
    "sic_processed" => ["ISTL2", "ISTL3", "ISTL4"],
    "era5_land_processed" => ["lai", "si", "sie"],
    "albedo_processed" => ["fsr", "flsr"],
    "sst_processed" => String[],
    "era5_bucket_processed" => String[],
)

"""
`W` is summed in Float64 before it is stored as Float32, where WeatherQuest
sums in Float32, so the two differ by a rounding step.
"""
const W_TOLERANCE = 1.0e-7

"""
SST over land is whatever the gap fill put there. This package fills by a
breadth-first search in index space and WeatherQuest uses a Euclidean nearest
neighbour, so the two disagree over land and have to agree over ocean.
"""
const SST_OCEAN_TOLERANCE = 1.0e-4

if !isdir(ARTIFACT_DIR)
    error("No artifact directory at $(ARTIFACT_DIR). Set IC_ARTIFACT_DIR.")
end

dir = ERA5.fetch_initial_conditions(DATE)

"""
The ocean mask on the [0, 360) longitude axis the processed files use. ERA5
leaves `sst` missing over land, so it says which points are ocean. The
artifact raw file is the only one here that still carries it.
"""
function ocean_mask()
    path = joinpath(ARTIFACT_DIR, "era5_raw_$(STAMP).nc")
    NCDatasets.NCDataset(path) do ds
        lon = Array(ds["longitude"])
        sst = ERA5.IC.read_surface_field(ds, "sst")
        _, perm = ERA5.IC.roll_longitudes(lon)
        return .!ismissing.(sst[perm, :])
    end
end

@testset "InitialConditions.ERA5 against wxquest_initial_conditions" begin
    for (name, expected_missing) in EXPECTED_MISSING
        mine = joinpath(dir, "$(name)_$(STAMP).nc")
        theirs = joinpath(ARTIFACT_DIR, "$(name)_$(STAMP).nc")
        isfile(theirs) || continue

        @testset "$name" begin
            NCDatasets.NCDataset(mine) do a
                NCDatasets.NCDataset(theirs) do b
                    data_vars = n -> sort([
                        k for k in keys(n) if !(k in keys(n.dim))
                    ])
                    only_theirs = setdiff(data_vars(b), data_vars(a))
                    @test sort(only_theirs) == sort(expected_missing)
                    @test isempty(setdiff(data_vars(a), data_vars(b)))

                    for coord in keys(a.dim)
                        haskey(a, coord) && haskey(b, coord) || continue
                        @test Array(a[coord]) == Array(b[coord])
                    end

                    for v in intersect(data_vars(a), data_vars(b))
                        mine_data = Array(a[v])
                        theirs_data = Array(b[v])
                        @test size(mine_data) == size(theirs_data)
                        difference = abs.(mine_data .- theirs_data)
                        if v == "W"
                            @test maximum(difference) <= W_TOLERANCE
                        elseif v == "SST"
                            # Only the ocean has to agree
                            mask = ocean_mask()
                            ocean = difference[mask, :]
                            @test maximum(ocean) <= SST_OCEAN_TOLERANCE
                        else
                            @test maximum(difference) == 0
                        end
                    end
                end
            end
        end
    end

    @testset "era5_raw" begin
        mine = joinpath(dir, "era5_raw_$(STAMP).nc")
        theirs = joinpath(ARTIFACT_DIR, "era5_raw_$(STAMP).nc")
        NCDatasets.NCDataset(mine) do a
            NCDatasets.NCDataset(theirs) do b
                for v in ("t", "u", "v", "q", "sp", "skt", "surface_geopotential")
                    @test haskey(a, v)
                    @test maximum(abs.(Array(a[v]) .- Array(b[v]))) == 0
                end
                # The model levels have to arrive whole and in order
                @test Array(a["model_level"]) == collect(1:ERA5.N_MODEL_LEVELS)
            end
        end
    end
end
