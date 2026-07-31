"""
    build_raw(pressure_path, surface_path, output_path)

Build the raw atmosphere file that the ClimaAtmos WeatherModel reads. It
holds the pressure-level variables, the single-level `skt` and `sp`, and the
single-level geopotential renamed to `surface_geopotential`. Port of
`combine_era5_datasets` in WeatherQuest `get_initial_conditions.py`,
including the geopotential rename.

Keep the dimension names `longitude`, `latitude`, `pressure_level`, and
`valid_time`, because ClimaAtmos asserts them.

Write the levels in order of decreasing pressure, which is increasing
altitude. ClimaAtmos interpolates each column in altitude and assumes that
the vertical coordinate increases. With the levels in the other order, it
extrapolates the top level down to the whole column and gives no warning.
"""
function build_raw(pressure_path, surface_path, output_path)
    NCDatasets.NCDataset(output_path, "c") do ncout
        NCDatasets.NCDataset(pressure_path) do ncp
            for name in ("longitude", "latitude", "pressure_level", "valid_time")
                haskey(ncp.dim, name) || error(
                    "Expected dimension $name in the CDS pressure-level " *
                    "file, found $(collect(keys(ncp.dim))). The CDS output " *
                    "format may have changed.",
                )
            end
            level_perm = sortperm(Array(ncp["pressure_level"]); rev = true)
            for (name, len) in ncp.dim
                NCDatasets.defDim(ncout, name, len)
            end
            for (name, var) in ncp
                dims = NCDatasets.dimnames(var)
                data = Array(var)
                level_dim = findfirst(==("pressure_level"), dims)
                isnothing(level_dim) || (data = permute_along(data, level_dim, level_perm))
                attrib = clean_attributes(var)
                if eltype(data) <: Union{Missing, AbstractFloat}
                    data = Float32.(replace(data, missing => NaN))
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
                dims = NCDatasets.dimnames(var)
                all(d -> haskey(ncout.dim, d), dims) || error(
                    "The CDS surface file grid does not match the " *
                    "pressure-level file grid (dims $(dims))",
                )
                data = Float32.(replace(Array(var), missing => NaN))
                attrib = clean_attributes(var)
                attrib["varname"] = dst_name
                NCDatasets.defVar(ncout, dst_name, data, dims; attrib = attrib)
            end
        end
    end
    return output_path
end
