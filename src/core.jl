# Core functionality for querying package version timestamps

using Git
using Dates: DateTime, Second

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
        # Get latest version from registry
        version = get_latest_version(pkg_name)
    end

    timestamp, _ = when_internal(pkg_name, string(version))
    return timestamp
end

"""
    when_internal(package_name::String, version::Union{String, Nothing}) -> (DateTime, Bool, String)

Internal function to get timestamp for a specific package version.
Returns a tuple of (timestamp, is_yanked, resolved_version).
"""
function when_internal(package_name::String, version::Union{String, Nothing})
    # Ensure registry is up to date (checks against Pkg's registry)
    ensure_registry_up_to_date!()

    registry_path = get_registry_path()
    pkg_path = get_package_path(registry_path, package_name)

    if isnothing(pkg_path)
        error("Package '$package_name' not found in General registry")
    end

    versions_file = "$(pkg_path)/Versions.toml"

    # If no version specified, get the latest
    if isnothing(version)
        version = get_latest_version_from_file(registry_path, versions_file)
    else
        # Resolve partial versions (e.g., "1.9" -> "1.9.0")
        version = resolve_version(registry_path, versions_file, version)
    end

    # Check if version is yanked
    yanked = is_version_yanked(registry_path, versions_file, version)

    # Find the commit that added or last modified this version entry
    timestamp = get_version_timestamp(registry_path, versions_file, version)

    return (timestamp, yanked, version)
end

"""
    get_latest_version(package_name::String) -> String

Get the latest version of a package from the registry.
"""
function get_latest_version(package_name::String)
    registry_path = get_registry_path()
    pkg_path = get_package_path(registry_path, package_name)

    if isnothing(pkg_path)
        error("Package '$package_name' not found in General registry")
    end

    versions_file = "$(pkg_path)/Versions.toml"
    return get_latest_version_from_file(registry_path, versions_file)
end

"""
    read_file_from_repo(registry_path::String, file_path::String) -> String

Read file content from the Git repository at HEAD.
"""
function read_file_from_repo(registry_path::String, file_path::String)
    # Use git show to read file content from HEAD
    content = read(git(["-C", registry_path, "show", "HEAD:$file_path"]), String)
    return content
end

"""
    get_all_versions_from_file(registry_path::String, versions_file::String; include_yanked::Bool=true) -> Vector{String}

Get all versions from a Versions.toml file.

# Arguments
- `registry_path`: Path to the registry
- `versions_file`: Path to the Versions.toml file (relative to registry)
- `include_yanked`: Whether to include yanked versions (default: true)

# Returns
Vector of version strings
"""
function get_all_versions_from_file(registry_path::String, versions_file::String; include_yanked::Bool=true)
    # Get the content of Versions.toml
    content = read_file_from_repo(registry_path, versions_file)

    # Parse versions and check for yanked flag
    versions = String[]
    current_version = nothing
    is_yanked = false

    for line in split(content, '\n')
        # Check for version header
        if occursin(r"^\[\"(.+?)\"\]", line)
            # Save previous version if not yanked (or if we include yanked)
            if !isnothing(current_version) && (include_yanked || !is_yanked)
                push!(versions, current_version)
            end

            # Start new version
            m = match(r"^\[\"(.+?)\"\]", line)
            current_version = m.captures[1]
            is_yanked = false
        elseif occursin(r"^yanked\s*=\s*true", line)
            # Mark current version as yanked
            is_yanked = true
        end
    end

    # Don't forget the last version
    if !isnothing(current_version) && (include_yanked || !is_yanked)
        push!(versions, current_version)
    end

    if isempty(versions)
        error("No versions found in $versions_file")
    end

    return versions
end

"""
    is_version_yanked(registry_path::String, versions_file::String, version::String) -> Bool

Check if a specific version is yanked.
"""
function is_version_yanked(registry_path::String, versions_file::String, version::String)
    # Get the content of Versions.toml
    content = read_file_from_repo(registry_path, versions_file)

    # Find the version section and check for yanked flag
    in_version_section = false
    for line in split(content, '\n')
        # Check if we're entering the target version section
        if occursin(Regex("^\\[\"$(replace(version, "." => "\\."))\"\\]"), line)
            in_version_section = true
        # Check if we're entering a new version section
        elseif occursin(r"^\[\"", line)
            in_version_section = false
        # Check for yanked flag in current section
        elseif in_version_section && occursin(r"^yanked\s*=\s*true", line)
            return true
        end
    end

    return false
end

"""
    get_latest_version_from_file(registry_path::String, versions_file::String) -> String

Extract the latest version from a Versions.toml file.
"""
function get_latest_version_from_file(registry_path::String, versions_file::String)
    versions = get_all_versions_from_file(registry_path, versions_file)
    # Return the last version (assuming they're in order)
    return last(versions)
end

"""
    resolve_version(registry_path::String, versions_file::String, partial_version::String) -> String

Resolve a partial version to a full version.
For example, "1.9" might resolve to "1.9.0" or "1.9.1" depending on what exists.

If the exact version exists, return it.
If it's a partial version (e.g., "1.9"), find the first matching non-yanked version that starts with it.

Note: Skips yanked versions when resolving partial versions, but allows exact yanked versions.
"""
function resolve_version(registry_path::String, versions_file::String, partial_version::String)
    # Get all versions including yanked ones
    all_versions = get_all_versions_from_file(registry_path, versions_file; include_yanked=true)

    # First, check if the exact version exists
    if partial_version in all_versions
        return partial_version
    end

    # For partial version resolution, skip yanked versions
    non_yanked_versions = get_all_versions_from_file(registry_path, versions_file; include_yanked=false)

    # Try to find a matching version
    # Add a dot to ensure we match version prefixes properly
    # e.g., "1.9" should match "1.9.0" but not "1.90.0"
    search_prefix = partial_version * "."

    matching_versions = filter(v -> startswith(v, search_prefix), non_yanked_versions)

    if isempty(matching_versions)
        # No matches found, maybe they provided a partial without the last component
        # Try searching without the dot
        matching_versions = filter(v -> startswith(v, partial_version), non_yanked_versions)
    end

    if isempty(matching_versions)
        error("Version $partial_version not found in $versions_file (or all matching versions are yanked)")
    end

    # Return the first matching version (typically the earliest patch version)
    return first(matching_versions)
end

"""
    get_version_timestamp(registry_path::String, versions_file::String, version::String) -> DateTime

Get the timestamp when a specific version was added to the registry.
"""
function get_version_timestamp(registry_path::String, versions_file::String, version::String)
    # Use git log -S to efficiently find when this version string was added
    # The -S option (pickaxe) finds commits that introduced or removed the string
    search_pattern = "[\"$version\"]"

    # Run git log with -S to find commits that added this string
    # --format=%at outputs the commit timestamp
    # --reverse shows oldest first
    try
        # Use Git.jl to run git log -S to find when the version string was added
        cmd = git(["-C", registry_path, "log", "-S", search_pattern, "--format=%at", "--reverse", "--", versions_file])
        output = read(cmd, String)

        if isempty(strip(output))
            error("Version $version not found in $versions_file")
        end

        # Get the first timestamp (when the version was added)
        timestamps = split(strip(output), '\n')
        timestamp_unix = parse(Int64, timestamps[1])

        # Convert from Unix timestamp to DateTime
        return DateTime(1970) + Second(timestamp_unix)
    catch e
        error("Failed to get timestamp for version $version: $e")
    end
end