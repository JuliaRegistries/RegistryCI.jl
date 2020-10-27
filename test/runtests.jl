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

@testset "RegistryCI.jl" begin
    @testset "RegistryCI.jl unit tests" begin
        @info("Running the RegistryCI.jl unit tests")
        include("registryci_registry_testing.jl")
    end

    @testset "TagBot.jl unit tests" begin
        @info("Running the TagBot.jl unit tests")
        include("tagbot-unit.yml")
    end

    @testset "AutoMerge.jl unit tests" begin
        @info("Running the AutoMerge.jl unit tests")
        include("automerge-unit.jl")
    end

    AUTOMERGE_RUN_INTEGRATION_TESTS = get(ENV, "AUTOMERGE_RUN_INTEGRATION_TESTS", "")::String
    if AUTOMERGE_RUN_INTEGRATION_TESTS == "true"
        @testset "AutoMerge.jl integration tests" begin
            @info("Running the AutoMerge.jl integration tests")
            include("automerge-integration.jl")
        end
    end
end
