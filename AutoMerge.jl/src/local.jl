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

    # Copy original registry to temp location
    # Use force=true to ensure proper copying and recursive to copy subdirectories
    cp(registry_path, temp_registry; force=true, follow_symlinks=true)

    # Remove any potential issues with the temp directory
    if isdir(joinpath(temp_registry, basename(registry_path)))
        # If cp created a subdirectory, move contents up
        source_dir = joinpath(temp_registry, basename(registry_path))
        for item in readdir(source_dir)
            mv(joinpath(source_dir, item), joinpath(temp_registry, item); force=true)
        end
        rm(source_dir; recursive=true)
    end

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
    project_file = joinpath(package_path, "Project.toml")

    # Create temporary git repository for the package
    temp_pkg_repo = mktempdir()
    try
        # Copy package to temporary location and ensure proper git structure
        cp(package_path, temp_pkg_repo; force=true, follow_symlinks=true)

        # Handle potential nested directory from cp
        if isdir(joinpath(temp_pkg_repo, basename(package_path)))
            source_dir = joinpath(temp_pkg_repo, basename(package_path))
            for item in readdir(source_dir)
                mv(joinpath(source_dir, item), joinpath(temp_pkg_repo, item); force=true)
            end
            rm(source_dir; recursive=true)
        end

        # Initialize git repository if needed
        if !isdir(joinpath(temp_pkg_repo, ".git"))
            Base.run(Cmd(`git init`; dir=temp_pkg_repo))
            Base.run(Cmd(`git config user.email "test@example.com"`; dir=temp_pkg_repo))
            Base.run(Cmd(`git config user.name "Test User"`; dir=temp_pkg_repo))
            Base.run(Cmd(`git add .`; dir=temp_pkg_repo))
            Base.run(Cmd(`git commit -m "Initial commit"`; dir=temp_pkg_repo))
        end

        # Get the actual git tree hash
        actual_tree_hash = read(Cmd(`git rev-parse "HEAD^{tree}"`; dir=temp_pkg_repo), String) |> strip

        # Use RegistryTools.register with file:// URLs
        registry_url = "file://" * temp_registry
        package_url = "file://" * temp_pkg_repo

        result = RegistryTools.register(
            package_url,
            joinpath(temp_pkg_repo, "Project.toml"),
            actual_tree_hash;
            registry=registry_url,
            registry_fork=registry_url,
            registry_deps=String[],
            push=true,
            force_reset=true,
        )

        # Merge the registration branch that RegistryTools created
        if !isnothing(result) && hasfield(typeof(result), :branch)
            registration_branch = result.branch
            if occursin(registration_branch, read(Cmd(`git branch -a`; dir=temp_registry), String))
                Base.run(Cmd(`git checkout $registration_branch`; dir=temp_registry))
                Base.run(Cmd(`git checkout main`; dir=temp_registry))
                Base.run(Cmd(`git merge $registration_branch --no-edit`; dir=temp_registry))
            end
        end

        # Verify registration was successful
        registry_toml = TOML.parsefile(joinpath(temp_registry, "Registry.toml"))
        if !haskey(registry_toml, "packages") || !haskey(registry_toml["packages"], uuid)
            error("RegistryTools.register completed but package not found in registry")
        end

    finally
        # Clean up temporary package repo
        rm(temp_pkg_repo; recursive=true, force=true)
    end

    return temp_registry
end

