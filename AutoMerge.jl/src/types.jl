using Dates: Day, Minute

struct AlwaysAssertionError <: Exception
    msg::String
end


"""
    AutoMergeConfiguration

Configuration struct for AutoMerge.

```julia
AutoMergeConfiguration(; kwargs...)
```

!!! note
    New keyword arguments with defaults may be added to this struct in _non-breaking_ releases of AutoMerge.jl. Default values and keyword argument names will not be removed or changed in non-breaking releases, however.

# Required keyword arguments

- `merge_new_packages::Bool`: should AutoMerge merge registration PRs for new packages
- `merge_new_versions::Bool`: should AutoMerge merge registration PRs for new versions of packages
- `new_package_waiting_period::Dates.Period`: new package waiting period, e.g `Day(3)`.
- `new_jll_package_waiting_period::Dates.Period`: new JLL package waiting period, e.g `Minute(20)`.
- `new_version_waiting_period::Dates.Period`: new package version waiting period, e.g `Minute(10)`.
- `new_jll_version_waiting_period::Dates.Period`: new JLL package version waiting period, e.g `Minute(10)`.
- `registry::String`: the registry name you want to run AutoMerge on.
- `authorized_authors::Vector{String}`: list of who can submit registration, e.g `String["JuliaRegistrator"]`.
- `authorized_authors_special_jll_exceptions::Vector{String}`: a list of users who can submit JLL packages (which have strict rules about allowed dependencies and are subject to `new_jll_*_waiting_period`s instead of `new_*_waiting_period`s).

# Keyword arguments with default values

- `tagbot_enabled::Bool = false`: if tagbot is enabled.
- `additional_statuses::AbstractVector{<:AbstractString} = String[]`: list of additional commit statuses that must pass before AutoMerge will merge a PR
- `additional_check_runs::AbstractVector{<:AbstractString} = String[]`: list of additional check runs that must pass before AutoMerge will merge a PR
- `error_exit_if_automerge_not_applicable::Bool = false`: if `false`, AutoMerge will not error on PRs made by non-AutoMerge-authorized users
- `master_branch::String = "master"`: name of `master_branch`, e.g you may want to specify this to `"main"` for new GitHub repositories.
- `master_branch_is_default_branch::Bool = true`: if `master_branch` specified above is the default branch.
- `suggest_onepointzero::Bool = true`: should the AutoMerge comment include a suggestion to tag a 1.0 release for v0.x.y packages.
- `point_to_slack::Bool = false`: should the AutoMerge comment recommend sending a message to the `#pkg-registration` Julia-Slack channel when auto-merging is not possible.
- `registry_deps::Vector{<:AbstractString} = String[]`: list of registry dependencies, e.g your packages may depend on `General`.
- `api_url::String = "https://api.github.com"`: the registry host API URL.
- `check_license::Bool = false`: check package has a valid license.
- `check_breaking_explanation::Bool = false`: Check whether the PR has release notes (collected via Registrator.jl) with a breaking change explanation.
- `public_registries::Vector{<:AbstractString} = String[]`: If a new package registration has a UUID that matches
  that of a package already registered in one of these registries supplied here
  (and has either a different name or different URL) then an error will be thrown.
  This to prevent AutoMerge from being used for "dependency confusion"
  attacks on those registries.
- `read_only::Bool = false`: run in read only mode.
- `environment_variables_to_pass::Vector{<:AbstractString} = String[]`: Environment variables to pass to the subprocess that does `Pkg.add("Foo")` and `import Foo`
"""
Base.@kwdef struct AutoMergeConfiguration
    merge_new_packages::Bool
    merge_new_versions::Bool
    new_package_waiting_period::Dates.Period
    new_jll_package_waiting_period::Dates.Period
    new_version_waiting_period::Dates.Period
    new_jll_version_waiting_period::Dates.Period
    registry::String
    tagbot_enabled::Bool = false
    authorized_authors::Vector{String}
    authorized_authors_special_jll_exceptions::Vector{String}
    additional_statuses::AbstractVector{<:AbstractString} = String[]
    additional_check_runs::AbstractVector{<:AbstractString} = String[]
    error_exit_if_automerge_not_applicable::Bool = false
    master_branch::String = "master"
    master_branch_is_default_branch::Bool = true
    suggest_onepointzero::Bool = true
    point_to_slack::Bool = false
    registry_deps::Vector{<:AbstractString} = String[]
    api_url::String = "https://api.github.com"
    check_license::Bool = false
    check_breaking_explanation::Bool = false
    public_registries::Vector{<:AbstractString} = String[]
    read_only::Bool = false
    environment_variables_to_pass::Vector{<:AbstractString} = String[]
end

function Base.show(io::IO, ::MIME"text/plain", obj::AutoMergeConfiguration)
    print(io, AutoMergeConfiguration, " with:")
    for k in propertynames(obj)
        print(io, "\n  ", k, ": `", repr(getproperty(obj, k)), "`")
    end
end

Base.show(io::IO, ::AutoMergeConfiguration) = print(io, AutoMergeConfiguration, "(…)")


const GENERAL_AUTOMERGE_CONFIG = AutoMergeConfiguration(
    merge_new_packages = true,
    merge_new_versions = true,
    new_package_waiting_period = Day(3),
    new_jll_package_waiting_period = Minute(20),
    new_version_waiting_period = Minute(10),
    new_jll_version_waiting_period = Minute(10),
    registry = "JuliaRegistries/General",
    tagbot_enabled = true,
    authorized_authors = String["JuliaRegistrator"],
    authorized_authors_special_jll_exceptions = String["jlbuild"],
    suggest_onepointzero = false,
    additional_statuses = String[],
    additional_check_runs = String[],
    check_license = true,
    public_registries = String[
        "https://github.com/HolyLab/HolyLabRegistry",
        "https://github.com/cossio/CossioJuliaRegistry"
    ],
    point_to_slack = true,
    check_breaking_explanation = true,
)


@doc """
    AutoMerge.GENERAL_AUTOMERGE_CONFIG

This is the [`AutoMergeConfiguration`](@ref) object intended for use by the
[General registry](https://github.com/JuliaRegistries/General).
General uses the `AutoMerge.GENERAL_AUTOMERGE_CONFIG` from the latest released version of
AutoMerge.jl (once its manifest has been updated).

!!! warning
    The values of the fields chosen here may change in non-breaking releases
    of AutoMerge.jl at the discretion of the maintainers of the General registry,
    in order to configure the registry for the current needs of the community.

Here are the settings chosen for General in this version of AutoMerge.jl:
```julia
julia> AutoMerge.GENERAL_AUTOMERGE_CONFIG
$(sprint(show, MIME"text/plain"(), GENERAL_AUTOMERGE_CONFIG))

```
""" GENERAL_AUTOMERGE_CONFIG
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

# Constructor that requires all fields (except `pkg_code_path`) as named arguments.
function GitHubAutoMergeData(; kwargs...)
    pkg_code_path = mktempdir(; cleanup=true)
    kwargs = (; pkg_code_path=pkg_code_path, kwargs...)
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
