"""
    run(config::AutoMergeConfiguration, env=ENV, cicfg::CIService=auto_detect_ci_service(; env=env); config_overrides...)

Run the `AutoMerge` service.

# Arguments

- `config`: AutoMergeConfiguration struct containing all configuration options
- `env`: an `AbstractDictionary` used to read environmental variables from.
   Defaults to `ENV` but a plain `Dict` can be passed to mimic an alternate environment.
- `cicfg`: Configuration struct describing the continuous integration (CI) environment in which AutoMerge is being run.

# Keyword Arguments

Any field from `AutoMergeConfiguration` can be overridden via keyword arguments. See the documentation for [`AutoMerge.AutoMergeConfiguration`](@ref) for details on available fields.

# Example

Here is an example of how `General` registry is configured:

```julia
using AutoMerge

AutoMerge.run(AutoMerge.GENERAL_AUTOMERGE_CONFIG)
```

See [`AutoMerge.GENERAL_AUTOMERGE_CONFIG`](@ref) for the specific values used by General.
"""
function run(
    config::AutoMergeConfiguration,
    env=ENV,
    cicfg::CIService=auto_detect_ci_service(; env=env);
    config_overrides...
)::Nothing
    # Apply configuration overrides
    config = AutoMergeConfiguration(; ((k => getproperty(config, k)) for k in propertynames(config))..., config_overrides...)

    all_statuses = deepcopy(config.additional_statuses)
    all_check_runs = deepcopy(config.additional_check_runs)
    push!(all_statuses, "automerge/decision")
    unique!(all_statuses)
    unique!(all_check_runs)
    api = GitHub.GitHubWebAPI(HTTP.URI(config.api_url))

    registry_head = directory_of_cloned_registry(cicfg; env=env)

    # Figure out what type of build this is
    run_pr_build = conditions_met_for_pr_build(cicfg; env=env, config.master_branch)
    run_merge_build = conditions_met_for_merge_build(
        cicfg; env=env, config.master_branch
    )

    if !(run_pr_build || run_merge_build)
        throw_not_automerge_applicable(
            AutoMergeWrongBuildType,
            "Build not determined to be either a PR build or a merge build. Exiting.";
            config.error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    # Authentication
    key = if run_pr_build || !config.tagbot_enabled
        "AUTOMERGE_GITHUB_TOKEN"
    else
        "AUTOMERGE_TAGBOT_TOKEN"
    end
    auth = my_retry(() -> GitHub.authenticate(api, env[key]))
    whoami = my_retry(() -> username(api, cicfg; auth=auth))
    @info("Authenticated to GitHub as \"$(whoami)\"")
    registry_repo = my_retry(() -> GitHub.repo(api, config.registry; auth=auth))

    if run_pr_build
        pr_number = pull_request_number(cicfg; env=env)
        pr_head_commit_sha = current_pr_head_commit_sha(cicfg; env=env)
        pull_request_build(
            config,
            api,
            pr_number,
            pr_head_commit_sha,
            registry_repo,
            registry_head;
            whoami=whoami,
            auth=auth,
        )
    else
        always_assert(run_merge_build)
        cron_or_api_build(
            config,
            api,
            registry_repo;
            auth=auth,
            whoami=whoami,
            all_statuses=all_statuses,
            all_check_runs=all_check_runs,
        )
    end
    return nothing
end
