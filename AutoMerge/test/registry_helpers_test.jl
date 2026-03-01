using Test
using AutoMerge
using RegistryInstances
using UUIDs
using Pkg

@testset "Registry Helpers" begin
    # Get General registry for testing
    general_path = joinpath(first(DEPOT_PATH), "registries", "General")
    general = RegistryInstance(general_path)

    # JSON.jl for testing
    json_uuid = UUID("682c06a0-de6a-54ab-a142-c8b1cf79cde6")

    @testset "get_package_info" begin
        # Test by name
        info = AutoMerge.get_package_info(general, "JSON")
        @test info.repo == "https://github.com/JuliaIO/JSON.jl.git"
        @test info.subdir === nothing
        @test !isempty(info.version_info)

        # Test by UUID
        info_by_uuid = AutoMerge.get_package_info(general, json_uuid)
        @test info_by_uuid.repo == info.repo
    end

    @testset "get_compat_for_version" begin
        # Test getting compat for a specific version
        compat = AutoMerge.get_compat_for_version(general, "JSON", v"0.21.3")
        @test compat isa Dict{String, Pkg.Versions.VersionSpec}
        @test haskey(compat, "julia")
    end

    @testset "get_deps_for_version" begin
        # Test getting deps for a specific version
        deps = AutoMerge.get_deps_for_version(general, "JSON", v"0.21.3")
        @test deps isa Dict{String, UUID}
    end

    @testset "Integration: Core functionality works" begin
        # Test that helpers integrate well with rest of AutoMerge
        info = AutoMerge.get_package_info(general, "JSON")
        @test !isempty(info.version_info)

        # Pick a version and test compat/deps
        ver = first(keys(info.version_info))
        compat = AutoMerge.get_compat_for_version(general, "JSON", ver)
        deps = AutoMerge.get_deps_for_version(general, "JSON", ver)
        @test compat isa Dict
        @test deps isa Dict
    end
end
