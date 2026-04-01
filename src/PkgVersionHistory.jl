module PkgVersionHistory

using Dates
using Downloads
using JSON
using Pkg
using ReplMaker
using TOML
using gh_cli_jll

export when, update_cache!, check_pending_prs

# Session cache for API responses: package_name => Dict(version => metadata)
const VERSION_CACHE = Dict{String, Dict{String, Any}}()

const API_BASE = "https://juliaregistries.github.io/GeneralMetadata.jl/api"

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
