using Test
using AutoMerge

@testset "General name check" begin
    name_check_main = @static if VERSION >= v"1.12"
        AutoMerge.GeneralNameCheck.main
    else
        AutoMerge.GeneralNameCheck._main
    end

    # Note: main returns exit codes.
    redirect_stderr(devnull) do
        @test name_check_main(String[]) == 1
        @test name_check_main(["a", "b"]) == 1
    end
    mktemp() do path, io
        redirect_stdout(io) do
            @test name_check_main(["csv"]) == 0
        end
        close(io)
        output = read(path, String)
        @test contains(output, "Name is a valid identifier.")
        @test contains(output, "Name only contains ascii characters.")
        @test contains(output, "Name matches registered package up to capitalization:")
        @test contains(output, "Name is shorter than five characters:")
        @test contains(output, "Name passes julia redundancy check.")
        @test contains(output, "Name does not have normal capitalization:")
        @test contains(output, "Name similarities found:")
    end
end
