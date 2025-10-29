# PkgVersionHistory.jl

[![CI](https://github.com/SebastianM-C/PkgVersionHistory.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/SebastianM-C/PkgVersionHistory.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/SebastianM-C/PkgVersionHistory.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/SebastianM-C/PkgVersionHistory.jl)

A Julia package to check when package versions were registered in the General registry.

> **⚠️ Experimental Package**: This package is vibe-coded and considered experimental. APIs may change, and there might be rough edges. Use with appropriate caution in production environments.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/SebastianM-C/PkgVersionHistory.jl")
```

## Features

- **Check registration timestamps**: Find out when a specific package version was registered
- **REPL integration**: Use the convenient `when` command in a custom REPL mode (`}`)
- **Multiple packages**: Query multiple packages at once
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

# Refresh the registry cache
when> refresh

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
- Partial version resolution skips yanked versions
- Exact yanked versions can still be queried
- Yanked status is indicated with `[YANKED]` in the output

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

## How It Works

The package works by:

1. Cloning a bare copy of the [General registry](https://github.com/JuliaRegistries/General) to a scratch space
2. Using git to query the commit history for when specific package versions were added
3. Parsing the commit timestamps to provide registration times

The registry is cloned only once and stored in a [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) managed directory:
```
~/.julia/scratchspaces/<package-uuid>/General/
```

**Benefits of using Scratch.jl:**
- Automatic cleanup when the package is removed
- Standardized cache location management
- Integration with Julia's package system
- Can be garbage collected with `Pkg.gc()`

### Updating the Registry

The package automatically checks if your cached registry is older than Pkg's registry and updates it if needed. This happens:
- When you use the `when` command in REPL mode
- When you call the programmatic API

You can also manually update the registry:

**In REPL mode:**
```julia-repl
when> refresh
```

**Programmatically:**
```julia
using PkgVersionHistory
PkgVersionHistory.update_registry!()
```

The registry is compared with Pkg's registry (in `~/.julia/registries/General`) to ensure you have the latest data that Pkg knows about.

## Checking Pending PRs

When you query the latest version of a package (without specifying `@version`), the package automatically checks for pending pull requests using the GitHub CLI (`gh`):

```julia-repl
when> when MyPackage
MyPackage@1.2.3 registered 2 weeks ago (2024-10-14 10:30:00)

  Pending PR(s):
  PR #12345: New version: MyPackage v1.2.4
    by @author, opened 2 days ago [AutoMerge]
```

This shows any open PRs for the package, including their AutoMerge status.

**Requirements for pending PR checks:**
- GitHub CLI (`gh`) must be installed: https://cli.github.com/
- Alternatively, the `gh_jll` package can provide it
- If `gh` is not available, pending PR checks are silently skipped

## Requirements

- Julia 1.10 or higher
- Git (for cloning and querying the registry)
- ~400 MB disk space for the General registry (one-time, in scratch space)
- GitHub CLI (`gh`) - optional, for checking pending PRs

## Disk Space Management

The General registry is about 400 MB and is stored in a scratch space managed by Scratch.jl.

To clean up scratch spaces across all packages:
```julia
using Pkg
Pkg.gc()  # Removes scratch spaces from uninstalled packages
```

To manually remove PkgVersionHistory's registry cache:
```julia
using PkgVersionHistory, Scratch
scratch_dir = @get_scratch!("General")
rm(scratch_dir; recursive=true)
```

## Related Projects

- [PackageAnalyzer.jl](https://github.com/JuliaEcosystem/PackageAnalyzer.jl) - Analyzes packages in the General registry for documentation, testing, and CI coverage. While PackageAnalyzer focuses on package content and quality metrics, PkgVersionHistory focuses on registration timestamps and version history.
- [RegistryInstances.jl](https://github.com/GunnarFarneback/RegistryInstances.jl) - Provides stable access to registry metadata including compatibility information and tree hashes.
- [JuliaRegistryAnalysis.jl](https://github.com/KristofferC/JuliaRegistryAnalysis.jl) - Analyzes package dependencies and creates dependency graphs for packages in the General registry.

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
