module PkgVersionHistory

using Dates
using JSON
using Pkg
using ReplMaker
using Scratch
using TimeZones
using gh_cli_jll

export when, update_registry!, check_pending_prs

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
