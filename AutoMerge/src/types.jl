struct AlwaysAssertionError <: Exception
    msg::String
end

struct NewPackage end
struct NewVersion end

abstract type AutoMergeException <: Exception end

struct AutoMergeAuthorNotAuthorized <: AutoMergeException
    msg::String
end

struct AutoMergeCronJobError <: AutoMergeException
    msg::String
end

struct AutoMergeGuidelinesNotMet <: AutoMergeException
    msg::String
end

struct AutoMergeNeitherNewPackageNorNewVersion <: AutoMergeException
    msg::String
end

struct AutoMergePullRequestNotOpen <: AutoMergeException
    msg::String
end

struct AutoMergeShaMismatch <: AutoMergeException
    msg::String
end

struct AutoMergeWrongBuildType <: AutoMergeException
    msg::String
end

struct ErrorCannotComputeVersionDifference
    msg::String
end

struct GitHubAutoMergeData
    # Handle to the GitHub API. Used to query the PR and update
    # comments and status.
    api::GitHub.GitHubAPI

    # Whether the registry PR refers to a new package or a new version
    # of an existing package.
    registration_type::Union{NewPackage,NewVersion}

    # The GitHub pull request data.
    pr::GitHub.PullRequest

    # Name of the package being registered.
    pkg::String

    # Version of the package being registered.
    version::VersionNumber

    # Used for updating CI status.
    current_pr_head_commit_sha::String

    # The GitHub repo data for the registry.
    registry::GitHub.Repo

    # GitHub authorization data.
    auth::GitHub.Authorization

    # Type of authorization for automerge. This can be either:
    # :jll - special jll exceptions are allowed,
    # :normal - normal automerge rules.
    authorization::Symbol

    # Directory of a registry clone that includes the PR.
    registry_head::String

    # Directory of a registry clone that excludes the PR.
    registry_master::String

    # Whether to add a comment suggesting bumping package version to
    # 1.0 if appropriate.
    suggest_onepointzero::Bool

    # Whether to add a comment suggesting to ask on the #pkg-registration
    # Julia-Slack channel when AutoMerge is not possible
    point_to_slack::Bool

    # GitHub identity resulting from the use of an authentication token.
    whoami::String

    # List of dependent registries. Typically this would contain
    # "General" when running automerge for a private registry.
    registry_deps::Vector{String}

    # Location of the directory where the package code
    # will be downloaded into. Populated at construction time
    # via `mktempdir`.
    pkg_code_path::String

    # Location of the directory where the package repository
    # is cloned for git operations. Populated at construction time
    # via `mktempdir`.
    pkg_clone_dir::String

    # A list of public Julia registries (repository URLs) which will
    # be checked for UUID collisions in order to mitigate the
    # dependency confusion vulnerability. See the
    # `dependency_confusion.jl` file for details.
    public_registries::Vector{String}

    # whether only read-only actions should be taken
    read_only::Bool

    # Environment variables to pass to the subprocess that does `Pkg.add("Foo")` and `import Foo`
    environment_variables_to_pass::Vector{String}
end

# Constructor that requires all fields (except `pkg_code_path` and `pkg_clone_dir`) as named arguments.
function GitHubAutoMergeData(; kwargs...)
    pkg_code_path = mktempdir()
    pkg_clone_dir = mktempdir()
    kwargs = (; pkg_code_path=pkg_code_path, pkg_clone_dir=pkg_clone_dir, kwargs...)
    fields = fieldnames(GitHubAutoMergeData)
    always_assert(Set(keys(kwargs)) == Set(fields))
    always_assert(kwargs[:authorization] ∈ (:normal, :jll))
    return GitHubAutoMergeData(getindex.(Ref(kwargs), fields)...)
end

struct LocalAutoMergeData
    # Whether the registration refers to a new package or a new version
    # of an existing package.
    registration_type::Union{NewPackage,NewVersion}

    # Name of the package being registered.
    pkg::String

    # Version of the package being registered.
    version::VersionNumber

    # Current commit SHA of the package repository.
    current_pr_head_commit_sha::String

    # Directory of a registry clone that includes the simulated registration.
    registry_head::String

    # Directory of a registry clone that excludes the simulated registration.
    registry_master::String

    # Whether to add a comment suggesting bumping package version to
    # 1.0 if appropriate.
    suggest_onepointzero::Bool

    # List of dependent registries. Typically this would contain
    # "General" when running automerge for a private registry.
    registry_deps::Vector{String}

    # Location of the directory where the package code is located.
    pkg_code_path::String

    # A list of public Julia registries (repository URLs) which will
    # be checked for UUID collisions in order to mitigate the
    # dependency confusion vulnerability.
    public_registries::Vector{String}

    # Environment variables to pass to the subprocess that does `Pkg.add("Foo")` and `import Foo`
    environment_variables_to_pass::Vector{String}
end

Base.@kwdef mutable struct Guideline
    # Short description of the guideline. Only used for logging.
    info::String

    # Documentation for the guideline
    docs::Union{String,Nothing} = info

    # Function that is run in order to determine whether a guideline
    # is met. Input is an instance of `GitHubAutoMergeData` or `LocalAutoMergeData` and output
    # is passed status plus a user facing message explaining the
    # guideline result.
    check::Function

    # Saved result of the `check` function.
    passed::Bool = false

    # Saved output message from the `check` function.
    message::String = "Internal error. A check that was supposed to run never did: $(info)"
end

passed(guideline::Guideline) = guideline.passed
message(guideline::Guideline) = guideline.message
function check!(guideline::Guideline, data::GitHubAutoMergeData)
    return guideline.passed, guideline.message = guideline.check(data)
end
function check!(guideline::Guideline, data::LocalAutoMergeData)
    return guideline.passed, guideline.message = guideline.check(data)
end

struct LocalCheckResult
    pkg::String
    version::VersionNumber
    registration_type::Union{NewPackage,NewVersion}
    commit_sha::String
    overall_pass::Bool
    passed_guidelines::Vector{Guideline}
    failed_guidelines::Vector{Guideline}
    total_guidelines::Int
end

# Single-line show method
function Base.show(io::IO, result::LocalCheckResult)
    status = result.overall_pass ? "✓ PASS" : "✗ FAIL"
    print(io, "LocalCheckResult: $(result.pkg) v$(result.version) ($status)")
end

# Multi-line show method
function Base.show(io::IO, ::MIME"text/plain", result::LocalCheckResult)
    println(io, "="^60)
    println(io, "LOCAL AUTOMERGE CHECK RESULTS")
    println(io, "="^60)
    println(io, "Package: $(result.pkg) v$(result.version)")
    println(io, "Registration type: $(typeof(result.registration_type))")
    status = result.overall_pass ? "✓ PASS" : "✗ FAIL"
    println(io, "Overall result: $status")
    println(io)

    if !isempty(result.passed_guidelines)
        println(io, "✓ Passed guidelines ($(length(result.passed_guidelines))):")
        for guideline in result.passed_guidelines
            println(io, "  • $(guideline.info)")
        end
        println(io)
    end

    if !isempty(result.failed_guidelines)
        println(io, "✗ Failed guidelines ($(length(result.failed_guidelines))):")
        for guideline in result.failed_guidelines
            println(io, "  • $(guideline.info)")
            if !isempty(guideline.message)
                println(io, "    $(guideline.message)")
            end
        end
        println(io)
    end

    print(io, "="^60)
end
