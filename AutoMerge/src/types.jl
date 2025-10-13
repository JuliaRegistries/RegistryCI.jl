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

Base.@kwdef struct ProjectInfo
    local_path::String
    pkg_name::String
    uuid::UUID
    version::VersionNumber
end

mutable struct GitHubAutoMergeData
    # Handle to the GitHub API. Used to query the PR and update
    # comments and status.
    const api::GitHub.GitHubAPI

    # Whether the registry PR refers to a new package or a new version
    # of an existing package.
    const registration_type::Union{NewPackage,NewVersion}

    # The GitHub pull request data.
    const pr::GitHub.PullRequest

    # Name of the package being registered.
    const pkg::String

    # Version of the package being registered.
    const version::VersionNumber

    # Used for updating CI status.
    const current_pr_head_commit_sha::String

    # The GitHub repo data for the registry.
    const registry::GitHub.Repo

    # GitHub authorization data.
    const auth::GitHub.Authorization

    # Type of authorization for automerge. This can be either:
    # :jll - special jll exceptions are allowed,
    # :normal - normal automerge rules.
    const authorization::Symbol

    # Directory of a registry clone that includes the PR.
    const registry_head::String

    # Directory of a registry clone that excludes the PR.
    const registry_master::String

    # Whether to add a comment suggesting bumping package version to
    # 1.0 if appropriate.
    const suggest_onepointzero::Bool

    # Whether to add a comment suggesting to ask on the #pkg-registration
    # Julia-Slack channel when AutoMerge is not possible
    const point_to_slack::Bool

    # GitHub identity resulting from the use of an authentication token.
    const whoami::String

    # List of dependent registries. Typically this would contain
    # "General" when running automerge for a private registry.
    const registry_deps::Vector{String}

    # Location of the directory where the package code
    # will be downloaded into. Populated at construction time
    # via `mktempdir`.
    const pkg_code_path::String

    # Location of the directory where the package repository
    # is cloned for git operations. Populated at construction time
    # via `mktempdir`.
    const pkg_clone_dir::String

    # A list of public Julia registries (repository URLs) which will
    # be checked for UUID collisions in order to mitigate the
    # dependency confusion vulnerability. See the
    # `dependency_confusion.jl` file for details.
    const public_registries::Vector{String}

    # whether only read-only actions should be taken
    const read_only::Bool

    # Environment variables to pass to the subprocess that does `Pkg.add("Foo")` and `import Foo`
    const environment_variables_to_pass::Vector{String}

    # after the code is downloaded, we parse the Project.toml and populate this
    parsed_project_info::Union{Nothing,ProjectInfo}
end

# Constructor that requires all fields (except `pkg_code_path` and `pkg_clone_dir`) as named arguments.
function GitHubAutoMergeData(; kwargs...)
    pkg_code_path = mktempdir()
    pkg_clone_dir = mktempdir()
    parsed_project_info = nothing
    kwargs = (; pkg_code_path, pkg_clone_dir, parsed_project_info, kwargs...)
    fields = fieldnames(GitHubAutoMergeData)
    always_assert(Set(keys(kwargs)) == Set(fields))
    always_assert(kwargs[:authorization] ∈ (:normal, :jll))
    return GitHubAutoMergeData(getindex.(Ref(kwargs), fields)...)
end

Base.@kwdef mutable struct Guideline
    # Short description of the guideline. Only used for logging.
    info::String

    # Documentation for the guideline
    docs::Union{String,Nothing} = info

    # Function that is run in order to determine whether a guideline
    # is met. Input is an instance of `GitHubAutoMergeData` and output
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
