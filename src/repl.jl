# REPL mode integration using ReplMaker

using ReplMaker
using REPL

"""
    init_repl_mode()

Initialize a custom REPL mode for the `when` command.
This creates a new REPL mode activated with `}` (similar to `]` for Pkg mode).
"""
function init_repl_mode()
    # Initialize the REPL mode using ReplMaker
    # Use `}` as the trigger character (next to `]` on keyboard)
    ReplMaker.initrepl(
        parse_when_command,
        prompt_text="when> ",
        prompt_color=:cyan,
        start_key='}',
        mode_name="when_repl_mode",
        startup_text=false
    )
end

"""
    parse_when_command(input::String)

Parse input from the when REPL mode and convert it to Julia code that will be executed.
This function is called by ReplMaker for each line entered in the `when>` prompt.
"""
function parse_when_command(input::String)
    # Trim the input and convert to String (strip returns SubString)
    input_str = String(strip(input))

    # Handle empty input
    if isempty(input_str)
        return nothing
    end

    # Handle help
    if input_str == "help" || input_str == "?"
        return :(begin
            println("Available commands:")
            println("  when <package>              - Check latest version (and pending PRs)")
            println("  when <package>@<version>    - Check specific version registration time")
            println("  when <pkg1> <pkg2> ...      - Check multiple packages")
            println("  refresh                      - Update the local registry cache")
            println("  help                         - Show this help message")
            println()
            println("Examples:")
            println("  when> when Example")
            println("  when> when Example@1.2.3")
            println("  when> when JSON DataFrames HTTP")
            println("  when> refresh")
            println()
            println("Note: Registry is automatically updated if older than Pkg's registry.")
            println("Press backspace to return to julia> prompt")
        end)
    end

    # Parse the command
    parts = split(input_str)
    if isempty(parts)
        return nothing
    end

    command = String(parts[1])

    if command == "when"
        # Extract package specs (everything after "when")
        if length(parts) < 2
            return :(println("Usage: when <package> [<package>...]"))
        end
        package_specs = join(parts[2:end], " ")
        return :(PkgVersionHistory.execute_when_command($package_specs))
    elseif command == "refresh"
        return :(PkgVersionHistory.execute_refresh_command())
    else
        return :(println("Unknown command: $command. Type 'help' for usage information."))
    end
end

"""
    execute_when_command(line::String)

Execute the `when` command from the REPL.
"""
function execute_when_command(line::String)
    # Parse the command line (convert SubStrings to Strings)
    parts = String.(split(strip(line)))

    if isempty(parts)
        println("Type 'help' for usage information")
        return
    end

    # Process each package
    # Note: ensure_registry_up_to_date!() is called in when_internal()
    for pkg_spec in parts
        execute_when_for_package(pkg_spec)
    end
end

"""
    execute_when_for_package(pkg_spec::String)

Execute the when query for a single package specification.
If no version is specified, also checks for pending PRs and local registry status.
"""
function execute_when_for_package(pkg_spec::String)
    try
        # Parse package name and version
        parts = split(pkg_spec, '@')
        pkg_name = String(parts[1])
        version = length(parts) > 1 ? String(parts[2]) : nothing

        # Get the timestamp and yanked status
        timestamp, yanked, resolved_version = when_internal(pkg_name, version)

        # Format and print the output
        output = format_when_output(pkg_name, resolved_version, timestamp, yanked)
        println(output)

        # If no version was specified (asking for latest), check additional info
        if isnothing(version)
            # Check local registry version
            try
                local_version = get_pkg_latest_version(pkg_name)
                if !isnothing(local_version) && local_version != resolved_version
                    println()
                    # Parse versions for comparison
                    local_v = VersionNumber(local_version)
                    registry_v = VersionNumber(resolved_version)

                    if local_v < registry_v
                        printstyled("  Note: ", color=:yellow)
                        println("Your local registry has $pkg_name@$local_version")
                        printstyled("  Run ", color=:cyan)
                        printstyled("] registry update", color=:cyan, bold=true)
                        printstyled(" to get the latest version\n", color=:cyan)
                    elseif local_v > registry_v
                        # This shouldn't happen but handle it gracefully
                        printstyled("  Note: ", color=:yellow)
                        println("Your local registry has a newer version: $pkg_name@$local_version")
                    end
                end
            catch e
                # Silently ignore local version check errors
            end

            # Check for pending PRs
            try
                prs = check_pending_prs(pkg_name)

                if !isnothing(prs) && !isempty(prs)
                    println()
                    printstyled("  Pending PR(s):\n", color=:yellow)
                    for pr in prs
                        println("  ", format_pending_pr(pr))
                    end
                end
            catch e
                # Silently ignore PR check errors (e.g., gh not installed)
                # The version info is the primary goal
            end
        end
    catch e
        printstyled("Error querying $pkg_spec: ", color=:red, bold=true)
        println(sprint(showerror, e))
    end
end

# Removed dead code: execute_pending_check function was never used

"""
    execute_refresh_command()

Execute the refresh command to update the registry cache.
"""
function execute_refresh_command()
    try
        printstyled("Updating registry cache...\n", color=:cyan)
        update_registry!()
        printstyled("Registry updated successfully!\n", color=:green)
    catch e
        printstyled("Error updating registry: ", color=:red, bold=true)
        println(sprint(showerror, e))
    end
end
