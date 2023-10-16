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

@static if Base.VERSION < v"1.11"
    # BrokenRecord fails to precompile on Julia 1.11
    Pkg.add(;
        name = "BrokenRecord",
        uuid = "bdd55f5b-6e67-4da1-a080-6086e55655a0",
        version = "0.1.3",
    )
    import BrokenRecord
end

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
end
