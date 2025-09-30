using AutoMerge
using Test
using Dates
using TOML

@testset "Local AutoMerge functionality" begin
    @testset "detect_package_info" begin
        # Create a temporary package directory for testing
        tmpdir = mktempdir()
        project_file = joinpath(tmpdir, "Project.toml")

        # Test valid Project.toml
        project_content = """
        name = "TestPkg"
        uuid = "12345678-1234-5678-1234-567812345678"
        version = "1.2.3"

        [deps]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
        """

        write(project_file, project_content)

        pkg, version, uuid = AutoMerge.detect_package_info(tmpdir)
        @test pkg == "TestPkg"
        @test version == v"1.2.3"
        @test uuid == "12345678-1234-5678-1234-567812345678"

        # Test missing Project.toml
        rm(project_file)
        @test_throws ArgumentError AutoMerge.detect_package_info(tmpdir)

        # Test Project.toml missing required fields
        write(project_file, "name = \"TestPkg\"")  # missing version and uuid
        @test_throws ArgumentError AutoMerge.detect_package_info(tmpdir)

        rm(tmpdir; recursive=true)
    end

    @testset "create_simulated_registry_with_package" begin
        # Create temporary package directory
        tmppackage = mktempdir()
        project_file = joinpath(tmppackage, "Project.toml")
        project_content = """
        name = "TestPkg"
        uuid = "12345678-1234-5678-1234-567812345678"
        version = "0.1.0"

        [compat]
        julia = "1.6"

        [deps]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
        """
        write(project_file, project_content)

        # Create temporary registry
        tmpregistry = mktempdir()
        registry_toml = joinpath(tmpregistry, "Registry.toml")
        registry_content = """
        name = "TestRegistry"
        uuid = "87654321-4321-8765-4321-876543218765"

        [packages]
        """
        write(registry_toml, registry_content)

        # Create simulated registry
        simulated_registry = AutoMerge.create_simulated_registry_with_package(
            tmppackage, tmpregistry
        )

        # Verify the simulated registry has the package
        sim_registry_toml = TOML.parsefile(joinpath(simulated_registry, "Registry.toml"))
        @test haskey(sim_registry_toml["packages"], "12345678-1234-5678-1234-567812345678")
        @test sim_registry_toml["packages"]["12345678-1234-5678-1234-567812345678"]["name"] == "TestPkg"

        # Verify package files were created
        pkg_dir = joinpath(simulated_registry, "T", "TestPkg")
        @test isdir(pkg_dir)
        @test isfile(joinpath(pkg_dir, "Package.toml"))
        @test isfile(joinpath(pkg_dir, "Versions.toml"))
        @test isfile(joinpath(pkg_dir, "Compat.toml"))
        @test isfile(joinpath(pkg_dir, "Deps.toml"))

        # Verify package content
        package_toml = TOML.parsefile(joinpath(pkg_dir, "Package.toml"))
        @test package_toml["name"] == "TestPkg"
        @test package_toml["uuid"] == "12345678-1234-5678-1234-567812345678"

        versions_toml = TOML.parsefile(joinpath(pkg_dir, "Versions.toml"))
        @test haskey(versions_toml, "0.1.0")
        # RegistryTools uses the actual git tree hash, so just verify it's a valid hash
        tree_hash = versions_toml["0.1.0"]["git-tree-sha1"]
        @test length(tree_hash) == 40  # SHA-1 hash is 40 characters
        @test all(c -> c in "0123456789abcdef", tree_hash)  # Valid hex characters

        rm(tmppackage; recursive=true)
        rm(tmpregistry; recursive=true)
    end

    @testset "LocalAutoMergeData construction" begin
        data = AutoMerge.LocalAutoMergeData(
            AutoMerge.NewPackage(),
            "TestPkg",
            v"1.0.0",
            "abc123",
            "/tmp/registry_head",
            "/tmp/registry_master",
            true,
            String[],
            "/tmp/pkg",
            String[],
            String[]
        )

        @test data.registration_type isa AutoMerge.NewPackage
        @test data.pkg == "TestPkg"
        @test data.version == v"1.0.0"
        @test data.current_pr_head_commit_sha == "abc123"
        @test data.suggest_onepointzero == true
        @test data.pkg_code_path == "/tmp/pkg"
    end

    @testset "_get_local_guidelines" begin
        # Test new package guidelines
        new_pkg_guidelines = AutoMerge._get_local_guidelines(AutoMerge.NewPackage(); check_license=false)
        @test length(new_pkg_guidelines) > 0

        # Verify some specific guidelines are included
        guideline_names = [g[1].info for g in new_pkg_guidelines]
        @test "Name is a Julia identifier" in guideline_names
        @test "Normal capitalization" in guideline_names
        @test "Name not too short" in guideline_names

        # Test new version guidelines
        new_version_guidelines = AutoMerge._get_local_guidelines(AutoMerge.NewVersion(); check_license=false)
        @test length(new_version_guidelines) > 0

        # New version should have fewer guidelines than new package
        @test length(new_version_guidelines) < length(new_pkg_guidelines)
    end
end

@testset "Local AutoMerge integration tests" begin
    # These tests require a more realistic setup but are designed to be lightweight

    @testset "local_check with mock package - new package" begin
        # Create a realistic test package
        tmppackage = mktempdir()

        # Create Project.toml
        project_file = joinpath(tmppackage, "Project.toml")
        project_content = """
        name = "LocalTestPkg"
        uuid = "11111111-2222-3333-4444-555555555555"
        version = "0.1.0"

        [compat]
        julia = "1.6"
        """
        write(project_file, project_content)

        # Initialize git repo and make a commit
        run(Cmd(`git init`; dir=tmppackage))
        run(Cmd(`git config user.email "test@example.com"`; dir=tmppackage))
        run(Cmd(`git config user.name "Test User"`; dir=tmppackage))
        run(Cmd(`git add Project.toml`; dir=tmppackage))
        run(Cmd(`git commit -m "Initial commit"`; dir=tmppackage))

        # Create src directory with proper structure
        src_dir = joinpath(tmppackage, "src")
        mkpath(src_dir)
        write(joinpath(src_dir, "LocalTestPkg.jl"), """
        module LocalTestPkg

        greet() = "Hello, World!"

        end
        """)

        # Create temporary registry
        tmpregistry = mktempdir()
        registry_toml = joinpath(tmpregistry, "Registry.toml")
        registry_content = """
        name = "TestRegistry"
        uuid = "87654321-4321-8765-4321-876543218765"

        [packages]
        """
        write(registry_toml, registry_content)

        # Run local_check
        results = AutoMerge.local_check(tmppackage, tmpregistry)

        @test results.pkg == "LocalTestPkg"
        @test results.version == v"0.1.0"
        @test results.registration_type isa AutoMerge.NewPackage
        @test results.total_guidelines > 0
        @test length(results.passed_guidelines) + length(results.failed_guidelines) == results.total_guidelines

        rm(tmppackage; recursive=true)
        rm(tmpregistry; recursive=true)
    end

    @testset "local_check error handling" begin
        # Test with non-existent package path
        tmpregistry = mktempdir()
        registry_toml = joinpath(tmpregistry, "Registry.toml")
        write(registry_toml, """
        name = "TestRegistry"
        uuid = "87654321-4321-8765-4321-876543218765"

        [packages]
        """)

        @test_throws ArgumentError AutoMerge.local_check("/nonexistent/path", tmpregistry)

        # Test with non-existent registry path
        tmppackage = mktempdir()
        write(joinpath(tmppackage, "Project.toml"), """
        name = "TestPkg"
        uuid = "12345678-1234-5678-1234-567812345678"
        version = "1.0.0"
        """)

        @test_throws ArgumentError AutoMerge.local_check(tmppackage, "/nonexistent/registry")

        rm(tmppackage; recursive=true)
        rm(tmpregistry; recursive=true)
    end
end
