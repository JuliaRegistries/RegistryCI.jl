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

Create a temporary copy of the registry with the package registration simulated using RegistryTools.
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

    # Copy original registry to temp location and initialize as git repo
    cp(registry_path, temp_registry; force=true)

    # Initialize the temporary registry as a git repository
    # RegistryTools expects registries to be git repositories
    Base.run(Cmd(`git init`; dir=temp_registry))
    Base.run(Cmd(`git config user.email "automerge@local"`; dir=temp_registry))
    Base.run(Cmd(`git config user.name "AutoMerge Local"`; dir=temp_registry))
    Base.run(Cmd(`git add .`; dir=temp_registry))

    # Make initial commit if there are files to commit
    try
        Base.run(Cmd(`git commit -m "Initial registry state"`; dir=temp_registry))
    catch
        # If no files to commit, make an empty commit
        Base.run(Cmd(`git commit --allow-empty -m "Initial registry state"`; dir=temp_registry))
    end

    # Use RegistryTools.register to properly add the package
    # We need a Project instance for the package
    project_file = joinpath(package_path, "Project.toml")

    # Use RegistryTools.register with push=false to simulate registration
    result = RegistryTools.register(
        "https://github.com/example/$(pkg).jl.git",  # placeholder repo URL
        project_file,
        tree_hash;
        registry=temp_registry,
        registry_fork=temp_registry,
        registry_deps=String[],  # Will be passed from calling function if needed
        push=false,  # Don't actually push - just modify the local registry
        force_reset=true,
    )

    # Check if registration was successful
    if !isnothing(result)
        @info "RegistryTools registration completed successfully" result=result

        # RegistryTools might have modified the registry in place
        # Let's check if the registry was updated
        registry_toml = TOML.parsefile(joinpath(temp_registry, "Registry.toml"))
        if haskey(registry_toml, "packages")
            @info "Registry now contains packages" count=length(registry_toml["packages"])
        else
            @warn "No packages found in registry after RegistryTools.register"
        end
    else
        @warn "RegistryTools.register returned nothing"
    end

    return temp_registry
end
