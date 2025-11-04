# Registry management functions

using Git
using Dates: DateTime, Second

"""
    get_registry_path()

Get the path to the local clone of the General registry.
If it doesn't exist, clone it.

Uses Scratch.jl to manage the cache directory, which provides:
- Automatic cleanup when the package is removed
- Standardized cache location management
- Integration with Julia's package system
"""
function get_registry_path()
    # Use Scratch.jl to get a persistent cache directory for this package
    # The registry will be stored in a scratch space named "General"
    scratch_dir = @get_scratch!("General")
    registry_path = scratch_dir

    # Check if the registry is already cloned
    # A bare repo will have a "config" file in the root
    if !isfile(joinpath(registry_path, "config"))
        @info "Cloning General registry to scratch space..."
        @info "Location: $registry_path"

        # Remove any partial/corrupted clone
        if isdir(registry_path)
            rm(registry_path; recursive=true, force=true)
            scratch_dir = @get_scratch!("General")
            registry_path = scratch_dir
        end

        # Clone as a bare repository (no working tree, saves space)
        try
            run(git(["clone", "--bare", "https://github.com/JuliaRegistries/General.git", registry_path]))
            @info "Registry cloned successfully"
        catch e
            @error "Failed to clone General registry" exception=(e, catch_backtrace())
            rethrow()
        end
    end

    return registry_path
end

"""
    get_pkg_registry_tarball()

Find the path to Pkg's General registry tarball.
Returns `nothing` if not found.

Pkg stores registries as tarballs (e.g., General.tar.gz), not as extracted directories.
"""
function get_pkg_registry_tarball()
    # Pkg's registries are stored as tarballs in DEPOT_PATH[i]/registries/
    for depot in DEPOT_PATH
        tarball_path = joinpath(depot, "registries", "General.tar.gz")
        if isfile(tarball_path)
            return tarball_path
        end
    end
    return nothing
end

"""
    get_pkg_registry_path()

Find the path to Pkg's General registry.
Returns `nothing` if not found.

This function is kept for backward compatibility with get_pkg_latest_version,
which needs to read Versions.toml files directly.
"""
function get_pkg_registry_path()
    # Pkg's registries are stored in DEPOT_PATH[1]/registries/General
    # Check if an extracted directory exists (older Pkg versions or extracted manually)
    for depot in DEPOT_PATH
        registry_path = joinpath(depot, "registries", "General")
        if isdir(registry_path)
            return registry_path
        end
    end
    return nothing
end

"""
    get_registry_last_update(registry_path::String) -> Union{DateTime, Nothing}

Get the timestamp of the last update to a registry.
Returns `nothing` if unable to determine.
"""
function get_registry_last_update(registry_path::String)
    try
        # Use Git.jl to get the commit timestamp for HEAD
        # This works reliably with both bare and regular repositories
        timestamp_str = readchomp(git(["-C", registry_path, "log", "-1", "--format=%at", "HEAD"]))
        timestamp_unix = parse(Int64, timestamp_str)

        # Convert from Unix timestamp to DateTime
        return DateTime(1970) + Second(timestamp_unix)
    catch e
        # Log the error for debugging
        @debug "Failed to get registry timestamp" exception=e
        return nothing
    end
end

"""
    get_tarball_last_update(tarball_path::String) -> Union{DateTime, Nothing}

Get the modification time of a registry tarball.
Returns `nothing` if unable to determine.
"""
function get_tarball_last_update(tarball_path::String)
    try
        # Get the file modification time
        mtime = stat(tarball_path).mtime
        # Convert Unix timestamp to DateTime
        return DateTime(1970) + Second(round(Int64, mtime))
    catch e
        @debug "Failed to get tarball modification time" exception=e
        return nothing
    end
end

"""
    should_update_registry() -> Bool

Check if our cached registry should be updated by comparing with Pkg's registry.
Returns true if our cache is older than Pkg's registry.

Supports both modern Pkg (using compressed tarball) and older Pkg versions
(using unpacked directory).
"""
function should_update_registry()
    # Get our registry timestamp
    our_registry = get_registry_path()
    our_timestamp = get_registry_last_update(our_registry)

    if isnothing(our_timestamp)
        # Can't determine our timestamp, assume we should update
        return true
    end

    # Check both tarball (modern Pkg with package servers) and directory (older Pkg)
    # Use whichever is newer
    pkg_timestamp = nothing

    # Check for compressed tarball (modern Pkg)
    pkg_tarball = get_pkg_registry_tarball()
    if !isnothing(pkg_tarball)
        tarball_timestamp = get_tarball_last_update(pkg_tarball)
        if !isnothing(tarball_timestamp)
            pkg_timestamp = tarball_timestamp
        end
    end

    # Check for unpacked directory (older Pkg versions)
    pkg_registry = get_pkg_registry_path()
    if !isnothing(pkg_registry)
        dir_timestamp = get_registry_last_update(pkg_registry)
        if !isnothing(dir_timestamp)
            # Use the newer of the two timestamps if both exist
            if isnothing(pkg_timestamp) || dir_timestamp > pkg_timestamp
                pkg_timestamp = dir_timestamp
            end
        end
    end

    # If we couldn't find either format, don't auto-update
    if isnothing(pkg_timestamp)
        return false
    end

    # Update if Pkg's registry is newer
    return pkg_timestamp > our_timestamp
end

"""
    update_registry!()

Update the local clone of the General registry.
In a bare repository, we need to both fetch and update the branch reference.
"""
function update_registry!()
    registry_path = get_registry_path()
    @info "Updating registry..."

    try
        # Fetch only the master branch from origin
        # We only need master, and fetching all branches can fail with non-fast-forward errors
        # on registrator branches, which would prevent refs from being updated properly
        run(git(["-C", registry_path, "fetch", "origin", "refs/heads/master:refs/remotes/origin/master"]))

        # Update master branch to point to origin/master
        # Get the hash of origin/master
        origin_master_hash = readchomp(git(["-C", registry_path, "rev-parse", "refs/remotes/origin/master"]))

        # Update refs/heads/master to point to origin/master
        run(git(["-C", registry_path, "update-ref", "refs/heads/master", origin_master_hash]))

        # Make sure HEAD points to master (for bare repos)
        run(git(["-C", registry_path, "symbolic-ref", "HEAD", "refs/heads/master"]))

        @info "Registry updated"
    catch e
        if occursin("authentication", lowercase(string(e)))
            @warn "Registry update failed due to authentication. The cached registry will be used." exception=(e, catch_backtrace())
        else
            @warn "Registry update failed. The cached registry will be used." exception=(e, catch_backtrace())
        end
    end

    return nothing
end

"""
    ensure_registry_up_to_date!()

Ensure our cached registry is not older than Pkg's registry.
Automatically updates if our cache is stale.
"""
function ensure_registry_up_to_date!()
    if should_update_registry()
        @info "Registry cache is older than Pkg's registry, updating..."
        try
            update_registry!()
        catch e
            # Silently continue with cached registry if update fails
            # The update_registry! function will have already logged a warning if needed
        end
    end
end

"""
    get_pkg_latest_version(package_name::String) -> Union{String, Nothing}

Get the latest version of a package from Pkg's local registry.
Returns `nothing` if Pkg registry not found or package not found.
"""
function get_pkg_latest_version(package_name::String)
    # Get Pkg's registry path
    pkg_registry = get_pkg_registry_path()
    if isnothing(pkg_registry)
        return nothing
    end

    # Construct path to the package's Versions.toml in Pkg's registry
    # Note that git expects `/` always
    first_letter = uppercase(string(first(package_name)))
    versions_file = "$pkg_registry/$first_letter/$package_name/Versions.toml"

    if !isfile(versions_file)
        return nothing
    end

    try
        # Read and parse the Versions.toml file

        # Extract all version numbers
        versions = String[]
        for line in eachline(versions_file)
            m = match(r"^\[\"(.+?)\"\]", line)
            if !isnothing(m)
                push!(versions, m.captures[1])
            end
        end

        if isempty(versions)
            return nothing
        end

        # Return the last version (assuming they're in order)
        return last(versions)
    catch
        return nothing
    end
end

"""
    get_package_path(registry_path::String, package_name::String)

Get the path to a package directory in the registry.
Returns `nothing` if the package doesn't exist.
"""
function get_package_path(registry_path::String, package_name::String)
    # Packages are organized by first letter and package name
    # Note that git expects `/` always
    first_letter = uppercase(string(first(package_name)))
    pkg_path = "$first_letter/$package_name"

    # Check if the Versions.toml file exists for this package
    versions_file = "$pkg_path/Versions.toml"

    # Use git ls-tree to check if this path exists in the repo
    try
        # Check if the file exists in HEAD
        output = read(git(["-C", registry_path, "ls-tree", "HEAD", versions_file]), String)
        # git ls-tree returns empty output if the file doesn't exist
        if isempty(strip(output))
            return nothing
        else
            return pkg_path
        end
    catch
        # If git command fails
        return nothing
    end
end
