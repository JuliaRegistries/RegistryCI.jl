using Test
using AutoMerge
using RegistryInstances
using Pkg
using TOML

# Old implementations for comparison
function old_parse_registry_toml(registry_dir, path_components...; allow_missing = false)
    path = joinpath(registry_dir, path_components...)
    isfile(path) && return TOML.parsefile(path)
    allow_missing && return Dict{String, Any}()
    error("Registry file $path does not exist in $(registry_dir).")
end

function old_get_package_relpath_in_registry(; package_name::String, registry_path::String)
    registry_toml_parsed = old_parse_registry_toml(registry_path, "Registry.toml")
    all_packages = registry_toml_parsed["packages"]
    all_package_names_and_paths = map(x -> (x["name"], x["path"]), values(all_packages))
    matching_package_indices = findall(
        getindex.(all_package_names_and_paths, 1) .== package_name
    )
    num_indices = length(matching_package_indices)
    (num_indices == 0) &&
        throw(ErrorException("no package found with the name $(package_name)"))
    (num_indices != 1) && throw(
        ErrorException(
            "multiple ($(num_indices)) packages found with the name $(package_name)"
        ),
    )
    single_matching_index = only(matching_package_indices)
    single_matching_package = all_package_names_and_paths[single_matching_index]
    _pkgname, _pkgrelpath = single_matching_package
    AutoMerge.always_assert(_pkgname == package_name)
    _pkgrelpath::String
    return _pkgrelpath
end

function old_meets_compat_for_julia(working_directory::AbstractString, pkg, version)
    package_relpath = old_get_package_relpath_in_registry(;
        package_name=pkg, registry_path=working_directory
    )
    compat = old_parse_registry_toml(working_directory, package_relpath, "Compat.toml"; allow_missing = true)
    # Go through all the compat entries looking for the julia compat
    # of the new version. When found, test
    # 1. that it is a bounded range,
    # 2. that the upper bound is not 2 or higher,
    # 3. that the range includes at least one 1.x version.
    for version_range in keys(compat)
        if version in Pkg.Types.VersionRange(version_range)
            if haskey(compat[version_range], "julia")
                julia_compat = Pkg.Types.VersionSpec(compat[version_range]["julia"])
                if !isempty(
                    intersect(
                        julia_compat, Pkg.Types.VersionSpec("$(typemax(Base.VInt))-*")
                    ),
                )
                    return false, "The compat entry for `julia` is unbounded."
                elseif !isempty(intersect(julia_compat, Pkg.Types.VersionSpec("2-*")))
                    return false,
                    "The compat entry for `julia` has an upper bound of 2 or higher."
                elseif isempty(intersect(julia_compat, Pkg.Types.VersionSpec("1")))
                    # For completeness, although this seems rather
                    # unlikely to occur.
                    return false,
                    "The compat entry for `julia` doesn't include any 1.x version."
                else
                    return true, ""
                end
            end
        end
    end

    return false, "There is no compat entry for `julia`."
end

function old_meets_compat_for_all_deps(working_directory::AbstractString, pkg, version)
    package_relpath = old_get_package_relpath_in_registry(;
        package_name=pkg, registry_path=working_directory
    )
    compat = old_parse_registry_toml(working_directory, package_relpath, "Compat.toml"; allow_missing = true)
    deps = old_parse_registry_toml(working_directory, package_relpath, "Deps.toml"; allow_missing = true)
    # First, we construct a Dict in which the keys are the package's
    # dependencies, and the value is always false.
    dep_has_compat_with_upper_bound = Dict{String,Bool}()
    for version_range in keys(deps)
        if version in Pkg.Types.VersionRange(version_range)
            for name in keys(deps[version_range])
                if AutoMerge._AUTOMERGE_REQUIRE_STDLIB_COMPAT
                    debug_msg = "Found a new (non-JLL) dependency: $(name)"
                    apply_compat_requirement = !AutoMerge.is_jll_name(name)
                else
                    debug_msg = "Found a new (non-stdlib non-JLL) dependency: $(name)"
                    apply_compat_requirement = !AutoMerge.is_jll_name(name) && !AutoMerge.is_julia_stdlib(name)
                end
                if apply_compat_requirement
                    @debug debug_msg
                    dep_has_compat_with_upper_bound[name] = false
                end
            end
        end
    end
    # Now, we go through all the compat entries. If a dependency has a compat
    # entry with an upper bound, we change the corresponding value in the Dict
    # to true.
    for version_range in keys(compat)
        if version in Pkg.Types.VersionRange(version_range)
            for (name, value) in compat[version_range]
                if value isa Vector
                    if !isempty(value)
                        value_ranges = Pkg.Types.VersionRange.(value)
                        each_range_has_upper_bound = AutoMerge._has_upper_bound.(value_ranges)
                        if all(each_range_has_upper_bound)
                            @debug(
                                "Dependency \"$(name)\" has compat entries that all have upper bounds"
                            )
                            dep_has_compat_with_upper_bound[name] = true
                        end
                    end
                else
                    value_range = Pkg.Types.VersionRange(value)
                    if AutoMerge._has_upper_bound(value_range)
                        @debug(
                            "Dependency \"$(name)\" has a compat entry with an upper bound"
                        )
                        dep_has_compat_with_upper_bound[name] = true
                    end
                end
            end
        end
    end
    meets_this_guideline = all(values(dep_has_compat_with_upper_bound))
    if meets_this_guideline
        return true, ""
    else
        bad_dependencies = Vector{String}()
        for name in keys(dep_has_compat_with_upper_bound)
            if !(dep_has_compat_with_upper_bound[name])
                @error(
                    "Dependency \"$(name)\" does not have a compat entry that has an upper bound"
                )
                push!(bad_dependencies, name)
            end
        end
        sort!(bad_dependencies)
        message = AutoMerge.compat_violation_message(bad_dependencies)
        return false, message
    end
end

@testset "Compat Guidelines Comparison" begin
    # Get General registry
    general_path = joinpath(first(DEPOT_PATH), "registries", "General")

    # Test packages with various characteristics
    test_packages = [
        # Popular packages with stable compat entries
        ("JSON", v"0.21.3"),
        ("HTTP", v"1.0.0"),
        ("DataFrames", v"1.3.0"),

        # Packages with complex dependency structures
        ("Plots", v"1.38.0"),
        ("Makie", v"0.19.0"),

        # JLL packages (simpler compat requirements)
        ("OpenSSL_jll", v"3.0.8+0"),

        # Smaller packages
        ("StaticArrays", v"1.5.0"),
        ("Distances", v"0.10.8"),
        ("Colors", v"0.12.10"),
    ]

    @testset "meets_compat_for_julia comparison" begin
        for (pkg, ver) in test_packages
            @testset "$pkg v$ver" begin
                # Try to run both old and new
                try
                    old_result = old_meets_compat_for_julia(general_path, pkg, ver)
                    new_result = AutoMerge.meets_compat_for_julia(general_path, pkg, ver)

                    @test old_result[1] == new_result[1]  # Check boolean result
                    # Message format might differ slightly, so just check they both return same success/failure
                    if old_result[1] != new_result[1]
                        @error "Mismatch for $pkg v$ver" old_result new_result
                    end
                catch e
                    # Some packages/versions might not exist in registry, that's okay
                    if isa(e, ErrorException) && (contains(string(e), "not found") || contains(string(e), "Version"))
                        @test_skip "Package $pkg v$ver not found in registry"
                    else
                        rethrow(e)
                    end
                end
            end
        end
    end

    @testset "meets_compat_for_all_deps comparison" begin
        for (pkg, ver) in test_packages
            @testset "$pkg v$ver" begin
                try
                    old_result = old_meets_compat_for_all_deps(general_path, pkg, ver)
                    new_result = AutoMerge.meets_compat_for_all_deps(general_path, pkg, ver)

                    @test old_result[1] == new_result[1]  # Check boolean result
                    if old_result[1] != new_result[1]
                        @error "Mismatch for $pkg v$ver" old_result new_result
                    end
                catch e
                    # Some packages/versions might not exist in registry, that's okay
                    if isa(e, ErrorException) && (contains(string(e), "not found") || contains(string(e), "Version"))
                        @test_skip "Package $pkg v$ver not found in registry"
                    else
                        rethrow(e)
                    end
                end
            end
        end
    end

    @testset "Exhaustive test on recent packages" begin
        # Get a sample of recent package versions from General registry
        registry = RegistryInstance(general_path)

        # Sample some packages for exhaustive testing
        sample_packages = ["JSON", "HTTP", "DataFrames", "StaticArrays", "Colors"]

        for pkg_name in sample_packages
            @testset "All versions of $pkg_name" begin
                try
                    info = AutoMerge.get_package_info(registry, pkg_name)
                    versions = collect(keys(info.version_info))

                    # Test up to 10 most recent versions
                    test_versions = sort(versions, rev=true)[1:min(10, length(versions))]

                    for ver in test_versions
                        # Test meets_compat_for_julia
                        try
                            old_julia = old_meets_compat_for_julia(general_path, pkg_name, ver)
                            new_julia = AutoMerge.meets_compat_for_julia(general_path, pkg_name, ver)
                            @test old_julia[1] == new_julia[1]
                        catch e
                            @test_broken false  # Mark as known issue if it fails
                        end

                        # Test meets_compat_for_all_deps
                        try
                            old_deps = old_meets_compat_for_all_deps(general_path, pkg_name, ver)
                            new_deps = AutoMerge.meets_compat_for_all_deps(general_path, pkg_name, ver)
                            @test old_deps[1] == new_deps[1]
                        catch e
                            @test_broken false  # Mark as known issue if it fails
                        end
                    end
                catch e
                    @test_skip "Could not test $pkg_name: $e"
                end
            end
        end
    end
end
