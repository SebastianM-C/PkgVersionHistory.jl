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
    check_pending_prs(package_name::String)

Check for pending PRs for a package in the General registry.
Returns information about open PRs and their AutoMerge status.
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