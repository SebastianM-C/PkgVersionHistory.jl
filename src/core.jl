# Core functionality for querying package version timestamps
# Uses GeneralMetadata.jl's web API for registration timestamps

"""
    fetch_package_versions(package_name::String) -> Dict{String, Any}

Fetch version metadata for a package from the GeneralMetadata API.
Returns a Dict mapping version strings to metadata dicts containing
`registered` (DateTime string) and optionally `yanked` (DateTime string).

Results are cached in-session to avoid redundant API calls.
"""
function fetch_package_versions(package_name::String)
    # Check session cache
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
    when(package_spec::String) -> DateTime

Get the timestamp when a package version was registered.

# Arguments
- `package_spec`: Package specification string, e.g., "Example" or "Example@1.2.3"

# Returns
- `DateTime` object representing when the version was registered in the General registry

# Examples
```julia
when("Example")  # Latest version
when("Example@1.2.3")  # Specific version
```

# See also
- [`check_pending_prs`](@ref): Check for pending PRs for a package in the General registry
- [`update_cache!`](@ref): Clear the local metadata cache
"""
function when(package_spec::String)
    # Parse package name and version
    parts = split(package_spec, '@')
    pkg_name = String(parts[1])
    version = length(parts) > 1 ? String(parts[2]) : nothing

    timestamp, _ = when_internal(pkg_name, version)
    return timestamp
end

"""
    when(package_spec::Pkg.Types.PackageSpec) -> DateTime

Get the timestamp when a package version was registered.

# Arguments
- `package_spec`: PackageSpec object

# Returns
- `DateTime` object representing when the version was registered
"""
function when(package_spec::Pkg.Types.PackageSpec)
    pkg_name = package_spec.name
    version = package_spec.version

    # Check that we have a package name
    if isnothing(pkg_name)
        error("PackageSpec must have a name")
    end

    if isnothing(version)
        timestamp, _, _ = when_internal(pkg_name, nothing)
    else
        timestamp, _, _ = when_internal(pkg_name, string(version))
    end
    return timestamp
end

"""
    when_internal(package_name::String, version::Union{String, Nothing}) -> (DateTime, Bool, String)

Internal function to get timestamp for a specific package version.
Returns a tuple of (timestamp, is_yanked, resolved_version).
"""
function when_internal(package_name::String, version::Union{String, Nothing})
    data = fetch_package_versions(package_name)

    if isempty(data)
        error("No versions found for package '$package_name'")
    end

    all_versions = sort!(collect(keys(data)), by=VersionNumber)

    if isnothing(version)
        # Get the latest version
        version = last(all_versions)
    else
        # Resolve partial versions
        version = resolve_version(data, version)
    end

    if !haskey(data, version)
        error("Version $version not found for package '$package_name'")
    end

    version_data = data[version]

    # Parse the registered timestamp
    registered = version_data["registered"]
    timestamp = if registered isa DateTime
        registered
    else
        DateTime(string(registered), dateformat"yyyy-mm-ddTHH:MM:SS")
    end

    # Check if yanked (presence of "yanked" key indicates yanked)
    yanked = haskey(version_data, "yanked")

    return (timestamp, yanked, version)
end

"""
    resolve_version(data::Dict, partial_version::String) -> String

Resolve a partial version to a full version string.

If the exact version exists, return it.
If it's a partial version (e.g., "1.9"), find the first matching non-yanked version.

Note: Skips yanked versions when resolving partial versions, but allows exact yanked versions.
"""
function resolve_version(data::AbstractDict, partial_version::String)
    all_versions = sort!(collect(keys(data)), by=VersionNumber)

    # First, check if the exact version exists
    if partial_version in all_versions
        return partial_version
    end

    # For partial version resolution, skip yanked versions
    non_yanked = filter(v -> !haskey(data[v], "yanked"), all_versions)

    # Add a dot to ensure we match version prefixes properly
    # e.g., "1.9" should match "1.9.0" but not "1.90.0"
    search_prefix = partial_version * "."
    matching = filter(v -> startswith(v, search_prefix), non_yanked)

    if isempty(matching)
        # Try without the dot
        matching = filter(v -> startswith(v, partial_version), non_yanked)
    end

    if isempty(matching)
        error("Version $partial_version not found for package (or all matching versions are yanked)")
    end

    return first(matching)
end

"""
    update_cache!()

Clear the in-session metadata cache, so subsequent queries will fetch fresh data from the API.
"""
function update_cache!()
    empty!(VERSION_CACHE)
    @info "Metadata cache cleared. Next query will fetch fresh data from GeneralMetadata API."
    return nothing
end

"""
    get_pkg_latest_version(package_name::String) -> Union{String, Nothing}

Get the latest version of a package from Pkg's local registry.
Returns `nothing` if Pkg registry not found or package not found.
"""
function get_pkg_latest_version(package_name::String)
    for depot in DEPOT_PATH
        registry_path = joinpath(depot, "registries", "General")
        if !isdir(registry_path)
            continue
        end

        first_letter = uppercase(string(first(package_name)))
        versions_file = joinpath(registry_path, first_letter, package_name, "Versions.toml")

        if !isfile(versions_file)
            continue
        end

        try
            versions_dict = TOML.parsefile(versions_file)
            if isempty(versions_dict)
                continue
            end
            versions = sort!(collect(keys(versions_dict)), by=VersionNumber)
            return last(versions)
        catch
            continue
        end
    end
    return nothing
end
