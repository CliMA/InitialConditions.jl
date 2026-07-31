"""
    process_sst(source_path, output_path; date = nothing)

Write the SST file. It holds the variable `SST` in Celsius on
`(lon, lat, time)`, with land filled by nearest neighbor, a [0, 360)
longitude axis, and the field copied to four monthly time points.
Port of `preprocess_sst` in WeatherQuest `interpolate.jl`.

`date` is only a fallback for a source file with no time coordinate. Every ERA5
download has one, so you rarely need it.
"""
function process_sst(source_path, output_path; date = nothing)
    NCDatasets.NCDataset(source_path) do ncin
        lon, lat = read_lonlat(ncin)
        ref_date = reference_date(ncin, date)
        sst = nearest_neighbor_fill(read_surface_field(ncin, "sst")) .- 273.15
        lon360, perm = roll_longitudes(lon)
        sst = sst[perm, :]
        time_points = monthly_time_points(ref_date)
        NCDatasets.NCDataset(output_path, "c") do ncout
            define_lonlat_time!(ncout, lon360, lat, time_points)
            write_replicated_time_var!(
                ncout,
                "SST",
                sst,
                length(time_points);
                attrib = Dict(
                    "standard_name" => "sea_surface_temperature",
                    "long_name" => "Sea Surface Temperature",
                    "units" => "celsius",
                    "varname" => "SST",
                ),
            )
        end
    end
    return output_path
end

"""
    process_sic(source_path, output_path; date = nothing)

Write the sea ice file. It holds the variable `SEAICE` in percent on
`(lon, lat, time)`, where missing values become 0, and `ISTL1`, the
near-surface ice temperature in Kelvin, filled by nearest neighbor.
Port of `preprocess_sic` in WeatherQuest `interpolate.jl`, without the deeper
ice temperature layers, which have no consumer.

`date` is only a fallback for a source file with no time coordinate. Every ERA5
download has one, so you rarely need it.
"""
function process_sic(source_path, output_path; date = nothing)
    NCDatasets.NCDataset(source_path) do ncin
        lon, lat = read_lonlat(ncin)
        ref_date = reference_date(ncin, date)
        sic = clamp.(zero_fill(read_surface_field(ncin, "siconc")) .* 100, 0, 100)
        lon360, perm = roll_longitudes(lon)
        sic = sic[perm, :]
        istl1 = nearest_neighbor_fill(read_surface_field(ncin, "istl1"))[perm, :]
        time_points = monthly_time_points(ref_date)
        NCDatasets.NCDataset(output_path, "c") do ncout
            define_lonlat_time!(ncout, lon360, lat, time_points)
            write_replicated_time_var!(
                ncout,
                "SEAICE",
                sic,
                length(time_points);
                attrib = Dict(
                    "standard_name" => "sea_ice_cover",
                    "long_name" => "Sea Ice Concentration",
                    "units" => "%",
                    "varname" => "SEAICE",
                ),
            )
            write_replicated_time_var!(
                ncout,
                "ISTL1",
                istl1,
                length(time_points);
                attrib = Dict(
                    "long_name" => "Ice temperature layer 1",
                    "units" => "K",
                    "varname" => "ISTL1",
                ),
            )
        end
    end
    return output_path
end
