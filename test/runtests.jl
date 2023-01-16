using Dates
# using GitCommand
using GitHub
using JSON
using Pkg
using Printf
using RegistryCI
using Test
using TimeZones

const AutoMerge = RegistryCI.AutoMerge

# Starting with Julia 1.7, when you use the Pkg server registry, the registry tarball does
# not get unpacked, and thus the registry files are not available. Of course, RegistryCI
# requires that the registry files are available. So for the RegistryCI test suite, we will
# disable the Pkg server.
ENV["JULIA_PKG_SERVER"] = ""

@testset "RegistryCI.jl" begin
    @testset "RegistryCI.jl unit tests" begin
        @info("Running the RegistryCI.jl unit tests")
        include("registryci_registry_testing.jl")
    end

    @testset "TagBot.jl unit tests" begin
        # if v"1.0" <= VERSION < VersionNumber(1, 5, typemax(UInt32))
        if false
            @info("Running the TagBot.jl unit tests", VERSION)
            include("tagbot-unit.jl")
        else
            @warn("Skipping the TagBot.jl unit tests", VERSION)
        end
    end

    @testset "AutoMerge.jl unit tests" begin
        @info("Running the AutoMerge.jl unit tests")
        include("automerge-unit.jl")
    end

    AUTOMERGE_RUN_INTEGRATION_TESTS =
        get(ENV, "AUTOMERGE_RUN_INTEGRATION_TESTS", "")::String
    if AUTOMERGE_RUN_INTEGRATION_TESTS == "true"
        @testset "AutoMerge.jl integration tests" begin
            @info("Running the AutoMerge.jl integration tests")
            include("automerge-integration.jl")
        end
    end

    @testset "env_threshold" begin
        e = RegistryCI.env_threshold
        ENV["zero"] = "0"
        ENV["zerodotzero"] = "0.0"
        ENV["zerodotzeropct"] = "0.0%"
        ENV["pct"] = "12%"
        ENV["fracpct"] = "20.5%"
        ENV["negcount"] = "-1"
        ENV["count"] = "123"
        # How can we test if a warning was logged?
        @test e("zero", 0.1) == 0
        @test e("zero", 0.1) isa Integer
        @test e("zerodotzero", 0.1) == 0.1         # default
        @test e("zerodotzeropct", 0.1) == 0.0
        @test e("zerodotzeropct", 0.1) isa Float32
        @test e("pct", 0) == 0.12f0
        @test e("fracpct", 0) == 0.205f0
        @test e("negcount", 10) == 10            # default
        @test e("count", 0) == 123
    end
end
