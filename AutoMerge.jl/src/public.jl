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

    # Authentication (always use AUTOMERGE_GITHUB_TOKEN for PR builds)
    auth = my_retry(() -> GitHub.authenticate(api, env["AUTOMERGE_GITHUB_TOKEN"]))
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

    # Authentication (always use AUTOMERGE_GITHUB_TOKEN for merge builds)
    auth = my_retry(() -> GitHub.authenticate(api, env["AUTOMERGE_GITHUB_TOKEN"]))
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
