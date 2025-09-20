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


# Starting with Julia 1.7, when you use the Pkg server registry, the registry tarball does
# not get unpacked, and thus the registry files are not available. Of course, RegistryCI
# requires that the registry files are available. So for the RegistryCI test suite, we will
# disable the Pkg server.
ENV["JULIA_PKG_SERVER"] = ""

@testset "RegistryCI.jl" begin
    @info("Running the RegistryCI.jl unit tests")
    include("registryci_registry_testing.jl")

    @testset "MovedFunctionality" begin
        @test_throws RegistryCI.MovedFunctionalityException RegistryCI.TagBot.main()
        @test_throws RegistryCI.MovedFunctionalityException RegistryCI.AutoMerge.run()
        @test_throws RegistryCI.MovedFunctionalityException sprint(show, RegistryCI.AutoMerge)
        @test_throws RegistryCI.MovedFunctionalityException sprint(show, RegistryCI.TagBot)
    end
end
