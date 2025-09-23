"""
    run([env, cicfg::CIService]; kwargs...)

Run the `AutoMerge` service.

# Arguments

- `env`: an `AbstractDictionary` used to read environmental variables from.
   Defaults to `ENV` but a plain `Dict` can be passed to mimic an alternate environment.
- `ciccfg`: Configuration struct describing the continuous integration (CI) environment in which AutoMerge is being run.

# Keyword Arguments

- `merge_new_packages`: should AutoMerge merge registration PRs for new packages
- `merge_new_versions`: should AutoMerge merge registration PRs for new versions of packages
- `new_package_waiting_period`: new package waiting period, e.g `Day(3)`.
- `new_jll_package_waiting_period`: new JLL package waiting period, e.g `Minute(20)`.
- `new_version_waiting_period`: new package version waiting period, e.g `Minute(10)`.
- `new_jll_version_waiting_period`: new JLL package version waiting period, e.g `Minute(10)`.
- `registry`: the registry name you want to run AutoMerge on.
- `tagbot_enabled`: if tagbot is enabled.
- `authorized_authors`: list of who can submit registration, e.g `String["JuliaRegistrator"]`.
- `authorized_authors_special_jll_exceptions`: a list of users who can submit JLL packages (which have strict rules about allowed dependencies and are subject to `new_jll_*_waiting_period`s instead of `new_*_waiting_period`s).
- `additional_statuses`: list of additional commit statuses that must pass before AutoMerge will merge a PR
- `additional_check_runs`: list of additional check runs that must pass before AutoMerge will merge a PR
- `error_exit_if_automerge_not_applicable`: if `false`, AutoMerge will not error on PRs made by non-AutoMerge-authorized users
- `master_branch`: name of `master_branch`, e.g you may want to specify this to `"main"` for new GitHub repositories.
- `master_branch_is_default_branch`: if `master_branch` specified above is the default branch.
- `suggest_onepointzero`: should the AutoMerge comment include a suggestion to tag a 1.0 release for v0.x.y packages.
- `point_to_slack`: should the AutoMerge comment recommend sending a message to the `#pkg-registration` Julia-Slack channel when auto-merging is not possible.
- `registry_deps`: list of registry dependencies, e.g your packages may depend on `General`.
- `api_url`: the registry host API URL, default is `"https://api.github.com"`.
- `check_license`: check package has a valid license, default is `false`.
- `check_breaking_explanation`: Check whether the PR has release notes (collected via Registrator.jl) with a breaking change explanation, default is `false`.
- `public_registries`: If a new package registration has a UUID that matches
   that of a package already registered in one of these registries supplied here
   (and has either a different name or different URL) then an error will be thrown.
   This to prevent AutoMerge from being used for "dependency confusion"
   attacks on those registries.
- `read_only`: run in read only mode, default is `false`.

# Example

Here is an example of how `General` registry is configured

```julia
using AutoMerge
using Dates

AutoMerge.run(
    merge_new_packages = ENV["MERGE_NEW_PACKAGES"] == "true",
    merge_new_versions = ENV["MERGE_NEW_VERSIONS"] == "true",
    new_package_waiting_period = Day(3),
    new_jll_package_waiting_period = Minute(20),
    new_version_waiting_period = Minute(10),
    new_jll_version_waiting_period = Minute(10),
    registry = "JuliaLang/General",
    tagbot_enabled = true,
    authorized_authors = String["JuliaRegistrator"],
    authorized_authors_special_jll_exceptions = String["jlbuild"],
    suggest_onepointzero = false,
    point_to_slack = false,
    additional_statuses = String[],
    additional_check_runs = String[],
    check_license = true,
    check_breaking_explanation = true,
    public_registries = String["https://github.com/HolyLab/HolyLabRegistry"],
)
```
"""
function run(;
    env=ENV,
    cicfg::CIService=auto_detect_ci_service(; env=env),
    merge_new_packages::Bool,
    merge_new_versions::Bool,
    new_package_waiting_period,
    new_jll_package_waiting_period,
    new_version_waiting_period,
    new_jll_version_waiting_period,
    registry::String,
    #
    tagbot_enabled::Bool=false,
    #
    authorized_authors::Vector{String},
    authorized_authors_special_jll_exceptions::Vector{String},
    #
    additional_statuses::AbstractVector{<:AbstractString}=String[],
    additional_check_runs::AbstractVector{<:AbstractString}=String[],
    #
    error_exit_if_automerge_not_applicable::Bool=false,
    #
    master_branch::String="master",
    master_branch_is_default_branch::Bool=true,
    suggest_onepointzero::Bool=true,
    point_to_slack::Bool=false,
    #
    registry_deps::Vector{<:AbstractString}=String[],
    api_url::String="https://api.github.com",
    check_license::Bool=false,
    check_breaking_explanation::Bool=false,
    # A list of public Julia registries (repository URLs)
    # which will be checked for UUID collisions in order to
    # mitigate the dependency confusion vulnerability. See
    # the `dependency_confusion.jl` file for details.
    public_registries::Vector{<:AbstractString}=String[],
    read_only::Bool=false,
    environment_variables_to_pass::Vector{<:AbstractString}=String[],
)::Nothing
    all_statuses = deepcopy(additional_statuses)
    all_check_runs = deepcopy(additional_check_runs)
    push!(all_statuses, "automerge/decision")
    unique!(all_statuses)
    unique!(all_check_runs)
    api = GitHub.GitHubWebAPI(HTTP.URI(api_url))

    registry_head = directory_of_cloned_registry(cicfg; env=env)

    # Figure out what type of build this is
    run_pr_build = conditions_met_for_pr_build(cicfg; env=env, master_branch=master_branch)
    run_merge_build = conditions_met_for_merge_build(
        cicfg; env=env, master_branch=master_branch
    )

    if !(run_pr_build || run_merge_build)
        throw_not_automerge_applicable(
            AutoMergeWrongBuildType,
            "Build not determined to be either a PR build or a merge build. Exiting.";
            error_exit_if_automerge_not_applicable=error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    # Authentication
    key = if run_pr_build || !tagbot_enabled
        "AUTOMERGE_GITHUB_TOKEN"
    else
        "AUTOMERGE_TAGBOT_TOKEN"
    end
    auth = my_retry(() -> GitHub.authenticate(api, env[key]))
    whoami = my_retry(() -> username(api, cicfg; auth=auth))
    @info("Authenticated to GitHub as \"$(whoami)\"")
    registry_repo = my_retry(() -> GitHub.repo(api, registry; auth=auth))

    if run_pr_build
        pr_number = pull_request_number(cicfg; env=env)
        pr_head_commit_sha = current_pr_head_commit_sha(cicfg; env=env)
        pull_request_build(
            api,
            pr_number,
            pr_head_commit_sha,
            registry_repo,
            registry_head;
            auth=auth,
            authorized_authors=authorized_authors,
            authorized_authors_special_jll_exceptions=authorized_authors_special_jll_exceptions,
            error_exit_if_automerge_not_applicable=error_exit_if_automerge_not_applicable,
            master_branch=master_branch,
            master_branch_is_default_branch=master_branch_is_default_branch,
            suggest_onepointzero=suggest_onepointzero,
            point_to_slack=point_to_slack,
            whoami=whoami,
            registry_deps=registry_deps,
            check_license=check_license,
            check_breaking_explanation=check_breaking_explanation,
            public_registries=public_registries,
            read_only=read_only,
            environment_variables_to_pass=environment_variables_to_pass,
            new_package_waiting_period=new_package_waiting_period,
        )
    else
        always_assert(run_merge_build)
        cron_or_api_build(
            api,
            registry_repo;
            auth=auth,
            authorized_authors=authorized_authors,
            authorized_authors_special_jll_exceptions=authorized_authors_special_jll_exceptions,
            merge_new_packages=merge_new_packages,
            merge_new_versions=merge_new_versions,
            new_package_waiting_period=new_package_waiting_period,
            new_jll_package_waiting_period=new_jll_package_waiting_period,
            new_version_waiting_period=new_version_waiting_period,
            new_jll_version_waiting_period=new_jll_version_waiting_period,
            whoami=whoami,
            all_statuses=all_statuses,
            all_check_runs=all_check_runs,
            read_only=read_only,
        )
    end
    return nothing
end

"""
    local_check(package_path, registry_path; kwargs...) -> LocalCheckResult

Check if a local package would pass AutoMerge guidelines if registered.

This function simulates what would happen if the package at `package_path` were
registered in the registry at `registry_path`, and runs the same guidelines
that AutoMerge would check in a real registration PR.

# Arguments
- `package_path::String`: Path to the package directory (must contain Project.toml)
- `registry_path::String`: Path to the target registry directory

# Keyword Arguments
- `pkg::Union{String, Nothing} = nothing`: Package name (auto-detected from Project.toml if not provided)
- `version::Union{VersionNumber, Nothing} = nothing`: Package version (auto-detected from Project.toml if not provided)
- `registration_type::Union{RegistrationType, Nothing} = nothing`: Registration type (auto-detected if not provided)
- `registry_deps::Vector{String} = String[]`: List of registry dependencies
- `check_license::Bool = false`: Whether to check for valid license
- `suggest_onepointzero::Bool = true`: Whether to suggest version 1.0
- `public_registries::Vector{String} = String[]`: Public registries to check for UUID conflicts
- `environment_variables_to_pass::Vector{String} = String[]`: Environment variables to pass to subprocesses

# Returns
- `LocalCheckResult`: Struct containing all check results with custom show methods for display

# Examples

```julia
# Check if MyPackage would pass AutoMerge guidelines
result = AutoMerge.local_check("/path/to/MyPackage", "/path/to/General")

# Check with license validation enabled
result = AutoMerge.local_check("/path/to/MyPackage", "/path/to/General"; check_license=true)

# Access results programmatically
if result.overall_pass
    println("Package \$(result.pkg) passed all guidelines!")
else
    println("Failed guidelines: ", [g.info for g in result.failed_guidelines])
end
```
"""
function local_check(
    package_path::String,
    registry_path::String;
    # Auto-detected parameters
    pkg::Union{String, Nothing} = nothing,
    version::Union{VersionNumber, Nothing} = nothing,
    registration_type::Union{Union{NewPackage,NewVersion}, Nothing} = nothing,

    # Registry settings
    registry_deps::Vector{String} = String[],

    # Check settings
    check_license::Bool = false,
    suggest_onepointzero::Bool = true,

    # Advanced settings
    public_registries::Vector{String} = String[],
    environment_variables_to_pass::Vector{String} = String[],
)
    # Validate input paths
    if !isdir(package_path)
        throw(ArgumentError("Package path does not exist: $package_path"))
    end
    if !isdir(registry_path)
        throw(ArgumentError("Registry path does not exist: $registry_path"))
    end

    # Auto-detect package information
    detected_pkg, detected_version, uuid = detect_package_info(package_path)
    pkg = something(pkg, detected_pkg)
    version = something(version, detected_version)

    # Get git information
    commit_sha, tree_hash = get_current_commit_info(package_path)

    # Auto-detect registration type
    registration_type = something(registration_type, determine_registration_type(pkg, registry_path))

    # Create temporary registries
    registry_master = mktempdir(; cleanup=true)
    cp(registry_path, registry_master; force=true)

    registry_head = create_simulated_registry_with_package(
        package_path, registry_path, pkg, version, uuid, tree_hash
    )

    # Create LocalAutoMergeData
    data = LocalAutoMergeData(
        registration_type,
        pkg,
        version,
        commit_sha,
        registry_head,
        registry_master,
        suggest_onepointzero,
        registry_deps,
        package_path,  # pkg_code_path points directly to the local package
        public_registries,
        environment_variables_to_pass,
    )

    # Run guidelines (subset for Phase 1)
    guidelines = _get_local_guidelines(registration_type; check_license=check_license)

    checked_guidelines = Guideline[]
    for (guideline, applicable) in guidelines
        if !applicable
            continue
        end

        try
            check!(guideline, data)
            push!(checked_guidelines, guideline)
        catch e
            # Create a failed guideline for this error
            failed_guideline = Guideline(;
                info=guideline.info,
                docs=guideline.docs,
                check=_ -> (false, "Error during check: $e"),
                passed=false,
                message="Error during check: $e"
            )
            push!(checked_guidelines, failed_guideline)
        end
    end

    # Calculate results
    passed_guidelines = filter(passed, checked_guidelines)
    failed_guidelines = filter(g -> !passed(g), checked_guidelines)
    overall_pass = length(failed_guidelines) == 0

    return LocalCheckResult(
        pkg,
        version,
        registration_type,
        commit_sha,
        overall_pass,
        passed_guidelines,
        failed_guidelines,
        length(checked_guidelines)
    )
end

"""
    _get_local_guidelines(registration_type; kwargs...) -> Vector{Tuple{Guideline, Bool}}

Get a subset of guidelines suitable for local checking.
This is a simplified version of `get_automerge_guidelines` that excludes
GitHub-specific checks that don't make sense in a local context.
"""
function _get_local_guidelines(registration_type; check_license::Bool)
    if registration_type isa NewPackage
        return [
            (guideline_name_identifier, true),
            (guideline_normal_capitalization, true),
            (guideline_name_length, true),
            (guideline_julia_name_check, true),
            (guideline_name_ascii, true),
            (guideline_standard_initial_version_number, true),
            (guideline_version_number_no_prerelease, true),
            (guideline_version_number_no_build, true),
            (guideline_version_has_osi_license, check_license),
            (guideline_src_names_OK, true),
            # Now we can use the existing robust CI guidelines with simulated registry
            (guideline_version_can_be_imported, true),
            (guideline_version_can_be_pkg_added, true),
        ]
    else  # NewVersion
        return [
            (guideline_version_number_no_prerelease, true),
            (guideline_version_number_no_build, true),
            (guideline_version_has_osi_license, check_license),
            (guideline_src_names_OK, true),
            # Now we can use the existing robust CI guidelines with simulated registry
            (guideline_version_can_be_imported, true),
            (guideline_version_can_be_pkg_added, true),
        ]
    end
end
