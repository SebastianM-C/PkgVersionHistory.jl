# Regression tests for the `when>` REPL mode.
#
# These exist because ReplMaker.jl's `initrepl` silently stopped working on Julia 1.13
# (it called `LineEdit.setup_search_keymap`, removed that release) and nothing caught it:
# `__init__` swallows the failure into a `@warn`, and no test ever built the mode.
#
# The mode can be constructed headlessly against a dummy terminal, so every piece of
# LineEdit plumbing `init_repl_mode` touches is exercised on whatever Julia runs CI.

using REPL
using REPL: LineEdit

"""
    dummy_repl() -> REPL.LineEditREPL

A `LineEditREPL` wired to an in-memory terminal, with the standard interface set up.
Nothing is read or drawn; it only exists so `init_repl_mode` has real modes,
keymaps and a history provider to attach to.
"""
function dummy_repl()
    term = REPL.Terminals.TTYTerminal("dumb", IOBuffer(), IOBuffer(), IOBuffer())
    repl = REPL.LineEditREPL(term, false)
    repl.interface = REPL.setup_interface(repl)
    return repl
end

@testset "REPL mode" begin
    repl = dummy_repl()
    julia_mode = repl.interface.modes[1]

    # The regression itself: this threw `UndefVarError: setup_search_keymap` on 1.13.
    when_mode = PkgVersionHistory.init_repl_mode(repl)
    @test when_mode isa LineEdit.Prompt
    @test when_mode.prompt == "when> "

    @testset "keymap plumbing" begin
        # Assert the keys are bound rather than naming the machinery behind them: ^R came
        # from `setup_search_keymap` up to 1.12 and from `history_keymap` on 1.13+, and
        # pinning the binding covers both without tracking which era this Julia is in.
        @test haskey(when_mode.keymap_dict, '\x12')   # ^R reaches history search
        @test haskey(when_mode.keymap_dict, '\b')     # backspace gets back to julia>
        @test haskey(julia_mode.keymap_dict, PkgVersionHistory.START_KEY)

        # `when>` lines must replay into `when>`, not `julia>`.
        @test when_mode.hist === julia_mode.hist
        @test julia_mode.hist.mode_mapping[PkgVersionHistory.MODE_NAME] === when_mode

        @test when_mode.sticky
    end

    @testset "command parsing" begin
        # `parse_when_command` is pure: input string in, expression out. No REPL needed.
        @test PkgVersionHistory.parse_when_command("") === nothing
        @test PkgVersionHistory.parse_when_command("help") == :(PkgVersionHistory.show_repl_help())
        @test PkgVersionHistory.parse_when_command("when Example") ==
            :(PkgVersionHistory.execute_when_command("Example"))
        @test PkgVersionHistory.parse_when_command("refresh") ==
            :(PkgVersionHistory.execute_refresh())
        # Compared piecewise rather than against a whole expression: Julia 1.13 tightened
        # `==` on `Expr` so interpolated non-AST values must be `===`, and two distinct
        # empty `String[]` vectors are not. Interpolated strings are fine either way.
        registry_ex = PkgVersionHistory.parse_when_command("registry list")
        @test registry_ex.head === :call
        @test registry_ex.args[1] == :(PkgVersionHistory.execute_registry_command)
        @test registry_ex.args[2] == "list"
        @test registry_ex.args[3] == String[]
    end
end
