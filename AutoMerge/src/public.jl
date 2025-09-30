"""
    check_pr(registry_config::RegistryConfiguration, pr_config::CheckPRConfiguration, env=ENV, cicfg::CIService=auto_detect_ci_service(; env=env))

Check a pull request for registration validity. This entrypoint runs untrusted code and does not require merge permissions.

# Arguments

- `registry_config`: RegistryConfiguration struct containing shared registry settings
- `pr_config`: CheckPRConfiguration struct containing PR validation specific settings
- `env`: an `AbstractDictionary` used to read environmental variables from.
   Defaults to `ENV` but a plain `Dict` can be passed to mimic an alternate environment.
- `cicfg`: Configuration struct describing the continuous integration (CI) environment in which AutoMerge is being run.

# Example

Here is an example of how `General` registry is configured:

```julia
using AutoMerge
(; registry_config, check_pr_config) = AutoMerge.general_registry_config()
AutoMerge.check_pr(registry_config, check_pr_config)
```

To configure a custom registry, save a `.toml` configuration file somewhere. This can be based on
the one General uses, which you can obtain by

```julia
config = AutoMerge.general_registry_config()
AutoMerge.write_config("AutoMerge.toml", config)
```

and then modify to suit your needs. This can then be used via:

```julia
using AutoMerge
(; registry_config, check_pr_config) = AutoMerge.read_config("path/to/AutoMerge.toml")
AutoMerge.check_pr(registry_config, check_pr_config)
```
"""
function check_pr(
    registry_config::RegistryConfiguration,
    pr_config::CheckPRConfiguration,
    env=ENV,
    cicfg::CIService=auto_detect_ci_service(; env=env);
)::Nothing
    api = GitHub.GitHubWebAPI(HTTP.URI(registry_config.api_url))
    registry_head = directory_of_cloned_registry(cicfg; env=env)

    # Verify this is a PR build
    run_pr_build = conditions_met_for_pr_build(cicfg; env=env, registry_config.master_branch)
    if !run_pr_build
        throw_not_automerge_applicable(
            AutoMergeWrongBuildType,
            "check_pr can only be run on pull request builds. Exiting.";
            registry_config.error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    # Authentication (use configurable token for PR builds)
    auth = my_retry(() -> GitHub.authenticate(api, env[pr_config.commit_status_token_name]))
    whoami = my_retry(() -> username(api, cicfg; auth=auth))
    @info("Authenticated to GitHub as \"$(whoami)\"")
    registry_repo = my_retry(() -> GitHub.repo(api, registry_config.registry; auth=auth))

    pr_number = pull_request_number(cicfg; env=env)
    pr_head_commit_sha = current_pr_head_commit_sha(cicfg; env=env)
    pull_request_build(
        registry_config,
        pr_config,
        api,
        pr_number,
        pr_head_commit_sha,
        registry_repo,
        registry_head;
        whoami=whoami,
        auth=auth,
    )
    return nothing
end

"""
    merge_prs(registry_config::RegistryConfiguration, merge_config::MergePRsConfiguration, env=ENV, cicfg::CIService=auto_detect_ci_service(; env=env))

Merge approved pull requests. This entrypoint requires merge permissions and does not run untrusted code.

# Arguments

- `registry_config`: RegistryConfiguration struct containing shared registry settings
- `merge_config`: MergePRsConfiguration struct containing merge specific settings
- `env`: an `AbstractDictionary` used to read environmental variables from.
   Defaults to `ENV` but a plain `Dict` can be passed to mimic an alternate environment.
- `cicfg`: Configuration struct describing the continuous integration (CI) environment in which AutoMerge is being run.

# Example

Here is an example of how `General` registry is configured:

```julia
using AutoMerge

(; registry_config, merge_prs_config) = AutoMerge.general_registry_config()
AutoMerge.merge_prs(registry_config, merge_prs_config)
```
"""
function merge_prs(
    registry_config::RegistryConfiguration,
    merge_config::MergePRsConfiguration,
    env=ENV,
    cicfg::CIService=auto_detect_ci_service(; env=env);
)::Nothing
    all_statuses = deepcopy(merge_config.additional_statuses)
    all_check_runs = deepcopy(merge_config.additional_check_runs)
    push!(all_statuses, "automerge/decision")
    unique!(all_statuses)
    unique!(all_check_runs)
    api = GitHub.GitHubWebAPI(HTTP.URI(registry_config.api_url))

    # Verify this is a merge build
    run_merge_build = conditions_met_for_merge_build(
        cicfg; env=env, registry_config.master_branch
    )
    if !run_merge_build
        throw_not_automerge_applicable(
            AutoMergeWrongBuildType,
            "merge_prs can only be run on merge/cron builds. Exiting.";
            registry_config.error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    # Authentication (use configurable token for merge builds)
    auth = my_retry(() -> GitHub.authenticate(api, env[merge_config.merge_token_name]))
    whoami = my_retry(() -> username(api, cicfg; auth=auth))
    @info("Authenticated to GitHub as \"$(whoami)\"")
    registry_repo = my_retry(() -> GitHub.repo(api, registry_config.registry; auth=auth))

    cron_or_api_build(
        registry_config,
        merge_config,
        api,
        registry_repo;
        auth=auth,
        whoami=whoami,
        all_statuses=all_statuses,
        all_check_runs=all_check_runs,
    )
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

    info, err = find_and_parse_project_toml(package_path)
    if info === false
        error(err)
    end
    pkg = info.pkg_name
    version = info.version
    uuid = info.uuid

    # Get git information
    commit_sha, tree_hash = get_current_commit_info(package_path)

    # Create temporary registries
    registry_master = mktempdir(; cleanup=true)
    cp(registry_path, registry_master; force=true)

    registry_head, registration_result = create_simulated_registry_with_package(
        package_path, registry_path
    )

    println(registration_result)

    registration_type = if registration_result[:kind] == :new_version
        NewVersion()
    elseif registration_result[:kind] == :new_package
        NewPackage()
    else
        error("Unknown registration result kind: $(registration_result[:kind]). Expected `:new_version` or `:new_package`.")
    end

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
