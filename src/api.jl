# API-based backend: fetches version metadata from the GeneralMetadata.jl web API.
# This is a lightweight alternative to the git backend that requires no disk space,
# but data may be up to ~24h stale (the API updates daily around midnight UTC).

using Downloads

# Session cache for API responses: package_name => Dict(version => metadata)
const VERSION_CACHE = Dict{String, Dict{String, Any}}()

const API_BASE = "https://juliaregistries.github.io/GeneralMetadata.jl/api"

"""
    fetch_package_versions_api(package_name::String) -> Dict{String, Any}

Fetch version metadata for a package from the GeneralMetadata API.
Returns a Dict mapping version strings to metadata dicts containing
`registered` (DateTime string) and optionally `yanked` (DateTime string).

Results are cached in-session to avoid redundant API calls.
"""
function fetch_package_versions_api(package_name::String)
    if haskey(VERSION_CACHE, package_name)
        return VERSION_CACHE[package_name]
    end

    url = "$API_BASE/$package_name/versions.json"
    buf = IOBuffer()
    try
        Downloads.download(url, buf)
    catch e
        if e isa Downloads.RequestError && e.response.status == 404
            error("Package '$package_name' not found in General registry")
        end
        rethrow()
    end

    data = JSON.parse(String(take!(buf)))
    VERSION_CACHE[package_name] = data
    return data
end

"""
    when_internal_api(package_name::String, version::Union{String, Nothing}) -> (DateTime, Bool, String)

API-based implementation of when_internal.
Returns a tuple of (timestamp, is_yanked, resolved_version).
"""
function when_internal_api(package_name::String, version::Union{String, Nothing})
    data = fetch_package_versions_api(package_name)

    if isempty(data)
        error("No versions found for package '$package_name'")
    end

    all_versions = sort!(collect(keys(data)), by=VersionNumber)

    if isnothing(version)
        version = last(all_versions)
    else
        version = resolve_version_api(data, version)
    end

    if !haskey(data, version)
        error("Version $version not found for package '$package_name'")
    end

    version_data = data[version]

    registered = version_data["registered"]
    timestamp = if registered isa DateTime
        registered
    else
        DateTime(string(registered), dateformat"yyyy-mm-ddTHH:MM:SS")
    end

    yanked = haskey(version_data, "yanked")

    return (timestamp, yanked, version)
end

"""
    resolve_version_api(data::AbstractDict, partial_version::String) -> String

Resolve a partial version to a full version string using API data.
Skips yanked versions when resolving partial versions, but allows exact yanked versions.
"""
function resolve_version_api(data::AbstractDict, partial_version::String)
    all_versions = sort!(collect(keys(data)), by=VersionNumber)

    if partial_version in all_versions
        return partial_version
    end

    non_yanked = filter(v -> !haskey(data[v], "yanked"), all_versions)

    search_prefix = partial_version * "."
    matching = filter(v -> startswith(v, search_prefix), non_yanked)

    if isempty(matching)
        matching = filter(v -> startswith(v, partial_version), non_yanked)
    end

    if isempty(matching)
        error("Version $partial_version not found for package (or all matching versions are yanked)")
    end

    return first(matching)
end

"""
    update_cache!()

Clear the in-session API metadata cache, so subsequent queries will fetch fresh data.
"""
function update_cache!()
    empty!(VERSION_CACHE)
    @info "API metadata cache cleared. Next query will fetch fresh data."
    return nothing
end
