using Dates
using GitHub
using Pkg
using Printf
using RegistryCI
using Test
using TimeZones

const AutoMerge = RegistryCI.AutoMerge

@testset "RegistryCI.jl" begin
    AUTOMERGE_RUN_INTEGRATION_TESTS = get(ENV, "AUTOMERGE_RUN_INTEGRATION_TESTS", "")::String
    if AUTOMERGE_RUN_INTEGRATION_TESTS == "true"
        @testset "AutoMerge.jl integration tests" begin
            @info("Running the AutoMerge.jl integration tests")
            include("automerge-integration.jl")
        end
    else
        @testset "RegistryCI.jl unit tests" begin
            @info("Running the RegistryCI.jl unit tests")
            include("registryci.jl")
        end
        @testset "AutoMerge.jl unit tests" begin
            @info("Running the AutoMerge.jl unit tests")
            include("automerge-unit.jl")
        end
    end
end
