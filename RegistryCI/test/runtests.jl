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

function ensure_unpacked_general_registry()
    registry_dir = joinpath(DEPOT_PATH[1], "registries", "General")
    registry_toml = joinpath(registry_dir, "Registry.toml")
    isfile(registry_toml) && return

    packed_registry = joinpath(DEPOT_PATH[1], "registries", "General.toml")
    if isfile(packed_registry)
        try
            Pkg.Registry.rm("General")
        catch err
            @info "Ignoring failure while removing packed General registry during test setup" err
        end
    end

    Pkg.Registry.add("General")
    isfile(registry_toml) || error("RegistryCI tests require an unpacked General registry at $registry_dir.")
end

ensure_unpacked_general_registry()

@testset "RegistryCI.jl" begin
    @info("Running the RegistryCI.jl unit tests")
    include("registryci_registry_testing.jl")

    @testset "MovedFunctionality" begin
        @test_throws RegistryCI.MovedFunctionalityException RegistryCI.TagBot.main()
        @test_throws RegistryCI.MovedFunctionalityException RegistryCI.AutoMerge.run()
        @test_throws RegistryCI.MovedFunctionalityException sprint(Base.showerror, RegistryCI.AutoMerge)
        @test_throws RegistryCI.MovedFunctionalityException sprint(Base.showerror, RegistryCI.TagBot)
    end
end
