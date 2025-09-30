"""
    check_pr(; registry, authorized_authors, ..., env=ENV, cicfg=auto_detect_ci_service(; env=env))

Check a pull request for registration validity. This entrypoint runs untrusted code and does not require merge permissions.

# Required Arguments

- `registry::String`: the registry name you want to run AutoMerge on.
- `authorized_authors::Vector{String}`: list of who can submit registration, e.g `String["JuliaRegistrator"]`.
- `authorized_authors_special_jll_exceptions::Vector{String}`: a list of users who can submit JLL packages.
- `new_package_waiting_minutes::Dates.Minute`: new package waiting period in minutes.
- `new_jll_package_waiting_minutes::Dates.Minute`: new JLL package waiting period in minutes.
- `new_version_waiting_minutes::Dates.Minute`: new package version waiting period in minutes.
- `new_jll_version_waiting_minutes::Dates.Minute`: new JLL package version waiting period in minutes.

# Optional Arguments

- `master_branch::String = "master"`: name of `master_branch`.
- `error_exit_if_automerge_not_applicable::Bool = false`: if `false`, AutoMerge will not error on PRs made by non-AutoMerge-authorized users
- `api_url::String = "https://api.github.com"`: the registry host API URL.
- `read_only::Bool = false`: run in read only mode.
- `master_branch_is_default_branch::Bool = true`: if `master_branch` is the default branch.
- `suggest_onepointzero::Bool = true`: should the AutoMerge comment include a suggestion to tag a 1.0 release.
- `point_to_slack::Bool = false`: should the AutoMerge comment recommend sending a message to the `#pkg-registration` Julia-Slack channel.
- `registry_deps::Vector{<:AbstractString} = String[]`: list of registry dependencies.
- `check_license::Bool = false`: check package has a valid license.
- `check_breaking_explanation::Bool = false`: Check whether the PR has breaking change explanation.
- `public_registries::Vector{<:AbstractString} = String[]`: registries to check for UUID collisions.
- `environment_variables_to_pass::Vector{<:AbstractString} = String[]`: Environment variables to pass to subprocess.
- `commit_status_token_name::String = "AUTOMERGE_GITHUB_TOKEN"`: Name of environment variable containing GitHub token.
- `env`: an `AbstractDictionary` used to read environmental variables from.
- `cicfg`: Configuration struct describing the continuous integration (CI) environment.
"""
function check_pr(;
    # Registry configuration
    registry::String,
    authorized_authors::Vector{String},
    authorized_authors_special_jll_exceptions::Vector{String},
    new_package_waiting_minutes::Dates.Minute,
    new_jll_package_waiting_minutes::Dates.Minute,
    new_version_waiting_minutes::Dates.Minute,
    new_jll_version_waiting_minutes::Dates.Minute,
    master_branch::String = "master",
    error_exit_if_automerge_not_applicable::Bool = false,
    api_url::String = "https://api.github.com",
    read_only::Bool = false,
    # PR configuration
    master_branch_is_default_branch::Bool = true,
    suggest_onepointzero::Bool = true,
    point_to_slack::Bool = false,
    registry_deps::Vector{<:AbstractString} = String[],
    check_license::Bool = false,
    check_breaking_explanation::Bool = false,
    public_registries::Vector{<:AbstractString} = String[],
    environment_variables_to_pass::Vector{<:AbstractString} = String[],
    commit_status_token_name::String = "AUTOMERGE_GITHUB_TOKEN",
    # System
    env = ENV,
    cicfg::CIService = auto_detect_ci_service(; env=env)
)::Nothing
    api = GitHub.GitHubWebAPI(HTTP.URI(api_url))
    registry_head = directory_of_cloned_registry(cicfg; env=env)

    # Verify this is a PR build
    run_pr_build = conditions_met_for_pr_build(cicfg; env=env, master_branch)
    if !run_pr_build
        throw_not_automerge_applicable(
            AutoMergeWrongBuildType,
            "check_pr can only be run on pull request builds. Exiting.";
            error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    # Authentication (use configurable token for PR builds)
    auth = my_retry(() -> GitHub.authenticate(api, env[commit_status_token_name]))
    whoami = my_retry(() -> username(api, cicfg; auth=auth))
    @info("Authenticated to GitHub as \"$(whoami)\"")
    registry_repo = my_retry(() -> GitHub.repo(api, registry; auth=auth))

    pr_number = pull_request_number(cicfg; env=env)
    pr_head_commit_sha = current_pr_head_commit_sha(cicfg; env=env)
    pull_request_build(
        api,
        pr_number,
        pr_head_commit_sha,
        registry_repo,
        registry_head;
        # Registry config args
        registry=registry,
        authorized_authors=authorized_authors,
        authorized_authors_special_jll_exceptions=authorized_authors_special_jll_exceptions,
        new_package_waiting_minutes=new_package_waiting_minutes,
        new_jll_package_waiting_minutes=new_jll_package_waiting_minutes,
        new_version_waiting_minutes=new_version_waiting_minutes,
        new_jll_version_waiting_minutes=new_jll_version_waiting_minutes,
        master_branch=master_branch,
        error_exit_if_automerge_not_applicable=error_exit_if_automerge_not_applicable,
        api_url=api_url,
        read_only=read_only,
        # PR config args
        master_branch_is_default_branch=master_branch_is_default_branch,
        suggest_onepointzero=suggest_onepointzero,
        point_to_slack=point_to_slack,
        registry_deps=registry_deps,
        check_license=check_license,
        check_breaking_explanation=check_breaking_explanation,
        public_registries=public_registries,
        environment_variables_to_pass=environment_variables_to_pass,
        commit_status_token_name=commit_status_token_name,
        whoami=whoami,
        auth=auth,
    )
    return nothing
end

"""
    merge_prs(; registry, authorized_authors, ..., env=ENV, cicfg=auto_detect_ci_service(; env=env))

Merge approved pull requests. This entrypoint requires merge permissions and does not run untrusted code.

# Required Arguments

- `registry::String`: the registry name you want to run AutoMerge on.
- `authorized_authors::Vector{String}`: list of who can submit registration, e.g `String["JuliaRegistrator"]`.
- `authorized_authors_special_jll_exceptions::Vector{String}`: a list of users who can submit JLL packages.
- `new_package_waiting_minutes::Dates.Minute`: new package waiting period in minutes.
- `new_jll_package_waiting_minutes::Dates.Minute`: new JLL package waiting period in minutes.
- `new_version_waiting_minutes::Dates.Minute`: new package version waiting period in minutes.
- `new_jll_version_waiting_minutes::Dates.Minute`: new JLL package version waiting period in minutes.

# Optional Arguments

- `master_branch::String = "master"`: name of `master_branch`.
- `error_exit_if_automerge_not_applicable::Bool = false`: if `false`, AutoMerge will not error on PRs made by non-AutoMerge-authorized users
- `api_url::String = "https://api.github.com"`: the registry host API URL.
- `read_only::Bool = false`: run in read only mode.
- `merge_new_packages::Bool = true`: should AutoMerge merge registration PRs for new packages
- `merge_new_versions::Bool = true`: should AutoMerge merge registration PRs for new versions of packages
- `additional_statuses::AbstractVector{<:AbstractString} = String[]`: list of additional commit statuses that must pass
- `additional_check_runs::AbstractVector{<:AbstractString} = String[]`: list of additional check runs that must pass
- `merge_token_name::String = "AUTOMERGE_MERGE_TOKEN"`: Name of environment variable containing GitHub token for PR merging.
- `env`: an `AbstractDictionary` used to read environmental variables from.
- `cicfg`: Configuration struct describing the continuous integration (CI) environment.
"""
function merge_prs(;
    # Registry configuration
    registry::String,
    authorized_authors::Vector{String},
    authorized_authors_special_jll_exceptions::Vector{String},
    new_package_waiting_minutes::Dates.Minute,
    new_jll_package_waiting_minutes::Dates.Minute,
    new_version_waiting_minutes::Dates.Minute,
    new_jll_version_waiting_minutes::Dates.Minute,
    master_branch::String = "master",
    error_exit_if_automerge_not_applicable::Bool = false,
    api_url::String = "https://api.github.com",
    read_only::Bool = false,
    # Merge configuration
    merge_new_packages::Bool = true,
    merge_new_versions::Bool = true,
    additional_statuses::AbstractVector{<:AbstractString} = String[],
    additional_check_runs::AbstractVector{<:AbstractString} = String[],
    merge_token_name::String = "AUTOMERGE_MERGE_TOKEN",
    # System
    env = ENV,
    cicfg::CIService = auto_detect_ci_service(; env=env)
)::Nothing
    all_statuses = deepcopy(additional_statuses)
    all_check_runs = deepcopy(additional_check_runs)
    push!(all_statuses, "automerge/decision")
    unique!(all_statuses)
    unique!(all_check_runs)
    api = GitHub.GitHubWebAPI(HTTP.URI(api_url))

    # Verify this is a merge build
    run_merge_build = conditions_met_for_merge_build(
        cicfg; env=env, master_branch
    )
    if !run_merge_build
        throw_not_automerge_applicable(
            AutoMergeWrongBuildType,
            "merge_prs can only be run on merge/cron builds. Exiting.";
            error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    # Authentication (use configurable token for merge builds)
    auth = my_retry(() -> GitHub.authenticate(api, env[merge_token_name]))
    whoami = my_retry(() -> username(api, cicfg; auth=auth))
    @info("Authenticated to GitHub as \"$(whoami)\"")
    registry_repo = my_retry(() -> GitHub.repo(api, registry; auth=auth))

    cron_or_api_build(
        api,
        registry_repo;
        # Registry config args
        registry=registry,
        authorized_authors=authorized_authors,
        authorized_authors_special_jll_exceptions=authorized_authors_special_jll_exceptions,
        new_package_waiting_minutes=new_package_waiting_minutes,
        new_jll_package_waiting_minutes=new_jll_package_waiting_minutes,
        new_version_waiting_minutes=new_version_waiting_minutes,
        new_jll_version_waiting_minutes=new_jll_version_waiting_minutes,
        master_branch=master_branch,
        error_exit_if_automerge_not_applicable=error_exit_if_automerge_not_applicable,
        api_url=api_url,
        read_only=read_only,
        # Merge config args
        merge_new_packages=merge_new_packages,
        merge_new_versions=merge_new_versions,
        additional_statuses=additional_statuses,
        additional_check_runs=additional_check_runs,
        merge_token_name=merge_token_name,
        auth=auth,
        whoami=whoami,
        all_statuses=all_statuses,
        all_check_runs=all_check_runs,
    )
    return nothing
end
