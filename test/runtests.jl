using Dates
# using GitCommand
using GitHub
using JSON
using Pkg
using Printf
using RegistryCI
using Test
using TimeZones
using ReferenceTests

const AutoMerge = RegistryCI.AutoMerge

# Starting with Julia 1.7, when you use the Pkg server registry, the registry tarball does
# not get unpacked, and thus the registry files are not available. Of course, RegistryCI
# requires that the registry files are available. So for the RegistryCI test suite, we will
# disable the Pkg server.
ENV["JULIA_PKG_SERVER"] = ""

@static if v"1.6-" <= Base.VERSION < v"1.11-"
    # BrokenRecord fails to precompile on Julia 1.11
    let
        # The use of `VersionNumber`s here (e.g. `version = v"foo.bar.baz"`) tells Pkg to install the exact version.
        brokenrecord = Pkg.PackageSpec(name = "BrokenRecord", uuid = "bdd55f5b-6e67-4da1-a080-6086e55655a0", version = v"0.1.9")
        jld2 = Pkg.PackageSpec(name = "JLD2", uuid = "033835bb-8acc-5ee8-8aae-3f567f8a3819", version = v"0.4.33")
        pkgs = [brokenrecord, jld2]
        Pkg.add(pkgs)
    end
    import BrokenRecord
end

@testset "RegistryCI.jl" begin
    # This functionality is now in RegistryTesting.jl, but we check the public `RegistryCI.test` still works (removing would be breaking).
    @testset "Public interface" begin
        @testset "RegistryCI.test" begin
            path = joinpath(DEPOT_PATH[1], "registries", "General")
            RegistryCI.test(path)
        end
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
