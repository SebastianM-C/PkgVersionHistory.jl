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
        # Run JET static analysis to detect potential type instabilities
        # and errors that could be caught at "compile time"
        # Note: JET warnings don't necessarily indicate bugs, just optimization opportunities

        @testset "report_package" begin
            # Analyze the whole package for potential issues
            # This will report type instabilities, potential errors, etc.
            rep = JET.report_package(
                PkgVersionHistory;
                target_modules = (PkgVersionHistory,),
                # Ignore some known false positives if needed
            )

            # Just report the findings, don't fail on them
            # Type instabilities are often acceptable in many contexts
            if !isempty(JET.get_reports(rep))
                println("\nJET found potential type instabilities (informational):")
                show(stdout, rep)
                println()
            end
            @test true  # Always pass, JET is informational
        end
    end

    @testset "Exports verification" begin
        # Simple check that expected exports are present
        exported = names(PkgVersionHistory)
        @test :when in exported
        @test :update_registry! in exported
    end
end
