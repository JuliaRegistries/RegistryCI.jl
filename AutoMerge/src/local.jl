"""
Helper functions for local AutoMerge checks.
"""

"""
    temp_git_dir(src::String; email="test@example.com", name="Test User") -> String

Create a temporary git repository by copying the source directory.
Returns the path to the temporary directory with the copied contents.
"""
function temp_git_dir(src::String; email="test@example.com", name="Test User")
    temp_parent = mktempdir()
    cp(src, temp_parent; force=true, follow_symlinks=true)

    bname = basename(src)
    # if src ends with a path separator, then basename(src) == ""
    if isempty(bname)
        bname = basename(dirname(src)) # RegistryCI.jl
    end

    temp_dir = joinpath(temp_parent, bname)
    @show readdir(temp_parent)
    @show isdir(temp_dir)

    # Initialize git repository if it isn't one
    if !isdir(joinpath(temp_dir, ".git"))
        for cmd in [`git init`, `git config user.email "$email"`, `git config user.name "$name"`, `git add .`, `git commit -m "Initial commit"`]
            Base.run(Cmd(cmd; dir=temp_dir))
        end
    end

    return temp_dir
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
    create_simulated_registry_with_package(
        package_path::String,
        registry_path::String
    ) -> String

Create a temporary copy of the registry with the package registration simulated using RegistryTools.
Returns the path to the temporary registry directory.
"""
function create_simulated_registry_with_package(
    package_path::String,
    registry_path::String
)
    # Create temporary directory for the simulated registry, which is a copy of the passed-in registry
    temp_registry = temp_git_dir(registry_path; email="automerge@local", name="AutoMerge Local")

    # Use RegistryTools.register to properly add the package
    project_file = joinpath(package_path, "Project.toml")

    # Create temporary git repository for the package
    temp_pkg_repo = temp_git_dir(package_path)
    local result
    try
        # Get the actual git tree hash
        actual_tree_hash = readchomp(Cmd(`git rev-parse "HEAD^{tree}"`; dir=temp_pkg_repo), String)

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
        if isnothing(result) || !hasfield(typeof(result), :branch)
            error("RegistryTools.register did not return a valid result with branch information")
        end

        registration_branch = result.branch
        if !occursin(registration_branch, read(Cmd(`git branch -a`; dir=temp_registry), String))
            error("RegistryTools registration branch '$registration_branch' not found in registry")
        end

        Base.run(Cmd(`git checkout $registration_branch`; dir=temp_registry))
        Base.run(Cmd(`git checkout main`; dir=temp_registry))
        Base.run(Cmd(`git merge $registration_branch --no-edit`; dir=temp_registry))

    finally
        # Clean up temporary package repo
        rm(temp_pkg_repo; recursive=true, force=true)
    end

    return temp_registry, result
end
