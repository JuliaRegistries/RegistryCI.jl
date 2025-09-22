"""
Helper functions for local AutoMerge checks.
"""

"""
    detect_package_info(package_path::String) -> (pkg::String, version::VersionNumber, uuid::String)

Extract package name, version, and UUID from Project.toml in the given package directory.
"""
function detect_package_info(package_path::String)
    project_file = joinpath(package_path, "Project.toml")
    if !isfile(project_file)
        throw(ArgumentError("Project.toml not found in $package_path"))
    end

    project = TOML.parsefile(project_file)

    pkg = get(project, "name", nothing)
    if pkg === nothing
        throw(ArgumentError("Package name not found in Project.toml"))
    end

    version_str = get(project, "version", nothing)
    if version_str === nothing
        throw(ArgumentError("Package version not found in Project.toml"))
    end
    version = VersionNumber(version_str)

    uuid = get(project, "uuid", nothing)
    if uuid === nothing
        throw(ArgumentError("Package UUID not found in Project.toml"))
    end

    return pkg, version, uuid
end

"""
    get_current_commit_info(package_path::String) -> (commit_sha::String, tree_hash::String)

Get the current commit SHA and tree hash from the git repository in the package directory.
"""
function get_current_commit_info(package_path::String)
    commit_sha = try
        String(readchomp(Cmd(`git rev-parse HEAD`; dir=package_path)))
    catch e
        throw(ArgumentError("Failed to get commit SHA from $package_path. Is this a git repository? Error: $e"))
    end

    tree_hash = try
        String(readchomp(Cmd(`git rev-parse "HEAD^{tree}"`; dir=package_path)))
    catch e
        throw(ArgumentError("Failed to get tree hash from $package_path. Error: $e"))
    end

    return commit_sha, tree_hash
end

"""
    determine_registration_type(pkg::String, registry_path::String) -> Union{NewPackage, NewVersion}

Determine if this would be a new package or new version registration.
"""
function determine_registration_type(pkg::String, registry_path::String)
    # Check if package already exists in registry
    registry_toml = joinpath(registry_path, "Registry.toml")
    if !isfile(registry_toml)
        throw(ArgumentError("Registry.toml not found in $registry_path"))
    end

    registry = TOML.parsefile(registry_toml)
    packages = get(registry, "packages", Dict())

    # Look for package by name in the registry
    for (uuid, pkg_info) in packages
        if get(pkg_info, "name", "") == pkg
            return NewVersion()
        end
    end

    return NewPackage()
end

"""
    create_simulated_registry_with_package(
        package_path::String,
        registry_path::String,
        pkg::String,
        version::VersionNumber,
        uuid::String,
        tree_hash::String
    ) -> String

Create a temporary copy of the registry with the package registration simulated.
Returns the path to the temporary registry directory.
"""
function create_simulated_registry_with_package(
    package_path::String,
    registry_path::String,
    pkg::String,
    version::VersionNumber,
    uuid::String,
    tree_hash::String
)
    # Create temporary directory for the simulated registry
    temp_registry = mktempdir(; cleanup=true)

    # Copy original registry to temp location
    cp(registry_path, temp_registry; force=true)

    # Add the package registration to the temporary registry
    _add_package_to_registry!(temp_registry, pkg, uuid, version, tree_hash, package_path)

    return temp_registry
end

"""
    _add_package_to_registry!(registry_path, pkg, uuid, version, tree_hash, package_path)

Internal function to add a package registration to a registry.
This simulates what Registrator would do.
"""
function _add_package_to_registry!(registry_path::String, pkg::String, uuid::String, version::VersionNumber, tree_hash::String, package_path::String)
    # Update Registry.toml
    registry_toml_path = joinpath(registry_path, "Registry.toml")
    registry_toml = TOML.parsefile(registry_toml_path)

    # Create package entry if it doesn't exist
    if !haskey(registry_toml, "packages")
        registry_toml["packages"] = Dict()
    end

    # Determine package directory structure (first letter of name)
    first_letter = uppercase(string(pkg[1]))
    pkg_dir = joinpath(registry_path, first_letter, pkg)
    pkg_relpath = joinpath(first_letter, pkg)

    # Add package to registry
    registry_toml["packages"][uuid] = Dict(
        "name" => pkg,
        "path" => pkg_relpath
    )

    # Write updated Registry.toml
    open(registry_toml_path, "w") do io
        TOML.print(io, registry_toml)
    end

    # Create package directory
    mkpath(pkg_dir)

    # Create Package.toml
    package_toml = Dict(
        "name" => pkg,
        "uuid" => uuid,
        "repo" => "https://github.com/example/$(pkg).jl.git"  # placeholder
    )

    open(joinpath(pkg_dir, "Package.toml"), "w") do io
        TOML.print(io, package_toml)
    end

    # Create Versions.toml
    versions_toml = Dict(
        string(version) => Dict("git-tree-sha1" => tree_hash)
    )

    open(joinpath(pkg_dir, "Versions.toml"), "w") do io
        TOML.print(io, versions_toml)
    end

    # Create Compat.toml (basic julia compat)
    project_file = joinpath(package_path, "Project.toml")
    if isfile(project_file)
        project = TOML.parsefile(project_file)
        compat = get(project, "compat", Dict())

        if !isempty(compat)
            compat_toml = Dict(string(version) => compat)
            open(joinpath(pkg_dir, "Compat.toml"), "w") do io
                TOML.print(io, compat_toml)
            end
        end

        # Create Deps.toml if there are dependencies
        deps = get(project, "deps", Dict())
        if !isempty(deps)
            deps_toml = Dict(string(version) => deps)
            open(joinpath(pkg_dir, "Deps.toml"), "w") do io
                TOML.print(io, deps_toml)
            end
        end
    end
end