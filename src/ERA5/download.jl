"""
    assert_netcdf_download(path)

Check that a completed CDS download is a NetCDF file, and return its path.

CDS can split a request across data streams and deliver a zip archive. This
module does not unpack archives, so it reports that case here instead of
failing later with a confusing NetCDF error.
"""
function assert_netcdf_download(path)
    magic = open(io -> read(io, 2), path)
    magic == UInt8['P', 'K'] && error(
        "CDS delivered a zip archive rather than a NetCDF file for $path. " *
        "This happens when CDS splits a request across data streams. Please " *
        "report the request that caused it.",
    )
    return path
end

"""
    download_source_files(date, download_dir; retrieve_fn, wait)

Submit the model-level and single-level CDS requests for `date` and download
the results into `download_dir`. Returns a NamedTuple with the paths of the two
NetCDF files. `retrieve_fn` has the signature of `CDSAPI.retrieve`.
"""
function download_source_files(
    date,
    download_dir;
    retrieve_fn = CDSAPI.retrieve,
    wait = 30.0,
)
    specs = (
        model = ("reanalysis-era5-complete", model_levels_request(date)),
        surface = ("reanalysis-era5-single-levels", single_levels_request(date)),
    )
    paths = map(keys(specs)) do key
        (dataset, request) = specs[key]
        path = joinpath(download_dir, "cds_$(key)_$(datetimestamp(date)).nc")
        @info "Requesting ERA5 data from CDS (this can queue for a while)" dataset date group =
            key
        retrieve_fn(dataset, request, path; wait)
        return assert_netcdf_download(path)
    end
    return NamedTuple{keys(specs)}(paths)
end
