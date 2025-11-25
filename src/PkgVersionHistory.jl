module PkgVersionHistory

using Dates
using JSON
using Pkg
using Pkg.Registry: reachable_registries, RegistryInstance
using ReplMaker
using Scratch
using TimeZones
using TOML
using gh_cli_jll

export when, update_registry!, check_pending_prs, set_registry!, get_registry_url, list_registries

# Default registry configuration
const DEFAULT_REGISTRY_NAME = "General"

# Current registry configuration (mutable)
const REGISTRY_CONFIG = Ref{@NamedTuple{name::String, url::Union{String, Nothing}}}((name=DEFAULT_REGISTRY_NAME, url=nothing))

"""
    list_registries() -> Vector{@NamedTuple{name::String, url::Union{String, Nothing}}}

List all registries available in Pkg's depot.

Returns a vector of named tuples with registry name and URL.

# Examples
```julia
julia> list_registries()
[(name = "General", url = "https://github.com/JuliaRegistries/General.git"), ...]
```
"""
function list_registries()
    regs = reachable_registries()
    return [(name=r.name, url=r.repo) for r in regs]
end

"""
    set_registry!(name::String)

Set the registry to use for version queries.

The registry must be available in Pkg's depot (use `]registry add` to add new registries).

# Arguments
- `name`: The name of the registry (e.g., "General", "MyRegistry")

# Examples
```julia
# List available registries
list_registries()

# Switch to a different registry
set_registry!("MyRegistry")

# Switch back to General
set_registry!("General")
```

# See also
- [`list_registries`](@ref): List available registries
"""
function set_registry!(name::String)
    regs = reachable_registries()
    idx = findfirst(r -> r.name == name, regs)
    if isnothing(idx)
        available = join([r.name for r in regs], ", ")
        error("Registry '$name' not found. Available registries: $available")
    end
    REGISTRY_CONFIG[] = (name=name, url=regs[idx].repo)
    @info "Registry set to $name"
    return nothing
end

"""
    get_registry_url() -> Union{String, Nothing}

Get the URL for the currently configured registry.
"""
function get_registry_url()
    config = REGISTRY_CONFIG[]

    # If URL is cached, return it
    if !isnothing(config.url)
        return config.url
    end

    # Otherwise, look it up from Pkg's registries
    regs = reachable_registries()
    idx = findfirst(r -> r.name == config.name, regs)
    if !isnothing(idx)
        return regs[idx].repo
    end
    return nothing
end

"""
    get_registry_name() -> String

Get the currently configured registry name.
"""
function get_registry_name()
    return REGISTRY_CONFIG[].name
end

include("registry.jl")
include("core.jl")
include("format.jl")
include("repl.jl")
include("gh.jl")

function __init__()
    # Initialize REPL mode when running interactively
    if isinteractive()
        # Check if REPL is already active
        if isdefined(Base, :active_repl)
            # REPL is already running, initialize immediately
            try
                init_repl_mode()
            catch e
                @warn "Failed to initialize when REPL mode" exception=e
            end
        else
            # REPL not yet active, use atreplinit to defer initialization
            atreplinit() do _repl
                try
                    init_repl_mode()
                catch e
                    @warn "Failed to initialize when REPL mode" exception=e
                end
            end
        end
    end
end

end # module
