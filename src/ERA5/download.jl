# Number of times a CDS download is attempted before giving up.
const DOWNLOAD_ATTEMPTS = 3

# Seconds to wait after a failed download attempt, times the attempt number.
const DOWNLOAD_RETRY_WAIT = 30.0

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
    try
        NCDatasets.NCDataset(path) do ds
            isempty(ds.dim) && error("no dimensions")
        end
    catch err
        error(
            "The CDS download at $path is not a readable NetCDF file, which " *
            "usually means the transfer was cut short: $(err)",
        )
    end
    return path
end

"""
    retrieve_with_retries(retrieve_fn, dataset, request, path; wait, attempts)

Download one CDS request to `path`, trying again when the transfer fails.

A retry resubmits the request, but CDS caches a result it has already
produced, so the later attempts usually skip the queue and go straight to the
transfer. A partial file is removed first, because CDS writes to the path from
the start rather than to a temporary.
"""
function retrieve_with_retries(
    retrieve_fn,
    dataset,
    request,
    path;
    wait,
    attempts = DOWNLOAD_ATTEMPTS,
)
    for attempt in 1:attempts
        try
            retrieve_fn(dataset, request, path; wait)
            return assert_netcdf_download(path)
        catch err
            attempt == attempts && rethrow()
            @warn "CDS download failed, trying again" dataset attempt attempts exception =
                err
            rm(path; force = true)
            sleep(DOWNLOAD_RETRY_WAIT * attempt)
        end
    end
end

"""
    download_source_files(date, download_dir; retrieve_fn, wait)

Submit the model-level and single-level CDS requests for `date` and download the
results into `download_dir`. Returns a NamedTuple with the paths of the two
NetCDF files. `retrieve_fn` has the signature of `CDSAPI.retrieve`. `attempts`
set the number of times each transfer is tried, 1 to fail on the first error.
"""
function download_source_files(
    date,
    download_dir;
    retrieve_fn = CDSAPI.retrieve,
    wait = 30.0,
    attempts = DOWNLOAD_ATTEMPTS,
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
        return retrieve_with_retries(
            retrieve_fn,
            dataset,
            request,
            path;
            wait,
            attempts,
        )
    end
    return NamedTuple{keys(specs)}(paths)
end
