"""
    process_land(source_path, output_path)

Write the integrated-land initial condition file. It holds these 2D
variables:

  - `skt` and `tsn` in Kelvin, filled by nearest neighbor
  - `swe`, the snow water equivalent in m

and these 3D variables on the negative depth coordinate `z`:

  - `swvl`, the total volumetric water
  - `stl`, the soil temperature in Kelvin

These are the variables that the ClimaLand subseasonal reader takes from this
file. The latitude axis increases. Ocean points are 0 in the masked fields,
because the ClimaLand reader masks with `> 0`. Port of `interpolate_land` in
WeatherQuest `interpolate.jl`, without the ice fraction and internal energy,
which ClimaLand derives itself.
"""
function process_land(source_path, output_path)
    NCDatasets.NCDataset(source_path) do ncin
        lon, lat = read_lonlat(ncin)
        lat_perm = sortperm(lat)
        nlayers = length(SOIL_LAYER_MIDPOINTS)

        read_soil =
            prefix -> begin
                layers = map(1:nlayers) do k
                    zero_fill(read_surface_field(ncin, "$prefix$k"))[:, lat_perm]
                end
                cat(layers...; dims = 3)
            end
        swvl = read_soil("swvl")
        stl = read_soil("stl")

        swe = zero_fill(read_surface_field(ncin, "sd"))[:, lat_perm]
        tsn = nearest_neighbor_fill(read_surface_field(ncin, "tsn"))[:, lat_perm]
        skt = nearest_neighbor_fill(read_surface_field(ncin, "skt"))[:, lat_perm]

        NCDatasets.NCDataset(output_path, "c") do ncout
            define_lonlat_time!(ncout, lon, lat[lat_perm], nothing)
            NCDatasets.defDim(ncout, "z", nlayers)
            z_var = NCDatasets.defVar(ncout, "z", Float32, ("z",), attrib = SOIL_Z_ATTRIB)
            z_var[:] = SOIL_Z

            for (name, field, units, long_name) in (
                ("swvl", swvl, "m^3/m^3", "Volumetric fraction of water"),
                ("stl", stl, "K", "Soil temperature"),
            )
                var = NCDatasets.defVar(
                    ncout,
                    name,
                    Float32,
                    ("lon", "lat", "z"),
                    attrib = Dict(
                        "units" => units,
                        "longname" => long_name,
                        "varname" => name,
                    ),
                )
                var[:, :, :] = soil_layers_to_z(field)
            end

            for (name, field, units, long_name) in (
                ("swe", swe, "m", "Snow water equivalent"),
                ("tsn", tsn, "K", "Temperature of snow layer"),
                ("skt", skt, "K", "Skin temperature"),
            )
                var = NCDatasets.defVar(
                    ncout,
                    name,
                    Float32,
                    ("lon", "lat"),
                    attrib = Dict(
                        "units" => units,
                        "longname" => long_name,
                        "varname" => name,
                    ),
                )
                var[:, :] = field
            end
        end
    end
    return output_path
end

# ============================================================================
# Preprocessing: bucket land
# ============================================================================

"""
    process_bucket(source_path, output_path; subsurface_water_z_max = 0.5)

Write the bucket initial condition file. It holds these 2D variables:

  - `W`, the soil water column integrated down to `subsurface_water_z_max`
  - `Ws`, the skin reservoir content
  - `S`, the snow water equivalent
  - `tsn` and `skt` in Kelvin

and the 3D soil temperature `T` on the negative depth coordinate `z`, filled
by nearest neighbor over ocean. Port of `interpolate_bucket` in WeatherQuest
`interpolate.jl`, including the layer-thickness weights of the `W` column
integral.
"""
function process_bucket(source_path, output_path; subsurface_water_z_max = 0.5)
    NCDatasets.NCDataset(source_path) do ncin
        lon, lat = read_lonlat(ncin)
        nlayers = length(SOIL_LAYER_MIDPOINTS)

        W = zeros(length(lon), length(lat))
        for k in 1:nlayers
            thickness = max(
                0.0,
                min(subsurface_water_z_max, SOIL_LAYER_BOTTOMS[k]) - SOIL_LAYER_TOPS[k],
            )
            thickness > 0 || continue
            W .+= zero_fill(read_surface_field(ncin, "swvl$k")) .* thickness
        end

        Ws = zero_fill(read_surface_field(ncin, "src"))
        S = zero_fill(read_surface_field(ncin, "sd"))

        # Fill the soil temperature over ocean, so the bucket has a value
        # everywhere. Zeros mark masked points in the source data.
        T_layers = map(1:nlayers) do k
            field = read_surface_field(ncin, "stl$k")
            with_nan = Union{Missing, Float64}[
                (ismissing(x) || x == 0) ? missing : x for x in field
            ]
            nearest_neighbor_fill(with_nan)
        end
        T = cat(T_layers...; dims = 3)

        tsn = nearest_neighbor_fill(read_surface_field(ncin, "tsn"))
        skt = nearest_neighbor_fill(read_surface_field(ncin, "skt"))

        NCDatasets.NCDataset(output_path, "c") do ncout
            define_lonlat_time!(ncout, lon, lat, nothing)
            NCDatasets.defDim(ncout, "z", nlayers)
            z_var = NCDatasets.defVar(ncout, "z", Float32, ("z",), attrib = SOIL_Z_ATTRIB)
            z_var[:] = SOIL_Z

            T_var = NCDatasets.defVar(
                ncout,
                "T",
                Float32,
                ("lon", "lat", "z"),
                attrib = Dict(
                    "units" => "K",
                    "longname" => "Soil temperature profile",
                    "varname" => "T",
                ),
            )
            T_var[:, :, :] = soil_layers_to_z(T)

            for (name, field, units, long_name) in (
                ("W", W, "m", "Subsurface water content"),
                ("Ws", Ws, "m", "Surface water content"),
                ("S", S, "m", "Snow water equivalent"),
                ("tsn", tsn, "K", "Temperature of snow layer"),
                ("skt", skt, "K", "Skin temperature"),
            )
                var = NCDatasets.defVar(
                    ncout,
                    name,
                    Float32,
                    ("lon", "lat"),
                    attrib = Dict(
                        "units" => units,
                        "longname" => long_name,
                        "varname" => name,
                    ),
                )
                var[:, :] = field
            end
        end
    end
    return output_path
end

# ============================================================================
# Preprocessing: albedo
# ============================================================================

"""
    process_albedo(source_path, output_path; date = nothing)

Write the albedo file. It holds the ERA5 forecast albedo as `sw_alb_clr` on
`(lon, lat, time)`. Port of `preprocess_albedo` in WeatherQuest
`interpolate.jl`, without the roughness fields, which have no consumer.

`date` is only a fallback for a source file with no time coordinate. Every ERA5
download has one, so you rarely need it.
"""
function process_albedo(source_path, output_path; date = nothing)
    NCDatasets.NCDataset(source_path) do ncin
        lon, lat = read_lonlat(ncin)
        ref_date = reference_date(ncin, date)
        lon360, perm = roll_longitudes(lon)
        albedo = nearest_neighbor_fill(read_surface_field(ncin, "fal")[perm, :])
        time_points = monthly_time_points(ref_date)
        NCDatasets.NCDataset(output_path, "c") do ncout
            define_lonlat_time!(ncout, lon360, lat, time_points)
            write_replicated_time_var!(
                ncout,
                "sw_alb_clr",
                albedo,
                length(time_points);
                attrib = Dict(
                    "standard_name" => "surface_albedo",
                    "long_name" => "Clear-sky shortwave albedo",
                    "units" => "1",
                    "varname" => "sw_alb_clr",
                ),
            )
        end
    end
    return output_path
end
