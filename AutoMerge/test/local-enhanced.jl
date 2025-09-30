using AutoMerge
using Test
using Dates
using TOML

@testset "Enhanced Local AutoMerge functionality with RegistryTools" begin
    @testset "RegistryTools integration" begin
        # Create a test package with dependencies
        tmppackage = mktempdir()
        project_file = joinpath(tmppackage, "Project.toml")
        project_content = """
        name = "EnhancedTestPkg"
        uuid = "11111111-2222-3333-4444-555555555555"
        version = "0.1.0"

        [deps]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [compat]
        julia = "1.6"
        """
        write(project_file, project_content)

        # Create src directory with proper structure
        src_dir = joinpath(tmppackage, "src")
        mkpath(src_dir)
        write(joinpath(src_dir, "EnhancedTestPkg.jl"), """
        module EnhancedTestPkg
        using Test

        function myfunction()
            @test true
            return "Hello from EnhancedTestPkg!"
        end

        end
        """)

        # Initialize git repo and make a commit
        run(Cmd(`git init`; dir=tmppackage))
        run(Cmd(`git config user.email "test@example.com"`; dir=tmppackage))
        run(Cmd(`git config user.name "Test User"`; dir=tmppackage))
        run(Cmd(`git add .`; dir=tmppackage))
        run(Cmd(`git commit -m "Initial commit"`; dir=tmppackage))

        # Create test registry with the Test package dependency
        tmpregistry = mktempdir()
        registry_toml = joinpath(tmpregistry, "Registry.toml")
        registry_content = """
        name = "TestRegistry"
        uuid = "87654321-4321-8765-4321-876543218765"

        [packages]
        "8dfed614-e22c-5e08-85e1-65c5234f0b40" = { name = "Test", path = "T/Test" }
        """
        write(registry_toml, registry_content)

        # Create Test package directory structure
        test_pkg_dir = joinpath(tmpregistry, "T", "Test")
        mkpath(test_pkg_dir)

        write(joinpath(test_pkg_dir, "Package.toml"), """
        name = "Test"
        uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
        repo = "https://github.com/JuliaLang/julia.git"
        """)

        write(joinpath(test_pkg_dir, "Versions.toml"), """
        ["1.0.0"]
        git-tree-sha1 = "aaaa1111222233334444555566667777888899999"
        """)

        # Run enhanced local_check with registry tests
        @info "Running enhanced local check with RegistryTools integration..."
        result = AutoMerge.local_check(tmppackage, tmpregistry)

        @test result.pkg == "EnhancedTestPkg"
        @test result.version == v"0.1.0"
        @test result.registration_type isa AutoMerge.NewPackage
        @test result.total_guidelines > 10  # Should have more guidelines now

        # Should have package loading guidelines now
        guideline_names = [g.info for g in vcat(result.passed_guidelines, result.failed_guidelines)]
        @test "Version can be `import`ed" in guideline_names
        @test "Version can be `Pkg.add`ed" in guideline_names

        # Print results for debugging
        println("Total guidelines: ", result.total_guidelines)
        println("Passed: ", length(result.passed_guidelines))
        println("Failed: ", length(result.failed_guidelines))

        if !isempty(result.failed_guidelines)
            println("Failed guidelines:")
            for g in result.failed_guidelines
                println("  • ", g.info)
                if !isempty(g.message)
                    println("    ", g.message)
                end
            end
        end

        rm(tmppackage; recursive=true)
        rm(tmpregistry; recursive=true)
    end

    @testset "Simulated registry creation with RegistryTools" begin
        # Test that create_simulated_registry_with_package works
        tmppackage = mktempdir()
        project_file = joinpath(tmppackage, "Project.toml")
        write(project_file, """
        name = "SimTestPkg"
        uuid = "22222222-3333-4444-5555-666666666666"
        version = "1.0.0"
        """)

        # Create src structure
        src_dir = joinpath(tmppackage, "src")
        mkpath(src_dir)
        write(joinpath(src_dir, "SimTestPkg.jl"), """
        module SimTestPkg
        greet() = "Hello from SimTestPkg!"
        end
        """)

        # Initialize git repo
        run(Cmd(`git init`; dir=tmppackage))
        run(Cmd(`git config user.email "test@example.com"`; dir=tmppackage))
        run(Cmd(`git config user.name "Test User"`; dir=tmppackage))
        run(Cmd(`git add .`; dir=tmppackage))
        run(Cmd(`git commit -m "Initial commit"`; dir=tmppackage))

        # Get git tree hash
        _, tree_hash = AutoMerge.get_current_commit_info(tmppackage)

        # Create base registry
        tmpregistry = mktempdir()
        write(joinpath(tmpregistry, "Registry.toml"), """
        name = "TestRegistry"
        uuid = "87654321-4321-8765-4321-876543218765"

        [packages]
        """)

        # Test simulated registry creation
        simulated_registry = AutoMerge.create_simulated_registry_with_package(
            tmppackage, tmpregistry, "SimTestPkg", v"1.0.0",
            "22222222-3333-4444-5555-666666666666", tree_hash
        )

        @test isdir(simulated_registry)
        @test isfile(joinpath(simulated_registry, "Registry.toml"))

        # Verify package was added to registry
        sim_registry_toml = TOML.parsefile(joinpath(simulated_registry, "Registry.toml"))
        @test haskey(sim_registry_toml["packages"], "22222222-3333-4444-5555-666666666666")
        @test sim_registry_toml["packages"]["22222222-3333-4444-5555-666666666666"]["name"] == "SimTestPkg"

        rm(tmppackage; recursive=true)
        rm(tmpregistry; recursive=true)
    end

    @testset "Error handling" begin
        # Test with malformed package
        tmpdir = mktempdir()
        write(joinpath(tmpdir, "Project.toml"), "invalid toml content [[[")

        tmpregistry = mktempdir()
        write(joinpath(tmpregistry, "Registry.toml"), """
        name = "TestRegistry"
        uuid = "87654321-4321-8765-4321-876543218765"

        [packages]
        """)

        # Should throw an error during package info detection
        @test_throws Exception AutoMerge.local_check(tmpdir, tmpregistry)

        rm(tmpdir; recursive=true)
        rm(tmpregistry; recursive=true)
    end
end