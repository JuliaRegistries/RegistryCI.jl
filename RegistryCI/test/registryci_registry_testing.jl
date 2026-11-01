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
    @testset "Empty registry" begin
        mktempdir() do tmpdir
            registry_dir = joinpath(tmpdir, "TestRegistry")
            mkpath(registry_dir)

            write(joinpath(registry_dir, "Registry.toml"), """
                name = "TestRegistry"
                uuid = "12345678-1234-5678-9abc-123456789abc"
                repo = "https://github.com/test/TestRegistry.git"

                [packages]
                """)

            @test RegistryCI.test(registry_dir) === nothing
        end
    end

    @testset "Case-insensitive path collapse" begin
        mktempdir() do tmpdir
            registry_dir = joinpath(tmpdir, "TestRegistry")
            mkpath(registry_dir)

            write(joinpath(registry_dir, "Registry.toml"), """
                name = "TestRegistry"
                uuid = "12345678-1234-5678-9abc-123456789abc"
                repo = "https://github.com/test/TestRegistry.git"

                [packages]
                87654321-4321-8765-cba9-987654321cba = { name = "TestPkg", path = "T/TestPkg" }
                87654321-4321-8765-cba9-987654321cbb = { name = "TestPkg2", path = "t/TestPkg2" }

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
                """)

            pkg_dir = joinpath(registry_dir, "t", "TestPkg2")
            mkpath(pkg_dir)

            write(joinpath(pkg_dir, "Package.toml"), """
                name = "TestPkg2"
                uuid = "87654321-4321-8765-cba9-987654321cbb"
                repo = "https://github.com/test/TestPkg2.git"
                """)

            write(joinpath(pkg_dir, "Versions.toml"), """
                ["1.0.0"]
                git-tree-sha1 = "abcdef0123456789abcdef0123456789abcdef02"
                """)

            @test fails() do
                RegistryCI.test(registry_dir)
            end
        end
    end

    @testset "Deps and compat roundtrip with RegistryTools typed values" begin
        mktempdir() do tmpdir
            registry_dir = joinpath(tmpdir, "TestRegistry")
            mkpath(registry_dir)

            write(joinpath(registry_dir, "Registry.toml"), """
                name = "TestRegistry"
                uuid = "12345678-1234-5678-9abc-123456789abc"
                repo = "https://github.com/test/TestRegistry.git"

                [packages]
                87654321-4321-8765-cba9-987654321cba = { name = "TestPkg", path = "T/TestPkg" }
                aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee = { name = "OtherPkg", path = "O/OtherPkg" }
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
                """)
            write(joinpath(pkg_dir, "Deps.toml"), """
                ["1.0.0"]
                OtherPkg = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
                """)
            write(joinpath(pkg_dir, "Compat.toml"), """
                ["1.0.0"]
                OtherPkg = "1"
                julia = "1"
                """)

            other_pkg_dir = joinpath(registry_dir, "O", "OtherPkg")
            mkpath(other_pkg_dir)
            write(joinpath(other_pkg_dir, "Package.toml"), """
                name = "OtherPkg"
                uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
                repo = "https://github.com/test/OtherPkg.git"
                """)
            write(joinpath(other_pkg_dir, "Versions.toml"), """
                ["1.0.0"]
                git-tree-sha1 = "0123456789abcdef0123456789abcdef01234567"
                """)

            @test RegistryCI.test(registry_dir) === nothing
        end
    end

    @testset "Roundtrip normalization merges overlapping sections" begin
        versions = [v"0.1.0", v"0.5.0", v"1.0.0"]
        uuid_a = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        uuid_b = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

        # Versions 0.5.0 and 1.0.0 are covered by both sections, so they depend on A and B
        deps = Dict(
            "0 - 1" => Dict("A" => uuid_a),
            "0.5 - 1" => Dict("B" => uuid_b),
        )
        # The same data, split into sections differently
        deps_resplit = Dict(
            "0.1" => Dict("A" => uuid_a),
            "0.5 - 1" => Dict("A" => uuid_a, "B" => uuid_b),
        )
        normalized = RegistryCI._normalize_deps_roundtrip(deps, versions)
        @test normalized[v"0.1.0"] == Dict("A" => Base.UUID(uuid_a))
        @test normalized[v"0.5.0"] == Dict("A" => Base.UUID(uuid_a), "B" => Base.UUID(uuid_b))
        @test normalized == RegistryCI._normalize_deps_roundtrip(deps_resplit, versions)
        @test normalized != RegistryCI._normalize_deps_roundtrip(Dict("0 - 1" => Dict("A" => uuid_a)), versions)

        compat = Dict(
            "0 - 1" => Dict("julia" => "1"),
            "0.5 - 1" => Dict("B" => "0.2"),
        )
        compat_resplit = Dict(
            "0.1" => Dict("julia" => "1"),
            "0.5 - 1" => Dict("julia" => "1", "B" => "0.2"),
        )
        normalized = RegistryCI._normalize_compat_roundtrip(compat, versions)
        @test normalized[v"1.0.0"] == Dict(
            "julia" => Pkg.Types.VersionSpec("1"),
            "B" => Pkg.Types.VersionSpec("0.2"),
        )
        @test normalized == RegistryCI._normalize_compat_roundtrip(compat_resplit, versions)
    end

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
