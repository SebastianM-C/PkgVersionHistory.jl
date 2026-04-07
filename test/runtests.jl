using PkgVersionHistory
using Test
using Dates
using Dates: Day, Hour

@testset "PkgVersionHistory.jl" begin
    # ========================================================================
    # Code quality tests using Aqua.jl and JET.jl
    # ========================================================================
    println("\n=== Running code quality tests (Aqua & JET) ===")
    include("test_aqua_jet.jl")

    # ========================================================================
    # Unit tests that don't require network access
    # ========================================================================
    println("\n=== Running unit tests (no network required) ===")
    include("test_unit_mocked.jl")
    include("test_error_handling.jl")

    # ========================================================================
    # Integration tests that require network access
    # ========================================================================
    println("\n=== Running integration tests (requires network) ===")

    @testset "Registry operations" begin
        # Test getting registry path
        registry_path = PkgVersionHistory.get_registry_path()
        @test isdir(registry_path)

        # Test finding a known package
        pkg_path = PkgVersionHistory.get_package_path(registry_path, "Example")
        @test !isnothing(pkg_path)

        # Test finding a non-existent package
        pkg_path = PkgVersionHistory.get_package_path(registry_path, "NonExistentPackageXYZ123")
        @test isnothing(pkg_path)
    end

    @testset "Version queries" begin
        # Test getting latest version of a known package
        version = PkgVersionHistory.get_latest_version("Example")
        @test !isempty(version)
        @test occursin(r"^\d+\.\d+\.\d+", version)

        # Test when function with package name only
        timestamp = when("Example")
        @test timestamp isa DateTime
        @test timestamp < now()  # Should be in the past

        # Test when function with specific version (Example 0.5.0 is a known version)
        timestamp = when("Example@0.5.0")
        @test timestamp isa DateTime
        @test timestamp < now()
    end

    @testset "Time formatting" begin
        # Test relative time formatting
        now_time = now()

        # 2 days ago
        dt = now_time - Day(2)
        str = PkgVersionHistory.format_relative_time(dt)
        @test occursin("day", str)
        @test occursin("ago", str)

        # 3 hours ago
        dt = now_time - Hour(3)
        str = PkgVersionHistory.format_relative_time(dt)
        @test occursin("hour", str)
        @test occursin("ago", str)

        # 1 year ago
        dt = now_time - Day(365)
        str = PkgVersionHistory.format_relative_time(dt)
        @test occursin("year", str) || occursin("month", str)
        @test occursin("ago", str)
    end

    @testset "Output formatting" begin
        timestamp = DateTime(2023, 1, 15, 10, 30, 0)
        output = PkgVersionHistory.format_when_output("Example", "1.0.0", timestamp)
        @test occursin("Example@1.0.0", output)
        @test occursin("registered", output)
        @test occursin("ago", output)
    end
end
