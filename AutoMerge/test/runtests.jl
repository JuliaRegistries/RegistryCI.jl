using Dates
using GitHub
using JSON
using Pkg
using Printf
using AutoMerge
using RegistryCI
using Test
using TimeZones
using ReferenceTests
using UUIDs

# NOTE: AutoMerge now supports both packed (tarball) and unpacked registries via RegistryInstances.jl.
# We enable the Pkg server to test packed registry support!
# ENV["JULIA_PKG_SERVER"] = ""  # Disabled - we want to test with packed registries

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

@testset "AutoMerge.jl" begin
    @testset "TagBot.jl unit tests" begin
        # if v"1.0" <= VERSION < VersionNumber(1, 5, typemax(UInt32))
        if false
            @info("Running the TagBot.jl unit tests", VERSION)
            include("tagbot-unit.jl")
        else
            @warn("Skipping the TagBot.jl unit tests", VERSION)
        end
    end

    @testset "Registry Helpers tests" begin
        @info("Running the Registry Helpers tests")
        include("registry_helpers_test.jl")
    end

    @testset "Compat Guidelines Comparison tests" begin
        @info("Running the Compat Guidelines Comparison tests")
        include("compat_tests.jl")
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
