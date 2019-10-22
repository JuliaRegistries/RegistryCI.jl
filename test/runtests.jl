using GitHub
using Pkg
using RegistryCI
using Test

const AutoMerge = RegistryCI.AutoMerge

@testset "RegistryCI.jl" begin
    AUTOMERGE_RUN_INTEGRATION_TESTS = get(ENV, "AUTOMERGE_RUN_INTEGRATION_TESTS", "")::String
    if AUTOMERGE_RUN_INTEGRATION_TESTS == "true"
        @testset "AutoMerge.jl integration tests" begin
            include("automerge-integration.jl")
        end
    else
        @testset "RegistryCI.jl unit tests" begin
            include("registryci.jl")
        end
        @testset "AutoMerge.jl unit tests" begin
            include("automerge-unit.jl")
        end
    end
end
