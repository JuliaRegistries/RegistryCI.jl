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

!!! note
    New keyword arguments with defaults may be added to this struct in _non-breaking_ releases of AutoMerge.jl. Default values and keyword argument names will not be removed or changed in non-breaking releases, however.

## Required keyword arguments (& fields)

- `registry::String`: the registry name you want to run AutoMerge on.
- `authorized_authors::Vector{String}`: list of who can submit registration, e.g `String["JuliaRegistrator"]`.
- `authorized_authors_special_jll_exceptions::Vector{String}`: a list of users who can submit JLL packages (which have strict rules about allowed dependencies and are subject to `new_jll_*_waiting_minutes`s instead of `new_*_waiting_minutes`s).
- `new_package_waiting_minutes::Dates.Minute`: new package waiting period in minutes.
- `new_jll_package_waiting_minutes::Dates.Minute`: new JLL package waiting period in minutes.
- `new_version_waiting_minutes::Dates.Minute`: new package version waiting period in minutes.
- `new_jll_version_waiting_minutes::Dates.Minute`: new JLL package version waiting period in minutes.

## Keyword arguments (& fields) with default values

- `master_branch::String = "master"`: name of `master_branch`, e.g you may want to specify this to `"main"` for new GitHub repositories.
- `error_exit_if_automerge_not_applicable::Bool = false`: if `false`, AutoMerge will not error on PRs made by non-AutoMerge-authorized users
- `api_url::String = "https://api.github.com"`: the registry host API URL.
- `read_only::Bool = false`: run in read only mode.
"""
Base.@kwdef struct RegistryConfiguration <: AbstractConfiguration
    registry::String
    authorized_authors::Vector{String}
    authorized_authors_special_jll_exceptions::Vector{String}
    new_package_waiting_minutes::Dates.Minute
    new_jll_package_waiting_minutes::Dates.Minute
    new_version_waiting_minutes::Dates.Minute
    new_jll_version_waiting_minutes::Dates.Minute
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

!!! note
    New keyword arguments with defaults may be added to this struct in _non-breaking_ releases of AutoMerge.jl. Default values and keyword argument names will not be removed or changed in non-breaking releases, however.

## Keyword arguments (& fields) with default values

- `master_branch_is_default_branch::Bool = true`: if `master_branch` specified above is the default branch.
- `suggest_onepointzero::Bool = true`: should the AutoMerge comment include a suggestion to tag a 1.0 release for v0.x.y packages.
- `point_to_slack::Bool = false`: should the AutoMerge comment recommend sending a message to the `#pkg-registration` Julia-Slack channel when auto-merging is not possible.
- `registry_deps::Vector{String} = String[]`: list of registry dependencies, e.g your packages may depend on `General`.
- `check_license::Bool = false`: check package has a valid license.
- `check_breaking_explanation::Bool = false`: Check whether the PR has release notes (collected via Registrator.jl) with a breaking change explanation.
- `public_registries::Vector{String} = String[]`: If a new package registration has a UUID that matches
  that of a package already registered in one of these registries supplied here
  (and has either a different name or different URL) then an error will be thrown.
  This to prevent AutoMerge from being used for "dependency confusion"
  attacks on those registries.
- `environment_variables_to_pass::Vector{String} = String[]`: Environment variables to pass to the subprocess that does `Pkg.add("Foo")` and `import Foo`
- `commit_status_token_name::String = "AUTOMERGE_GITHUB_TOKEN"`: Name of the environment variable containing the GitHub token used for PR validation. The token stored in this environment variable needs `repo:status` permission to set commit statuses and read access to PRs, but does not need write access to the repository.
"""
Base.@kwdef struct CheckPRConfiguration <: AbstractConfiguration
    master_branch_is_default_branch::Bool = true
    suggest_onepointzero::Bool = true
    point_to_slack::Bool = false
    registry_deps::Vector{String} = String[]
    check_license::Bool = false
    check_breaking_explanation::Bool = false
    public_registries::Vector{String} = String[]
    environment_variables_to_pass::Vector{String} = String[]
    commit_status_token_name::String = "AUTOMERGE_GITHUB_TOKEN"
end

"""
    MergePRsConfiguration

Configuration struct for merging approved PRs (requires merge permissions).

```julia
MergePRsConfiguration(; kwargs...)
```

!!! note
    New keyword arguments with defaults may be added to this struct in _non-breaking_ releases of AutoMerge.jl. Default values and keyword argument names will not be removed or changed in non-breaking releases, however.

## Keyword arguments (& fields) with default values

- `merge_new_packages::Bool = true`: should AutoMerge merge registration PRs for new packages
- `merge_new_versions::Bool = true`: should AutoMerge merge registration PRs for new versions of packages
- `additional_statuses::Vector{String} = String[]`: list of additional commit statuses that must pass before AutoMerge will merge a PR
- `additional_check_runs::Vector{String} = String[]`: list of additional check runs that must pass before AutoMerge will merge a PR
- `merge_token_name::String = "AUTOMERGE_MERGE_TOKEN"`: Name of the environment variable containing the GitHub token used for PR merging. The token stored in this environment variable needs write access to the repository to merge PRs.
"""
Base.@kwdef struct MergePRsConfiguration <: AbstractConfiguration
    merge_new_packages::Bool = true
    merge_new_versions::Bool = true
    additional_statuses::Vector{String} = String[]
    additional_check_runs::Vector{String} = String[]
    merge_token_name::String = "AUTOMERGE_MERGE_TOKEN"
end


"""
    AutoMergeConfiguration

Combined configuration object containing registry, PR checking, and PR merging settings.

!!! note
    New keyword arguments with defaults may be added to this struct in _non-breaking_ releases of AutoMerge.jl. Default values and keyword argument names will not be removed or changed in non-breaking releases, however.

## Keyword arguments & fields

- `registry_config::RegistryConfiguration`: Shared registry settings
- `check_pr_config::CheckPRConfiguration`: PR validation settings
- `merge_prs_config::MergePRsConfiguration`: PR merging settings
"""
Base.@kwdef struct AutoMergeConfiguration <: AbstractConfiguration
    registry_config::RegistryConfiguration
    check_pr_config::CheckPRConfiguration
    merge_prs_config::MergePRsConfiguration
end

_serialize(k, x::Any) = x
function _serialize(k, x::Dates.Minute)
    if !endswith(string(k), "_minutes")
        error("field $k does not end with `_minutes` but value $x has type `Dates.Minute`, so cannot be serialized unambiguously.")
    end
    return Dates.value(x)
end
_serialize(k, x::AbstractConfiguration) = to_dict(x)

function to_dict(config::AbstractConfiguration)
    Dict{String,Any}(string(k) => _serialize(k, getproperty(config, k)) for k in propertynames(config))
end

function _deserialize(k::AbstractString, x::Any)
    if endswith(k, "_minutes")
        val = Dates.Minute(x)
        if val < Dates.Minute(0)
            error("Configuration field '$k' must be non-negative, got $(Dates.value(val)) minutes. Please check your configuration file.")
        end
        return val
    elseif k == "registry_config"
        return from_dict(RegistryConfiguration, x)
    elseif k == "check_pr_config"
        return from_dict(CheckPRConfiguration, x)
    elseif k == "merge_prs_config"
        return from_dict(MergePRsConfiguration, x)
    else
        # Validate Vector{String} arrays
        if x isa Vector
            if !all(elt -> elt isa String, x)
                error("Configuration field '$k' must be a Vector{String}, but contains non-string elements. Please check your configuration file.")
            end
            return Vector{String}(x)
        end
        return x
    end
end
function from_dict(::Type{Config}, dict::AbstractDict{String}) where {Config <: AbstractConfiguration}
    # Check for unknown keys and warn (forward compatibility)
    expected_keys = Set(String(k) for k in fieldnames(Config))
    dict_keys = Set(keys(dict))
    unknown_keys = setdiff(dict_keys, expected_keys)
    if !isempty(unknown_keys)
        @warn "Configuration contains unknown keys: $(join(unknown_keys, ", ")). This may indicate the configuration was created with a newer version of AutoMerge. These keys will be ignored."
    end

    Config(; (Symbol(k) => _deserialize(k, dict[k]) for k in keys(dict) if k in expected_keys)...)
end

"""
    read_config(path) -> AutoMergeConfiguration

Read an AutoMerge configuration from a TOML file.
"""
function read_config(path)
    return from_dict(AutoMergeConfiguration, TOML.parsefile(path))
end

"""
    write_config(path, config::AbstractConfiguration) -> Nothing

Write an AutoMerge configuration to a TOML file. Automatically handles serialization of `Dates.Minute` fields to integer values.
"""
function write_config(path, config::AbstractConfiguration)
    open(path; write=true) do io
       TOML.print(io, AutoMerge.to_dict(config))
    end
end

function _full_show(io::IO, obj::Any; indent=0)
    # one-liner, so don't need indent
    print(io, " `")
    show(io, obj)
    print(io, "`")
end

function _full_show(io::IO, obj::AbstractConfiguration; indent=0)
    indent == 0 && print(io, " "^indent, typeof(obj), " with:")
    for k in propertynames(obj)
        print(io, "\n  ", " "^indent, k, ":")
        _full_show(io, getproperty(obj, k); indent = indent+2)
    end
end
Base.show(io::IO, ::MIME"text/plain", obj::AbstractConfiguration) = _full_show(io, obj)
Base.show(io::IO, obj::AbstractConfiguration) = print(io, typeof(obj), "(…)")

function general_registry_config()
    p = pkgdir(AutoMerge)
    if p === nothing # make JET happy
        @error "AutoMerge was not imported from a package, cannot locate package directory"
        return nothing
    end
    return read_config(joinpath(p, "configs", "General.AutoMerge.toml"))
end

@doc """
    AutoMerge.general_registry_config()

This is the [`AutoMerge.AutoMergeConfiguration`](@ref) object containing shared configuration
for the [General registry](https://github.com/JuliaRegistries/General). This configuration
is used by both PR checking and merging functionality.

!!! warning
    The values of the fields chosen here may change in non-breaking releases
    of AutoMerge.jl at the discretion of the maintainers of the General registry.

Here are the settings chosen for General in this version of AutoMerge.jl:
```julia
julia> AutoMerge.general_registry_config()
$(sprint(show, MIME"text/plain"(), general_registry_config()))

```
""" general_registry_config

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
