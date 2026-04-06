# PkgVersionHistory.jl

[![CI](https://github.com/SebastianM-C/PkgVersionHistory.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/SebastianM-C/PkgVersionHistory.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/SebastianM-C/PkgVersionHistory.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/SebastianM-C/PkgVersionHistory.jl)

A Julia package to check when package versions were registered in Julia registries.

> **⚠️ Experimental Package**: This package is vibe-coded and considered experimental. APIs may change, and there might be rough edges. Use with appropriate caution in production environments.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/SebastianM-C/PkgVersionHistory.jl")
```

## Features

- **Check registration timestamps**: Find out when a specific package version was registered
- **Two backends**: Git-based (default, fresh data) or web API (lightweight, no disk space)
- **Multiple registries**: Query any registry in your Pkg depot (git backend)
- **REPL integration**: Use the convenient `when` command in a custom REPL mode (`}`)
- **Multiple packages**: Query multiple packages at once
- **Yanked version detection**: Identify yanked versions with clear `[YANKED]` markers
- **Pending PRs**: Automatically check for open registration PRs when querying latest versions
- **Local registry status**: Compare with your local Pkg registry and get notified when it's behind
- **Automatic updates**: Registry cache automatically stays in sync with your Pkg registry
- **Programmatic API**: Use the `when()` function in your code

## Usage

### REPL Mode

The package adds a custom REPL mode activated with `}`:

```julia-repl
julia> using PkgVersionHistory

# Press } to enter the when REPL mode
when> when Example

# Check specific version (full or partial)
when> when Example@1.2.3
when> when Example@0.5      # Resolves to 0.5.0 automatically

# Check multiple packages
when> when JSON DataFrames HTTP

# Refresh data (update registry or clear API cache)
when> refresh

# Switch backend
when> backend api            # lightweight, no disk space
when> backend git            # fresh data (default)

# Registry management (git backend)
when> registry show         # Show current registry
when> registry list         # List available registries
when> registry use General  # Switch to a different registry

# Get help
when> help

# Press backspace to return to julia> prompt
```

**Version Resolution:** The package automatically resolves partial versions, just like Pkg does:

```julia-repl
when> when Optim@1.9      # Automatically resolves to 1.9.0
when> when Example@0      # Resolves to first 0.x.x version
```

**Yanked Versions:** The package handles yanked versions intelligently:
- Partial version resolution (e.g., `@1.9`) skips yanked versions automatically
- Exact yanked versions (e.g., `@1.9.0`) can still be queried and show the registration time
- Yanked status is clearly indicated with `[YANKED]` in the output
- Yanked versions are distinguishable from non-existent versions: a non-existent version gives an error, while a yanked exact version returns its registration time with the `[YANKED]` marker

**Pending PRs:** When you check the latest version of a package (without specifying a version), the package automatically checks for pending pull requests in the Julia General registry. This helps you see if there's a newer version being registered.

**Local Registry Status:** The package also compares the latest version in the General registry with your local Pkg registry. If your local registry is behind, you'll see a helpful message prompting you to run `] registry update`.

Example output:
```
Example@0.5.5 registered 1 year ago (2024-09-26 21:29:11 UTC)

  Note: Your local registry has Example@0.5.2
  Run ] registry update to get the latest version

  Pending PR(s):
  PR #12345: New version: Example v0.5.6
    by @author, opened 2 days ago [AutoMerge]
```

**Note:** All timestamps are displayed in UTC to ensure consistency across different timezones.

### Programmatic API

You can also use the `when()` function directly in your Julia code:

```julia
using PkgVersionHistory
using Dates

# Get timestamp for latest version
timestamp = when("Example")
println(timestamp)  # DateTime object

# Get timestamp for specific version
timestamp = when("Example@1.2.3")

# Using PackageSpec
using Pkg
spec = Pkg.Types.PackageSpec(name="Example", version="1.2.3")
timestamp = when(spec)
```

The programmatic API returns a `DateTime` object (not formatted), which you can use for further processing.

## Backends

The package supports two backends for fetching version metadata, selectable via [Preferences.jl](https://github.com/JuliaPackaging/Preferences.jl):

### Git Backend (default)

The default backend clones the General registry as a bare git repository and queries commit history directly using `git log -S`. This provides **fresh data immediately** — no lag.

**How it works:**
1. Clones a bare copy of the registry to a [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) managed directory
2. Uses `git log -S` to find the commit that introduced each version entry
3. Automatically stays in sync with your local Pkg registry

**Storage location:**
```
~/.julia/scratchspaces/<package-uuid>/<registry-name>/
```

**Trade-offs:**
- ✅ Fresh data — no lag behind the registry
- ✅ Supports multiple registries
- ❌ ~400 MB disk space for the General registry (one-time)
- ❌ Requires Git

### API Backend

A lightweight alternative that fetches version metadata from the [GeneralMetadata.jl](https://github.com/JuliaRegistries/GeneralMetadata.jl) web API, a static JSON API hosted on GitHub Pages.

**How it works:**
1. Queries `https://juliaregistries.github.io/GeneralMetadata.jl/api/<package>/versions.json`
2. Parses registration timestamps and yanked status from the JSON response
3. Caches responses in-session for fast repeated queries

**Trade-offs:**
- ✅ No disk space needed
- ✅ No Git dependency
- ✅ Fast queries (small JSON downloads)
- ❌ Data updates once per day (~midnight UTC) — recently registered versions may take up to 24 hours to appear
- ❌ General registry only (no custom registries)

### Switching Backends

**In REPL mode:**
```julia-repl
when> backend api    # switch to API backend
when> backend git    # switch back to git backend
when> backend        # show current backend
```

**Programmatically:**
```julia
using PkgVersionHistory

set_backend!(:api)   # lightweight, no disk space
set_backend!(:git)   # fresh data (default)
get_backend()        # check current backend
```

The preference is saved persistently in `LocalPreferences.toml`, so it survives Julia restarts.

## Refreshing Data

**In REPL mode:**
```julia-repl
when> refresh                 # updates git registry or clears API cache
when> registry refresh        # force-update git registry cache
```

**Programmatically:**
```julia
# Git backend
update_registry!()

# API backend
update_cache!()
```

## Checking Pending PRs

When you query the latest version of a package (without specifying `@version`), the package automatically checks for pending pull requests using the GitHub CLI (`gh`):

```julia-repl
when> when MyPackage
MyPackage@1.2.3 registered 2 weeks ago (2024-10-14 10:30:00)

  Pending PR(s):
  PR #12345: New version: MyPackage v1.2.4
    by @author, opened 2 days ago [AutoMerge]
```

This shows any open PRs for the package, including their AutoMerge status. The GitHub CLI (`gh`) is provided automatically via the `gh_cli_jll` dependency.

## Registry Management (Git Backend)

When using the git backend, you can query packages from any registry in your Pkg depot:

**In REPL mode:**
```julia-repl
when> registry list           # See available registries
when> registry use MyRegistry # Switch to a different registry
when> registry show           # Show current registry
```

**Programmatically:**
```julia
using PkgVersionHistory

list_registries()
set_registry!("MyRegistry")
get_registry_url()
```

**Note:** Only registries already added to Pkg can be used. To add a new registry, use `]registry add <url>` in Pkg mode first.

## Requirements

- Julia 1.10 or higher
- **Git backend:** Git, ~400 MB disk space for the General registry (one-time, in scratch space)
- **API backend:** Internet access only
- GitHub CLI (`gh`) — provided automatically via `gh_cli_jll`, used for checking pending PRs

## Disk Space Management

Registry caches (git backend) are stored in scratch spaces managed by Scratch.jl. The General registry is about 400 MB.

To clean up scratch spaces across all packages:
```julia
using Pkg
Pkg.gc()  # Removes scratch spaces from uninstalled packages
```

To switch to the API backend and avoid disk usage entirely:
```julia
using PkgVersionHistory
set_backend!(:api)
```

## Related Projects

- [PackageAnalyzer.jl](https://github.com/JuliaEcosystem/PackageAnalyzer.jl) - Analyzes packages in the General registry for documentation, testing, and CI coverage. While PackageAnalyzer focuses on package content and quality metrics, PkgVersionHistory focuses on registration timestamps and version history.
- [RegistryInstances.jl](https://github.com/GunnarFarneback/RegistryInstances.jl) - Provides stable access to registry metadata including compatibility information and tree hashes.
- [JuliaRegistryAnalysis.jl](https://github.com/KristofferC/JuliaRegistryAnalysis.jl) - Analyzes package dependencies and creates dependency graphs for packages in the General registry.

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
