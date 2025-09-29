using Dates
# using GitCommand
using GitHub
using JSON
using Pkg
using Printf
using RegistryCI
using Test
using TimeZones
using MetaTesting: fails

# Testing with General can be quite slow. We do it by default,
# but locally you can run
# julia --project -e 'using Pkg; Pkg.test(test_args=["false"])'
# to test without it.
if length(ARGS) == 1
    test_general = parse(Bool, ARGS[1])
else
    test_general = true
end

if test_general
    @testset "Public interface" begin
        @testset "RegistryCI.test on general" begin
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
end

@testset "Synthetic tests" begin
    @testset "Yanked key validation" begin
        mktempdir() do tmpdir
            registry_dir = joinpath(tmpdir, "TestRegistry")
            mkpath(registry_dir)

            write(joinpath(registry_dir, "Registry.toml"), """
                name = "TestRegistry"
                uuid = "12345678-1234-5678-9abc-123456789abc"
                repo = "https://github.com/test/TestRegistry.git"

                [packages]
                87654321-4321-8765-cba9-987654321cba = { name = "TestPkg", path = "T/TestPkg" }
                """)

            pkg_dir = joinpath(registry_dir, "T", "TestPkg")
            mkpath(pkg_dir)

            write(joinpath(pkg_dir, "Package.toml"), """
                name = "TestPkg"
                uuid = "87654321-4321-8765-cba9-987654321cba"
                repo = "https://github.com/test/TestPkg.git"
                """)

            write(joinpath(pkg_dir, "Versions.toml"), """
                ["1.0.0"]
                git-tree-sha1 = "abcdef0123456789abcdef0123456789abcdef01"
                yanked = true
                """)

            @test RegistryCI.test(registry_dir) === nothing

            for invalid_key in ("\"invalid\"", "\"false\"", "false", "\"true\"")
                write(joinpath(pkg_dir, "Versions.toml"), """
                    ["1.0.0"]
                    git-tree-sha1 = "abcdef0123456789abcdef0123456789abcdef01"
                    yanked = $invalid_key
                    """)

                @testset "Invalid yanked test" begin
                    @test fails() do
                        RegistryCI.test(registry_dir)
                    end
                end
            end
        end
    end
end
