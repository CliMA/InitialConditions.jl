"""
    build_raw(model_path, surface_path, output_path)

Build the raw atmosphere file. It holds the model-level variables, the
single-level `skt` and `sp`, and the single-level geopotential renamed to
`surface_geopotential`. Port of `combine_era5_datasets` in WeatherQuest
`get_initial_conditions.py`, including the geopotential rename.

Keep the dimension names `longitude`, `latitude`, `model_level`, and
`valid_time`, because WeatherQuest `to_z_levels_3d_model` asserts them. An
`expver` dimension, which CDS adds for a date inside the ERA5T window, is
collapsed onto its last index and dropped, as WeatherQuest
`_resolve_expver_conflict` does.

Keep the levels in the order CDS delivers them, level 1 at the model top and
level 137 at the surface. `to_z_levels_3d_model` reads that order off the
`model_level` coordinate and flips it itself, and the hybrid coefficients that
turn the levels into pressures are indexed by level number, so reordering here
would only desynchronize them.

!!! note "One step short of ClimaAtmos"

    Every other output of this package is the file its component model reads.
    The atmosphere is not: this file still needs WeatherQuest
    `to_z_levels_3d_model` to become the `era5_init_processed_internal_*.nc`
    that ClimaAtmos opens. TODO: port that step, which reconstructs pressure
    from the IFS hybrid coefficients, integrates geopotential hydrostatically,
    and interpolates each column onto the target grid.
"""
function build_raw(model_path, surface_path, output_path)
    NCDatasets.NCDataset(output_path, "c") do ncout
        NCDatasets.NCDataset(model_path) do ncm
            for name in ("longitude", "latitude", "model_level", "valid_time")
                haskey(ncm.dim, name) || error(
                    "Expected dimension $name in the CDS model-level file, " *
                    "found $(collect(keys(ncm.dim))). The CDS output format " *
                    "may have changed.",
                )
            end
            for (name, len) in ncm.dim
                name in EXPVER_DIM_NAMES && continue
                NCDatasets.defDim(ncout, name, len)
            end
            for (name, var) in ncm
                name in EXPVER_DIM_NAMES && continue
                data, dims = drop_expver(Array(var), NCDatasets.dimnames(var))
                attrib = clean_attributes(var)
                if eltype(data) <: Union{Missing, AbstractFloat}
                    # A plain Float32 array, so NCDatasets adds no _FillValue
                    data = Float32.(coalesce.(data, NaN))
                end
                NCDatasets.defVar(ncout, name, data, dims; attrib = attrib)
            end
        end
        NCDatasets.NCDataset(surface_path) do ncs
            for (src_name, dst_name) in
                (("skt", "skt"), ("sp", "sp"), ("z", "surface_geopotential"))
                haskey(ncs, src_name) ||
                    error("Variable $src_name not found in the CDS surface file")
                var = ncs[src_name]
                data, dims = drop_expver(Array(var), NCDatasets.dimnames(var))
                all(d -> haskey(ncout.dim, d), dims) || error(
                    "The CDS surface file grid does not match the " *
                    "model-level file grid (dims $(dims))",
                )
                data = Float32.(coalesce.(data, NaN))
                attrib = clean_attributes(var)
                attrib["varname"] = dst_name
                NCDatasets.defVar(ncout, dst_name, data, dims; attrib = attrib)
            end
        end
    end
    return output_path
end
