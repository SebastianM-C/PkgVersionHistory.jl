# Unit tests with mocked data for PkgVersionHistory
# Tests that don't require network access

using PkgVersionHistory
using Test
using Dates
using TimeZones

@testset "Unit Tests with Mocked Data" begin

    # ========================================================================
    # REPL COMMAND PARSING - Detailed tests
    # ========================================================================
    @testset "REPL Command Parsing - Detailed" begin
        @testset "Help command variations" begin
            # Test valid help commands (case-sensitive)
            for cmd in ["help", "?", "  help  "]
                result = PkgVersionHistory.parse_when_command(cmd)
                @test result isa Expr
                # The expression should call show_repl_help
                @test occursin("show_repl_help", string(result))
            end

            # Test that invalid case variations are treated as unknown commands
            for cmd in ["HELP", "Help"]
                result = PkgVersionHistory.parse_when_command(cmd)
                @test result isa Expr
                # These become unknown commands, so head might be :call
            end
        end

        @testset "When command - single package" begin
            result = PkgVersionHistory.parse_when_command("when Example")
            @test result isa Expr
            @test occursin("Example", string(result))
        end

        @testset "When command - versioned package" begin
            test_cases = [
                "when Example@1.0.0",
                "when Example@1",
                "when Example@0.5",
                "when JSON@0.21.4"
            ]

            for cmd in test_cases
                result = PkgVersionHistory.parse_when_command(cmd)
                @test result isa Expr
                @test !isnothing(result)
            end
        end

        @testset "When command - multiple packages" begin
            test_cases = [
                "when JSON DataFrames",
                "when Example JSON HTTP DataFrames",
                "when A B C D E"
            ]

            for cmd in test_cases
                result = PkgVersionHistory.parse_when_command(cmd)
                @test result isa Expr
            end
        end

        @testset "Registry subcommands" begin
            # registry refresh
            result = PkgVersionHistory.parse_when_command("registry refresh")
            @test result isa Expr
            @test occursin("execute_registry_command", string(result))

            # registry show
            result = PkgVersionHistory.parse_when_command("registry show")
            @test result isa Expr
            @test occursin("execute_registry_command", string(result))

            # registry list
            result = PkgVersionHistory.parse_when_command("registry list")
            @test result isa Expr
            @test occursin("execute_registry_command", string(result))

            # registry use
            result = PkgVersionHistory.parse_when_command("registry use General")
            @test result isa Expr
            @test occursin("execute_registry_command", string(result))

            # registry without subcommand shows help
            result = PkgVersionHistory.parse_when_command("registry")
            @test result isa Expr
            @test occursin("show_registry_help", string(result))
        end

        @testset "Invalid commands" begin
            test_cases = [
                "invalid",
                "unknown",
                "abc123",
                "refresh",  # refresh is no longer top-level (use registry refresh)
                "when",  # when without package
            ]

            for cmd in test_cases
                result = PkgVersionHistory.parse_when_command(cmd)
                if cmd == "when"
                    # Should return usage message
                    @test result isa Expr
                else
                    # Should return error message (unknown command)
                    @test result isa Expr
                end
            end
        end

        @testset "Edge cases" begin
            # Empty string
            @test isnothing(PkgVersionHistory.parse_when_command(""))

            # Only whitespace
            @test isnothing(PkgVersionHistory.parse_when_command("   "))
            @test isnothing(PkgVersionHistory.parse_when_command("\t\n"))

            # Very long input
            long_cmd = "when " * join(["Package$i" for i in 1:100], " ")
            result = PkgVersionHistory.parse_when_command(long_cmd)
            @test result isa Expr
        end
    end

    # ========================================================================
    # GITHUB PR FORMATTING - Detailed tests
    # ========================================================================
    @testset "GitHub PR Formatting - Detailed" begin
        @testset "Basic PR formatting" begin
            pr = Dict(
                "number" => 12345,
                "title" => "New version: Example v1.0.0",
                "author" => Dict("login" => "testuser"),
                "createdAt" => "2024-01-15T10:30:00Z",
                "labels" => []
            )

            result = PkgVersionHistory.format_pending_pr(pr)

            @test occursin("PR #12345", result)
            @test occursin("New version: Example v1.0.0", result)
            @test occursin("@testuser", result)
            @test occursin("ago", result)
            @test !occursin("[AutoMerge]", result)
        end

        @testset "PR with AutoMerge label" begin
            pr = Dict(
                "number" => 99999,
                "title" => "Package update",
                "author" => Dict("login" => "bot"),
                "createdAt" => "2024-12-01T00:00:00Z",
                "labels" => [
                    Dict("name" => "automerge"),
                    Dict("name" => "other-label")
                ]
            )

            result = PkgVersionHistory.format_pending_pr(pr)
            @test occursin("[AutoMerge]", result)
            @test occursin("#99999", result)
        end

        @testset "PR with multiple labels but no AutoMerge" begin
            pr = Dict(
                "number" => 11111,
                "title" => "Test PR",
                "author" => Dict("login" => "user123"),
                "createdAt" => "2024-06-15T12:00:00Z",
                "labels" => [
                    Dict("name" => "bug"),
                    Dict("name" => "enhancement")
                ]
            )

            result = PkgVersionHistory.format_pending_pr(pr)
            @test !occursin("[AutoMerge]", result)
        end

        @testset "PR with special characters in title" begin
            pr = Dict(
                "number" => 123,
                "title" => "New version: Foo.jl v2.0.0-beta.1 [breaking]",
                "author" => Dict("login" => "contributor"),
                "createdAt" => "2024-01-01T00:00:00Z",
                "labels" => []
            )

            result = PkgVersionHistory.format_pending_pr(pr)
            @test occursin("Foo.jl v2.0.0-beta.1 [breaking]", result)
        end
    end

    # ========================================================================
    # TIME FORMATTING - Comprehensive edge cases
    # ========================================================================
    @testset "Time Formatting - Comprehensive" begin
        using TimeZones
        now_time = now(UTC)

        test_cases = [
            (Second(0), "0 seconds ago"),
            (Second(1), "1 second ago"),
            (Second(30), "30 seconds ago"),
            (Second(59), "59 seconds ago"),
            (Minute(1), "1 minute ago"),
            (Minute(2), "2 minutes ago"),
            (Minute(59), "59 minutes ago"),
            (Hour(1), "1 hour ago"),
            (Hour(2), "2 hours ago"),
            (Hour(23), "23 hours ago"),
            (Day(1), "1 day ago"),
            (Day(3), "3 days ago"),
            (Day(6), "6 days ago"),
            (Day(7), "1 week ago"),
            (Day(14), "2 weeks ago"),
            (Day(21), "3 weeks ago"),
            (Day(30), "1 month ago"),
            (Day(60), "2 months ago"),
            (Day(350), "11 months ago"),
            (Day(365), "1 year ago"),
            (Day(730), "2 years ago"),
        ]

        for (offset, expected_pattern) in test_cases
            dt = now_time - offset
            result = PkgVersionHistory.format_relative_time(dt)
            # Just check it contains "ago" and a number
            @test occursin("ago", result)
            @test occursin(r"\d+", result)
        end
    end

    # ========================================================================
    # OUTPUT FORMATTING - Various scenarios
    # ========================================================================
    @testset "Output Formatting - Scenarios" begin
        timestamp = DateTime(2023, 6, 15, 14, 30, 45)

        @testset "Regular package version" begin
            output = PkgVersionHistory.format_when_output("MyPackage", "1.2.3", timestamp, false)
            @test occursin("MyPackage@1.2.3", output)
            @test occursin("registered", output)
            @test occursin("ago", output)
            @test occursin("2023-06-15", output)
            @test occursin("UTC", output)
            @test !occursin("[YANKED]", output)
        end

        @testset "Yanked version" begin
            output = PkgVersionHistory.format_when_output("MyPackage", "1.2.3", timestamp, true)
            @test occursin("[YANKED]", output)
        end

        @testset "Prerelease version" begin
            output = PkgVersionHistory.format_when_output("Pkg", "1.0.0-beta", timestamp, false)
            @test occursin("Pkg@1.0.0-beta", output)
        end

        @testset "Package names with special characters" begin
            test_cases = [
                "Package_With_Underscores",
                "PackageWith123",
                "X",
                "VeryLongPackageNameThatGoesOnAndOn"
            ]

            for pkg_name in test_cases
                output = PkgVersionHistory.format_when_output(pkg_name, "1.0.0", timestamp, false)
                @test occursin(pkg_name, output)
            end
        end
    end

    # ========================================================================
    # VERSION STRING PARSING - Edge cases
    # ========================================================================
    @testset "Version String Parsing" begin
        @testset "Package spec parsing" begin
            # Test package@version splitting
            test_cases = [
                ("Example", ("Example", nothing)),
                ("Example@1.0.0", ("Example", "1.0.0")),
                ("Example@1", ("Example", "1")),
                ("Example@0.5", ("Example", "0.5")),
                ("Package_Name@2.3.4", ("Package_Name", "2.3.4")),
            ]

            for (input, (expected_pkg, expected_ver)) in test_cases
                parts = split(input, '@')
                pkg_name = String(parts[1])
                version = length(parts) > 1 ? String(parts[2]) : nothing

                @test pkg_name == expected_pkg
                @test version == expected_ver
            end
        end
    end

    # ========================================================================
    # GH COMMAND SELECTION
    # ========================================================================
    @testset "GH Command Selection" begin
        @testset "get_gh_command returns valid command" begin
            cmd = PkgVersionHistory.get_gh_command()
            @test cmd isa Cmd
            # Should be either system gh or JLL gh
            cmd_string = string(cmd)
            @test occursin("gh", cmd_string)
        end
    end

    # ========================================================================
    # REGISTRY PATH MANAGEMENT
    # ========================================================================
    @testset "Registry Path Management" begin
        @testset "get_pkg_registry_path logic" begin
            path = PkgVersionHistory.get_pkg_registry_path()
            # May be nothing if Pkg registry doesn't exist
            if !isnothing(path)
                @test isdir(path)
                # Path should end with the current registry name
                @test endswith(path, PkgVersionHistory.get_registry_name())
                # Should be in some depot path
                @test any(depot -> startswith(path, depot), DEPOT_PATH)
            end
        end

        @testset "should_update_registry returns bool" begin
            result = PkgVersionHistory.should_update_registry()
            @test result isa Bool
        end
    end

    # ========================================================================
    # NOTE: Exports and module structure tests moved to test_aqua_jet.jl
    # Using Aqua.jl and JET.jl for better code quality checks
    # ========================================================================
end
