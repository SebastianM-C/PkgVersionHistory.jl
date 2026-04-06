module PkgVersionHistory

using Dates
using JSON
using Pkg
using Pkg.Registry: reachable_registries, RegistryInstance
using Preferences
using ReplMaker
using Scratch
using TimeZones
using TOML
using gh_cli_jll

export when, update_registry!, update_cache!, check_pending_prs
export set_registry!, get_registry_url, list_registries
export set_backend!, get_backend

# Default registry configuration
const DEFAULT_REGISTRY_NAME = "General"

# Current registry configuration (mutable)
const REGISTRY_CONFIG = Ref{@NamedTuple{name::String, url::Union{String, Nothing}}}((name=DEFAULT_REGISTRY_NAME, url=nothing))

# Backend preference: "git" (default) or "api"
const BACKEND = Ref{Symbol}(:git)

"""
    get_backend() -> Symbol

Get the currently active backend (`:git` or `:api`).
"""
get_backend() = BACKEND[]

"""
    set_backend!(backend::Union{String, Symbol})

Set the backend for version queries. Valid values: `:git` or `:api`.

- `:git` (default) — queries the General registry git history directly via a local
  clone managed by Scratch.jl (~400 MB). Provides fresh data immediately.
- `:api` — queries the GeneralMetadata.jl web API. No disk space needed, but data
  may be up to ~24 hours stale (the API updates daily around midnight UTC).

The preference is saved persistently in `LocalPreferences.toml`.

# Examples
```julia
set_backend!(:api)   # switch to lightweight API backend
set_backend!(:git)   # switch back to git backend
```
"""
function set_backend!(backend::Union{String, Symbol})
    b = Symbol(backend)
    if b ∉ (:git, :api)
        error("Invalid backend '$backend'. Must be :git or :api")
    end
    BACKEND[] = b
    @set_preferences!("backend" => string(b))
    @info "Backend set to :$b (saved to LocalPreferences.toml)"
    return nothing
end

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
include("api.jl")
include("format.jl")
include("repl.jl")
include("gh.jl")

function __init__()
    # Load backend preference
    backend = @load_preference("backend", "git")
    BACKEND[] = Symbol(backend)

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
