# REPL mode integration built directly on REPL.LineEdit.
#
# ReplMaker.jl is deliberately not used here: `ReplMaker.initrepl` calls
# `REPL.LineEdit.setup_search_keymap`, which Julia 1.13 removed along with the old
# incremental ^R/^S search prompt (superseded by `LineEdit.history_search`, which is
# already part of `LineEdit.history_keymap`). Driving LineEdit ourselves lets us
# feature-detect the handful of internals that moved between 1.10 and 1.13.

using REPL
using REPL: LineEdit

"Name this mode is registered under in the shared history provider."
const MODE_NAME = :when_repl_mode

"Key that switches from `julia>` into `when>`."
const START_KEY = '}'

"""
    search_prompt_and_keymap(hp) -> (prompt, keymap)

Build the incremental history-search prompt and keymap for a custom mode, when this
Julia version still has one.

Up to Julia 1.12, `LineEdit.setup_search_keymap` returned a `(prompt, keymap)` pair that
every non-`julia>` mode had to splice into its own keymap to get ^R/^S search. Julia 1.13
removed it: ^R/^S now call `LineEdit.history_search`, which lives in
`LineEdit.history_keymap` and needs no separate prompt. Returns `(nothing, nothing)` there.
"""
function search_prompt_and_keymap(hp)
    if isdefined(LineEdit, :setup_search_keymap)
        return LineEdit.setup_search_keymap(hp)
    end
    return (nothing, nothing)
end

"""
    auto_closing_brackets(repl) -> Bool

Whether this REPL auto-inserts closing brackets (Julia 1.13+, enabled by default).
"""
function auto_closing_brackets(repl)
    isdefined(LineEdit, :bracket_insert_keymap) || return false
    opts = repl.options
    return hasproperty(opts, :auto_insert_closing_bracket) && opts.auto_insert_closing_bracket
end

"""
    insert_start_key(repl, s::LineEdit.MIState)

Handle `}` when it should *not* switch modes, i.e. mid-line.

This mirrors how Base handles `]` for the Pkg mode: with auto-closing brackets on, typing
a closing brace that is already sitting under the cursor steps over it rather than
inserting a duplicate.
"""
function insert_start_key(repl, s::LineEdit.MIState)
    if auto_closing_brackets(repl)
        buf = LineEdit.buffer(s)
        if !eof(buf) && peek(buf, Char) == START_KEY
            LineEdit.edit_move_right(buf)
        else
            LineEdit.edit_insert(buf, START_KEY)
        end
        LineEdit.refresh_line(s)
    else
        LineEdit.edit_insert(s, START_KEY)
    end
    return nothing
end

"""
    init_repl_mode(repl = Base.active_repl)

Initialize a custom REPL mode for the `when` command.
This creates a new REPL mode activated with `}` (similar to `]` for Pkg mode).
"""
function init_repl_mode(repl = Base.active_repl)
    if !isdefined(repl, :interface)
        repl.interface = REPL.setup_interface(repl)
    end
    julia_mode = repl.interface.modes[1]

    prefix = repl.hascolor ? Base.text_colors[:cyan] : ""
    suffix = repl.hascolor ? (repl.envcolors ? Base.input_color : repl.input_color()) : ""

    when_mode = LineEdit.Prompt("when> ";
        prompt_prefix = prefix,
        prompt_suffix = suffix,
        complete = REPL.REPLCompletionProvider(),
        sticky = true,
    )
    when_mode.on_done = REPL.respond(parse_when_command, repl, when_mode)

    # Share the julia mode's history, tagged so `when>` lines are replayed into `when>`.
    hp = julia_mode.hist
    hp.mode_mapping[MODE_NAME] = when_mode
    when_mode.hist = hp

    search_prompt, skeymap = search_prompt_and_keymap(hp)
    prefix_prompt, prefix_keymap = LineEdit.setup_prefix_keymap(hp, when_mode)

    # Same layering Base uses for shell/help/pkg modes, minus the pieces this Julia
    # version does not have.
    keymaps = Dict{Any, Any}[REPL.mode_keymap(julia_mode), prefix_keymap, LineEdit.history_keymap]
    isnothing(skeymap) || pushfirst!(keymaps, skeymap)
    auto_closing_brackets(repl) && push!(keymaps, LineEdit.bracket_insert_keymap)
    push!(keymaps, LineEdit.default_keymap, LineEdit.escape_defaults)
    when_mode.keymap_dict = LineEdit.keymap(keymaps)

    # `}` at the start of an empty buffer enters the mode; anywhere else it is a brace.
    julia_mode.keymap_dict = LineEdit.keymap_merge(julia_mode.keymap_dict, Dict{Any, Any}(
        START_KEY => function (s::LineEdit.MIState, o...)
            if isempty(s) || position(LineEdit.buffer(s)) == 0
                buf = copy(LineEdit.buffer(s))
                LineEdit.transition(s, when_mode) do
                    LineEdit.state(s, when_mode).input_buffer = buf
                end
            else
                insert_start_key(repl, s)
            end
        end,
    ))

    push!(repl.interface.modes, when_mode)
    isnothing(search_prompt) || push!(repl.interface.modes, search_prompt)
    push!(repl.interface.modes, prefix_prompt)

    return when_mode
end

"""
    parse_when_command(input::String)

Parse input from the when REPL mode and convert it to Julia code that will be executed.
This function is called for each line entered at the `when>` prompt.
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
        return :(PkgVersionHistory.show_repl_help())
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
    elseif command == "registry"
        # Handle registry subcommands
        if length(parts) < 2
            return :(PkgVersionHistory.show_registry_help())
        end
        subcommand = String(parts[2])
        args = length(parts) > 2 ? String.(parts[3:end]) : String[]
        return :(PkgVersionHistory.execute_registry_command($subcommand, $args))
    elseif command == "refresh"
        return :(PkgVersionHistory.execute_refresh())
    elseif command == "backend"
        if length(parts) < 2
            return :(println("Current backend: $(PkgVersionHistory.get_backend())"))
        end
        backend = String(parts[2])
        return :(PkgVersionHistory.set_backend!($backend))
    else
        return :(println("Unknown command: $command. Type 'help' for usage information."))
    end
end

"""
    show_repl_help()

Show help for the REPL mode.
"""
function show_repl_help()
    println("Available commands:")
    println("  when <package>              - Check latest version (and pending PRs)")
    println("  when <package>@<version>    - Check specific version registration time")
    println("  when <pkg1> <pkg2> ...      - Check multiple packages")
    println("  refresh                     - Update registry cache / clear API cache")
    println("  backend                     - Show current backend")
    println("  backend <git|api>           - Switch backend (saved to LocalPreferences.toml)")
    println("  registry show               - Show current registry (git backend)")
    println("  registry list               - List available registries (git backend)")
    println("  registry use <name>         - Switch to a different registry (git backend)")
    println("  help                        - Show this help message")
    println()
    println("Examples:")
    println("  when> when Example")
    println("  when> when Example@1.2.3")
    println("  when> when JSON DataFrames HTTP")
    println("  when> backend api           # switch to lightweight API backend")
    println()
    println("Current backend: $(get_backend())")
    println("Press backspace to return to julia> prompt")
end

"""
    show_registry_help()

Show help for registry subcommands.
"""
function show_registry_help()
    println("Registry subcommands:")
    println("  registry show               - Show current registry")
    println("  registry list               - List available registries")
    println("  registry use <name>         - Switch to a different registry")
    println("  registry refresh            - Update the registry cache")
end

"""
    execute_registry_command(subcommand::String, args::Vector{String})

Execute a registry subcommand.
"""
function execute_registry_command(subcommand::String, args::Vector{String})
    if subcommand == "show"
        execute_registry_show()
    elseif subcommand == "list"
        execute_registry_list()
    elseif subcommand == "use"
        if isempty(args)
            println("Usage: registry use <name>")
            println("Use 'registry list' to see available registries.")
        else
            execute_registry_use(args[1])
        end
    elseif subcommand == "refresh"
        execute_registry_refresh()
    else
        println("Unknown registry subcommand: $subcommand")
        show_registry_help()
    end
end

"""
    execute_registry_show()

Show the current registry configuration.
"""
function execute_registry_show()
    name = get_registry_name()
    url = get_registry_url()
    println("Current registry: $name")
    if !isnothing(url)
        println("  URL: $url")
    end
end

"""
    execute_registry_list()

List all available registries.
"""
function execute_registry_list()
    current = get_registry_name()
    regs = list_registries()

    println("Available registries:")
    for reg in regs
        marker = reg.name == current ? " *" : "  "
        printstyled(marker, color = reg.name == current ? :green : :default)
        println(" $(reg.name)")
        if !isnothing(reg.url)
            println("     $(reg.url)")
        end
    end
    println()
    printstyled(" * ", color=:green)
    println("= current registry")
end

"""
    execute_registry_use(name::String)

Switch to a different registry.
"""
function execute_registry_use(name::String)
    try
        set_registry!(name)
        printstyled("Switched to registry: $name\n", color=:green)
    catch e
        printstyled("Error: ", color=:red, bold=true)
        println(sprint(showerror, e))
    end
end

"""
    execute_refresh()

Refresh data: update the git registry cache or clear the API cache,
depending on the active backend.
"""
function execute_refresh()
    if get_backend() == :api
        try
            printstyled("Clearing API metadata cache...\n", color=:cyan)
            update_cache!()
            printstyled("Cache cleared successfully!\n", color=:green)
        catch e
            printstyled("Error clearing cache: ", color=:red, bold=true)
            println(sprint(showerror, e))
        end
    else
        execute_registry_refresh()
    end
end

"""
    execute_registry_refresh()

Update the registry cache.
"""
function execute_registry_refresh()
    try
        name = get_registry_name()
        printstyled("Updating $name registry cache...\n", color=:cyan)
        update_registry!()
        printstyled("Registry updated successfully!\n", color=:green)
    catch e
        printstyled("Error updating registry: ", color=:red, bold=true)
        println(sprint(showerror, e))
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

