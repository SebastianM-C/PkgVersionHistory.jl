# Code quality tests using Aqua.jl and JET.jl

using PkgVersionHistory
using Test
using Aqua
using JET

@testset "Code Quality - Aqua & JET" begin

    @testset "Aqua.jl quality assurance" begin
        # Run comprehensive Aqua tests
        Aqua.test_all(
            PkgVersionHistory;
            # Ambiguities can be noisy due to Base/stdlib, so we may want to skip or filter
            ambiguities = true,
            # Check for unbound type parameters
            unbound_args = true,
            # Check for undefined exports
            undefined_exports = true,
            # Check project structure
            project_extras = true,
            # Check for stale dependencies
            stale_deps = true,
            # Check for deps compatibility
            deps_compat = true,
        )
    end

    @testset "Method ambiguities (filtered)" begin
        # Test ambiguities separately with filtering if needed
        # This allows us to exclude known/acceptable ambiguities from stdlib
        Aqua.test_ambiguities(PkgVersionHistory)
    end

    @testset "JET.jl static analysis" begin
        JET.test_package(PkgVersionHistory; target_modules = (PkgVersionHistory,))
    end

end
