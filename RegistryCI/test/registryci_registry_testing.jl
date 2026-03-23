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

function write_test_registry!(registry_dir; versions_toml, deps_toml=nothing, compat_toml=nothing)
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

    write(joinpath(pkg_dir, "Versions.toml"), versions_toml)
    if deps_toml !== nothing
        write(joinpath(pkg_dir, "Deps.toml"), deps_toml)
    end
    if compat_toml !== nothing
        write(joinpath(pkg_dir, "Compat.toml"), compat_toml)
    end
    return pkg_dir
end

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
            pkg_dir = write_test_registry!(
                registry_dir;
                versions_toml="""
                ["1.0.0"]
                git-tree-sha1 = "abcdef0123456789abcdef0123456789abcdef01"
                yanked = true
                """,
            )

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

    @testset "Compat entries must match active dependencies per version" begin
        mktempdir() do tmpdir
            registry_dir = joinpath(tmpdir, "TestRegistry")
            pkg_dir = write_test_registry!(
                registry_dir;
                versions_toml="""
                ["1.0.0"]
                git-tree-sha1 = "abcdef0123456789abcdef0123456789abcdef01"

                ["1.1.0"]
                git-tree-sha1 = "0123456789abcdef0123456789abcdef01234567"
                """,
                deps_toml="""
                ["1.1.0"]
                Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
                """,
                compat_toml="""
                ["1.0.0-1.1.0"]
                Dates = "1"
                julia = "1"
                """,
            )

            vers = Pkg.TOML.parsefile(joinpath(pkg_dir, "Versions.toml"))
            vnums = VersionNumber.(keys(vers))
            deps_by_version = RegistryCI.load_package_data(
                Base.UUID, joinpath(pkg_dir, "Deps.toml"), vnums
            )
            compat_by_version = RegistryCI.load_package_data(
                Pkg.Types.VersionSpec, joinpath(pkg_dir, "Compat.toml"), vnums
            )

            @test_throws ErrorException RegistryCI.check_compat_entries_have_matching_deps(
                vnums, deps_by_version, compat_by_version
            )
        end
    end

    @testset "Compat entries may be narrower than the dependency's total range" begin
        mktempdir() do tmpdir
            registry_dir = joinpath(tmpdir, "TestRegistry")
            pkg_dir = write_test_registry!(
                registry_dir;
                versions_toml="""
                ["1.0.0"]
                git-tree-sha1 = "abcdef0123456789abcdef0123456789abcdef01"

                ["1.1.0"]
                git-tree-sha1 = "0123456789abcdef0123456789abcdef01234567"
                """,
                deps_toml="""
                ["1.1.0"]
                Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
                """,
                compat_toml="""
                ["1.0.0-1.1.0"]
                julia = "1"

                ["1.1.0"]
                Dates = "1"
                """,
            )

            vers = Pkg.TOML.parsefile(joinpath(pkg_dir, "Versions.toml"))
            vnums = VersionNumber.(keys(vers))
            deps_by_version = RegistryCI.load_package_data(
                Base.UUID, joinpath(pkg_dir, "Deps.toml"), vnums
            )
            compat_by_version = RegistryCI.load_package_data(
                Pkg.Types.VersionSpec, joinpath(pkg_dir, "Compat.toml"), vnums
            )
            @test RegistryCI.check_compat_entries_have_matching_deps(
                vnums, deps_by_version, compat_by_version
            ) === nothing
            @test RegistryCI.test(registry_dir) === nothing
        end
    end
end
