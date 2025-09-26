using Dates: Day, Minute

struct AlwaysAssertionError <: Exception
    msg::String
end

abstract type AbstractConfiguration end

"""
    RegistryConfiguration

Shared configuration fields used by both PR checking and merging functionality.

```julia
RegistryConfiguration(; kwargs...)
```

# Required keyword arguments

- `registry::String`: the registry name you want to run AutoMerge on.
- `authorized_authors::Vector{String}`: list of who can submit registration, e.g `String["JuliaRegistrator"]`.
- `authorized_authors_special_jll_exceptions::Vector{String}`: a list of users who can submit JLL packages.
- `new_package_waiting_period::Dates.Period`: new package waiting period, e.g `Day(3)`.
- `new_jll_package_waiting_period::Dates.Period`: new JLL package waiting period, e.g `Minute(20)`.
- `new_version_waiting_period::Dates.Period`: new package version waiting period, e.g `Minute(10)`.
- `new_jll_version_waiting_period::Dates.Period`: new JLL package version waiting period, e.g `Minute(10)`.

# Keyword arguments with default values

- `master_branch::String = "master"`: name of `master_branch`
- `error_exit_if_automerge_not_applicable::Bool = false`: if `false`, AutoMerge will not error on build type mismatches
- `api_url::String = "https://api.github.com"`: the registry host API URL.
- `read_only::Bool = false`: run in read only mode.
"""
Base.@kwdef struct RegistryConfiguration <: AbstractConfiguration
    registry::String
    authorized_authors::Vector{String}
    authorized_authors_special_jll_exceptions::Vector{String}
    new_package_waiting_period::Dates.Period
    new_jll_package_waiting_period::Dates.Period
    new_version_waiting_period::Dates.Period
    new_jll_version_waiting_period::Dates.Period
    master_branch::String = "master"
    error_exit_if_automerge_not_applicable::Bool = false
    api_url::String = "https://api.github.com"
    read_only::Bool = false
end

"""
    CheckPRConfiguration

Configuration struct for checking PR registration validity (security-isolated functionality).

```julia
CheckPRConfiguration(; kwargs...)
```

# Keyword arguments with default values

- `master_branch_is_default_branch::Bool = true`: if `master_branch` specified above is the default branch.
- `suggest_onepointzero::Bool = true`: should the AutoMerge comment include a suggestion to tag a 1.0 release for v0.x.y packages.
- `point_to_slack::Bool = false`: should the AutoMerge comment recommend sending a message to the `#pkg-registration` Julia-Slack channel.
- `registry_deps::Vector{<:AbstractString} = String[]`: list of registry dependencies.
- `check_license::Bool = false`: check package has a valid license.
- `check_breaking_explanation::Bool = false`: Check whether the PR has release notes with a breaking change explanation.
- `public_registries::Vector{<:AbstractString} = String[]`: Public registries to check for UUID collisions to prevent dependency confusion attacks.
- `environment_variables_to_pass::Vector{<:AbstractString} = String[]`: Environment variables to pass to package testing subprocess.
"""
Base.@kwdef struct CheckPRConfiguration <: AbstractConfiguration
    master_branch_is_default_branch::Bool = true
    suggest_onepointzero::Bool = true
    point_to_slack::Bool = false
    registry_deps::Vector{<:AbstractString} = String[]
    check_license::Bool = false
    check_breaking_explanation::Bool = false
    public_registries::Vector{<:AbstractString} = String[]
    environment_variables_to_pass::Vector{<:AbstractString} = String[]
end

"""
    MergePRsConfiguration

Configuration struct for merging approved PRs (requires merge permissions).

```julia
MergePRsConfiguration(; kwargs...)
```

# Keyword arguments with default values

- `merge_new_packages::Bool = true`: should AutoMerge merge registration PRs for new packages
- `merge_new_versions::Bool = true`: should AutoMerge merge registration PRs for new versions of packages
- `additional_statuses::AbstractVector{<:AbstractString} = String[]`: list of additional commit statuses that must pass before AutoMerge will merge a PR
- `additional_check_runs::AbstractVector{<:AbstractString} = String[]`: list of additional check runs that must pass before AutoMerge will merge a PR
"""
Base.@kwdef struct MergePRsConfiguration <: AbstractConfiguration
    merge_new_packages::Bool = true
    merge_new_versions::Bool = true
    additional_statuses::AbstractVector{<:AbstractString} = String[]
    additional_check_runs::AbstractVector{<:AbstractString} = String[]
end

function Base.show(io::IO, ::MIME"text/plain", obj::AbstractConfiguration)
    print(io, typeof(obj), " with:")
    for k in propertynames(obj)
        print(io, "\n  ", k, ": `", repr(getproperty(obj, k)), "`")
    end
end

Base.show(io::IO, obj::AbstractConfiguration) = print(io, typeof(obj), "(…)")

function update_config(config::Config; config_overrides...) where {Config <: AbstractConfiguration}
    return Config(; ((k => getproperty(config, k)) for k in propertynames(config))..., config_overrides...)
end

const GENERAL_REGISTRY_CONFIG = RegistryConfiguration(
    registry = "JuliaRegistries/General",
    authorized_authors = String["JuliaRegistrator"],
    authorized_authors_special_jll_exceptions = String["jlbuild"],
    new_package_waiting_period = Day(3),
    new_jll_package_waiting_period = Minute(20),
    new_version_waiting_period = Minute(10),
    new_jll_version_waiting_period = Minute(10),
    master_branch = "master",
    error_exit_if_automerge_not_applicable = false,
    api_url = "https://api.github.com",
    read_only = false,
)

const GENERAL_CHECK_PR_CONFIG = CheckPRConfiguration(
    master_branch_is_default_branch = true,
    suggest_onepointzero = false,
    point_to_slack = true,
    registry_deps = String[],
    check_license = true,
    check_breaking_explanation = true,
    public_registries = String[
        "https://github.com/HolyLab/HolyLabRegistry",
        "https://github.com/cossio/CossioJuliaRegistry"
    ],
    environment_variables_to_pass = String[],
)

const GENERAL_MERGE_PRS_CONFIG = MergePRsConfiguration(
    merge_new_packages = true,
    merge_new_versions = true,
    additional_statuses = String[],
    additional_check_runs = String[],
)


@doc """
    AutoMerge.GENERAL_REGISTRY_CONFIG

This is the [`AutoMerge.RegistryConfiguration`](@ref) object containing shared configuration
for the [General registry](https://github.com/JuliaRegistries/General). This configuration
is used by both PR checking and merging functionality.

!!! warning
    The values of the fields chosen here may change in non-breaking releases
    of AutoMerge.jl at the discretion of the maintainers of the General registry.

Here are the settings chosen for General in this version of AutoMerge.jl:
```julia
julia> AutoMerge.GENERAL_REGISTRY_CONFIG
$(sprint(show, MIME"text/plain"(), GENERAL_REGISTRY_CONFIG))

```
""" GENERAL_REGISTRY_CONFIG

@doc """
    AutoMerge.GENERAL_CHECK_PR_CONFIG

This is the [`AutoMerge.CheckPRConfiguration`](@ref) object intended for use by the
[General registry](https://github.com/JuliaRegistries/General) for checking PR validity.
General uses these configurations from the latest released version of AutoMerge.jl.

!!! warning
    The values of the fields chosen here may change in non-breaking releases
    of AutoMerge.jl at the discretion of the maintainers of the General registry.

Here are the settings chosen for General in this version of AutoMerge.jl:
```julia
julia> AutoMerge.GENERAL_CHECK_PR_CONFIG
$(sprint(show, MIME"text/plain"(), GENERAL_CHECK_PR_CONFIG))

```
""" GENERAL_CHECK_PR_CONFIG

@doc """
    AutoMerge.GENERAL_MERGE_PRS_CONFIG

This is the [`AutoMerge.MergePRsConfiguration`](@ref) object intended for use by the
[General registry](https://github.com/JuliaRegistries/General) for merging approved PRs.
General uses these configurations from the latest released version of AutoMerge.jl.

!!! warning
    The values of the fields chosen here may change in non-breaking releases
    of AutoMerge.jl at the discretion of the maintainers of the General registry.

Here are the settings chosen for General in this version of AutoMerge.jl:
```julia
julia> AutoMerge.GENERAL_MERGE_PRS_CONFIG
$(sprint(show, MIME"text/plain"(), GENERAL_MERGE_PRS_CONFIG))

```
""" GENERAL_MERGE_PRS_CONFIG
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
