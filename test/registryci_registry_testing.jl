using Dates
# using GitCommand
using GitHub
using JSON
using Pkg
using Printf
using RegistryCI
using Test
using TimeZones

@testset "Public interface" begin
    @testset "RegistryCI.test" begin
        path = joinpath(DEPOT_PATH[1], "registries", "General")
        RegistryCI.test(path)
    end
end

@testset "Internal functions (private)" begin
    @testset "RegistryCI.load_registry_dep_uuids" begin
        all_registry_deps_names = [
            ["General"],
            ["https://github.com/JuliaRegistries/General"],
            ["https://github.com/JuliaRegistries/General.git"],
        ]
        for registry_deps_names in all_registry_deps_names
            extrauuids = RegistryCI.load_registry_dep_uuids(registry_deps_names)
            @test extrauuids isa Set{Base.UUID}
            @test length(extrauuids) > 1_000
        end
    end
end
