struct NewPackage end
struct NewVersion end

abstract type AutoMergeException <: Exception
end

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

struct GitHubAutoMergeData
    # Handle to the GitHub API. Used to query the PR and update
    # comments and status.
    api::GitHub.GitHubAPI

    # Whether the registry PR refers to a new package or a new version
    # of an existing package.
    registration_type::Union{NewPackage, NewVersion}

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

    # GitHub identity resulting from the use of an authentication token.
    whoami::String

    # List of dependent registries. Typically this would contain
    # "General" when running automerge for a private registry.
    registry_deps::Vector{String}

    # Location of the directory where the package code
    # will be downloaded into. Populated at construction time
    # via `mktempdir`.
    pkg_code_path::String

    # A list of public Julia registries (repository URLs) which will
    # be checked for UUID collisions in order to mitigate the
    # dependency confusion vulnerability. See the
    # `dependency_confusion.jl` file for details.
    public_registries::Vector{String}
end

# Constructor that requires all fields (except `pkg_code_path`) as named arguments.
function GitHubAutoMergeData(; kwargs...)
    pkg_code_path = mktempdir(; cleanup=true)
    kwargs = (; pkg_code_path=pkg_code_path, kwargs...)
    fields = fieldnames(GitHubAutoMergeData)
    always_assert(Set(keys(kwargs)) == Set(fields))
    always_assert(kwargs[:authorization] ∈ (:normal, :jll))
    return GitHubAutoMergeData(getindex.(Ref(kwargs), fields)...)
end

mutable struct Guideline
    # Short description of the guideline. Only used for logging.
    info::String
    # Function that is run in order to determine whether a guideline
    # is met. Input is an instance of `GitHubAutoMergeData` and output
    # is passed status plus a user facing message explaining the
    # guideline result.
    check::Function
    # Saved result of the `check` function.
    passed::Bool
    # Saved output message from the `check` function.
    message::String
end

function Guideline(info::String, check::Function)
    # This initial status and message are overwritten when the check
    # has been run.
    passed = false
    message = "Internal error. A check that was supposed to run never did: $info"
    return Guideline(info, check, passed, message)
end

passed(guideline::Guideline) = guideline.passed
message(guideline::Guideline) = guideline.message
function check!(guideline::Guideline, data::GitHubAutoMergeData)
    return guideline.passed, guideline.message = guideline.check(data)
end
