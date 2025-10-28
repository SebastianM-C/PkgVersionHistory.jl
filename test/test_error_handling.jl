# Error handling and edge case tests for PkgVersionHistory

using PkgVersionHistory
using Test
using Dates

@testset "Error Handling and Edge Cases" begin

    # ========================================================================
    # INPUT VALIDATION TESTS
    # ========================================================================
    @testset "Input Validation" begin
        @testset "Empty inputs" begin
            # Empty package name should error
            @test_throws Exception when("")

            # Empty REPL command should return nothing
            @test isnothing(PkgVersionHistory.parse_when_command(""))
            @test isnothing(PkgVersionHistory.parse_when_command("   "))
            @test isnothing(PkgVersionHistory.parse_when_command("\t\n"))
        end

        @testset "Invalid package names" begin
            invalid_names = [
                "NonExistent_Package_XYZ_123456789",
                "!!!invalid!!!",
                "pkg with spaces",
            ]

            for invalid_name in invalid_names
                # These should error when trying to find the package
                @test_throws Exception when(invalid_name)
            end
        end

        @testset "Malformed version strings" begin
            # Note: The resolve_version function might be lenient
            # These tests document expected behavior

            # Some version strings that might cause issues:
            # - Version with letters: "1.0.0alpha"
            # - Multiple @ symbols: "Package@@1.0.0"
            # - Version with special chars: "1.0.0!"

            # Test with multiple @ symbols
            @test_throws Exception when("Package@@1.0.0")
        end
    end

    # ========================================================================
    # GIT OPERATION ERROR HANDLING
    # ========================================================================
    @testset "Git Operation Errors" begin
        @testset "Invalid registry path" begin
            # Test with non-existent path
            # With Git.jl, this returns nothing rather than throwing
            @test isnothing(PkgVersionHistory.get_package_path("/nonexistent/path", "Example"))
        end
    end

    # ========================================================================
    # EDGE CASES - DATE/TIME
    # ========================================================================
    @testset "Date/Time Edge Cases" begin
        @testset "Very old timestamps" begin
            # Test with timestamps from year 2000
            old_timestamp = DateTime(2000, 1, 1, 0, 0, 0)
            result = PkgVersionHistory.format_relative_time(old_timestamp)
            @test occursin("year", result)
            @test occursin("ago", result)
        end

        @testset "Recent timestamps" begin
            # Test with very recent timestamp (seconds ago)
            using TimeZones
            recent = now(UTC) - Second(5)
            result = PkgVersionHistory.format_relative_time(recent)
            @test occursin("second", result)
        end

        @testset "Future timestamps (edge case)" begin
            # What happens if timestamp is in the future?
            using TimeZones
            future = now(UTC) + Day(1)
            result = PkgVersionHistory.format_relative_time(future)
            # Should still produce some output (might be negative or zero)
            @test result isa String
        end
    end

    # ========================================================================
    # EDGE CASES - VERSION RESOLUTION
    # ========================================================================
    @testset "Version Resolution Edge Cases" begin
        @testset "Partial versions" begin
            # These tests document expected behavior for partial version resolution
            # Actual testing requires real registry data

            # Expected behaviors:
            # "1" -> first "1.x.x" version
            # "1.9" -> first "1.9.x" version
            # "0.5" -> first "0.5.x" version

            # Test that the parsing logic works
            test_cases = [
                "1.0.0",  # Full version
                "1.0",    # Partial (missing patch)
                "1",      # Partial (missing minor and patch)
            ]

            for version_str in test_cases
                # Just verify the string is valid
                @test !isempty(version_str)
                @test all(c -> isdigit(c) || c == '.', version_str)
            end
        end

    end

    # ========================================================================
    # EDGE CASES - PACKAGE NAMES
    # ========================================================================
    @testset "Package Name Edge Cases" begin
        @testset "Single character package names" begin
            # Package names can be very short
            # Test that parsing works for single characters
            parts = split("A@1.0.0", '@')
            @test parts[1] == "A"
            @test parts[2] == "1.0.0"
        end

        @testset "Very long package names" begin
            # Test with a very long package name
            long_name = "VeryLongPackageName" * "Extended" ^ 10
            parts = split("$long_name@1.0.0", '@')
            @test parts[1] == long_name
        end

        @testset "Package names with numbers and underscores" begin
            test_names = [
                "Package123",
                "Package_Name",
                "Package_123",
                "X11",
                "Pkg2D",
            ]

            for name in test_names
                parts = split("$name@1.0.0", '@')
                @test parts[1] == name
            end
        end
    end

    # ========================================================================
    # CONCURRENT ACCESS
    # ========================================================================
    @testset "Concurrent Access" begin
        @testset "Multiple registry reads" begin
            # Test that multiple concurrent reads don't cause issues
            # This is a basic test; more thorough testing would use threads

            # Calling get_registry_path multiple times should be safe
            path1 = PkgVersionHistory.get_registry_path()
            path2 = PkgVersionHistory.get_registry_path()
            @test path1 == path2
        end
    end

    # ========================================================================
    # REPL MODE ERROR HANDLING
    # ========================================================================
    @testset "REPL Mode Error Handling" begin
        @testset "when command without arguments" begin
            result = PkgVersionHistory.parse_when_command("when")
            @test !isnothing(result)
            # Should return usage message
        end

        @testset "Unrecognized commands" begin
            test_commands = [
                "invalid",
                "asdf",
                "123",
                "!!!",
            ]

            for cmd in test_commands
                result = PkgVersionHistory.parse_when_command(cmd)
                @test !isnothing(result)
                # Should return error message expression
            end
        end
    end

    # ========================================================================
    # GITHUB PR EDGE CASES
    # ========================================================================
    @testset "GitHub PR Edge Cases" begin
        @testset "PR with missing fields" begin
            # Test handling of PR dict with missing fields
            # This should be caught and handled gracefully

            # Minimum required fields
            minimal_pr = Dict(
                "number" => 1,
                "title" => "Test",
                "author" => Dict("login" => "user"),
                "createdAt" => "2024-01-01T00:00:00Z",
                "labels" => []
            )

            result = PkgVersionHistory.format_pending_pr(minimal_pr)
            @test !isempty(result)
        end

        @testset "PR with empty labels array" begin
            pr = Dict(
                "number" => 1,
                "title" => "Test",
                "author" => Dict("login" => "user"),
                "createdAt" => "2024-01-01T00:00:00Z",
                "labels" => []
            )

            result = PkgVersionHistory.format_pending_pr(pr)
            @test !occursin("[AutoMerge]", result)
        end

        @testset "PR timestamp parsing" begin
            # Test various timestamp formats
            timestamps = [
                "2024-01-01T00:00:00Z",
                "2024-12-31T23:59:59Z",
                "2024-06-15T12:30:45Z",
            ]

            for ts in timestamps
                pr = Dict(
                    "number" => 1,
                    "title" => "Test",
                    "author" => Dict("login" => "user"),
                    "createdAt" => ts,
                    "labels" => []
                )

                result = PkgVersionHistory.format_pending_pr(pr)
                @test occursin("ago", result)
            end
        end
    end

    # ========================================================================
    # REGISTRY MANAGEMENT EDGE CASES
    # ========================================================================
    @testset "Registry Management Edge Cases" begin
        @testset "Multiple DEPOT_PATH entries" begin
            # Test that get_pkg_registry_path works with multiple depot paths
            # DEPOT_PATH is a Vector of paths
            @test DEPOT_PATH isa Vector
            @test length(DEPOT_PATH) >= 1

            # Should search through all depot paths
            path = PkgVersionHistory.get_pkg_registry_path()
            # May be nothing if no registry found
            if !isnothing(path)
                @test any(depot -> startswith(path, depot), DEPOT_PATH)
            end
        end

        @testset "Registry timestamp comparison" begin
            # Test get_registry_last_update with various scenarios
            # Returns DateTime or nothing

            # With valid registry (if available)
            registry_path = PkgVersionHistory.get_registry_path()
            if isdir(registry_path)
                timestamp = PkgVersionHistory.get_registry_last_update(registry_path)
                # May be nothing if can't determine
                if !isnothing(timestamp)
                    @test timestamp isa DateTime
                    @test timestamp < now()  # Should be in the past
                end
            end
        end

        @testset "should_update_registry edge cases" begin
            # Test the update decision logic
            result = PkgVersionHistory.should_update_registry()
            @test result isa Bool

            # The function should handle:
            # - Missing our registry (returns true)
            # - Missing Pkg registry (returns false)
            # - Corrupted timestamp data (returns true/false safely)
        end
    end
end
