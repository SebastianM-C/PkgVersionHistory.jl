# GitHub CLI integration for checking pending PRs

using gh_cli_jll

"""
    get_gh_command()

Get the gh command, preferring system installation over JLL.
"""
function get_gh_command()
    # First check if gh is installed on the system
    if !isnothing(Sys.which("gh"))
        return `gh`
    else
        # Use gh_cli_jll as fallback
        return `$(gh_cli_jll.gh())`
    end
end

"""
    check_pending_prs(package_name::String) -> Union{Vector{Dict}, Nothing}

Check for pending PRs for a package in the General registry.

Uses the GitHub CLI to search for open pull requests in JuliaRegistries/General
that mention the specified package name.

# Arguments
- `package_name::String`: The name of the package to search for

# Returns
- `Vector{Dict}`: Array of PR information dictionaries, each containing:
  - `number`: PR number
  - `title`: PR title
  - `author`: Author information (with `login` field)
  - `createdAt`: Creation timestamp (ISO 8601 format)
  - `labels`: Array of label information (each with `name` field)
- `nothing`: If no PRs found or if GitHub CLI is unavailable

# Examples
```julia
# Check for pending PRs
prs = check_pending_prs("OptimizationMadNLP")

if !isnothing(prs)
    for pr in prs
        println("PR #\$(pr["number"]): \$(pr["title"])")

        # Check for AutoMerge label
        has_automerge = any(l -> l["name"] == "automerge", pr["labels"])
        if has_automerge
            println("  [Will auto-merge]")
        end
    end
else
    println("No pending PRs found")
end
```

# Notes
- Requires GitHub CLI (`gh`) to be installed, or uses `gh_cli_jll` as fallback
- Returns `nothing` if the search fails or if no PRs are found
- The search looks for PRs with the package name in the title or body
"""
function check_pending_prs(package_name::String)
    gh_cmd = get_gh_command()

    # Search for PRs in JuliaRegistries/General that mention the package
    search_query = "repo:JuliaRegistries/General is:pr is:open \"$package_name\""

    try
        # Get list of open PRs
        output = read(`$gh_cmd pr list --repo JuliaRegistries/General --search $search_query --json number,title,createdAt,labels,author`, String)

        if isempty(strip(output)) || strip(output) == "[]"
            return nothing
        end

        # Parse JSON output
        prs = JSON.parse(output)

        return prs
    catch e
        @warn "Failed to check pending PRs" exception=e
        return nothing
    end
end

"""
    format_pending_pr(pr::Dict) -> String

Format a pending PR for display.
"""
function format_pending_pr(pr::Dict)
    number = pr["number"]
    title = pr["title"]
    author = pr["author"]["login"]
    created = pr["createdAt"]

    # Parse the timestamp
    created_dt = DateTime(created[1:19], dateformat"yyyy-mm-ddTHH:MM:SS")
    relative = format_relative_time(created_dt)

    # Check for AutoMerge label
    labels = pr["labels"]
    has_automerge = any(l -> l["name"] == "automerge", labels)
    automerge_str = has_automerge ? " [AutoMerge]" : ""

    return "  PR #$number: $title\n    by @$author, opened $relative$automerge_str"
end