abstract type CIService end

###############
## Travis CI ##
###############
struct TravisCI <: CIService
    enable_cron_builds::Bool
    enable_api_builds::Bool
    function TravisCI(; enable_cron_builds=true, enable_api_builds=true)
        return new(enable_cron_builds, enable_api_builds)
    end
end
function conditions_met_for_pr_build(cfg::TravisCI; env=ENV, master_branch, kwargs...)
    return get(env, "TRAVIS_EVENT_TYPE", nothing) == "pull_request" &&
           get(env, "TRAVIS_BRANCH", nothing) == master_branch
end
function conditions_met_for_merge_build(cfg::TravisCI; env=ENV, master_branch, kwargs...)
    ## Check that we are on the correct branch
    branch_ok = get(env, "TRAVIS_BRANCH", nothing) == master_branch
    ## Check that we are running a cron or api job
    event_type = get(env, "TRAVIS_EVENT_TYPE", nothing)
    cron_ok = event_type == "cron" && cfg.enable_cron_builds
    api_ok = event_type == "api" && cfg.enable_api_builds
    return branch_ok && (cron_ok || api_ok)
end
function pull_request_number(cfg::TravisCI; env=ENV, kwargs...)
    return parse(Int, env["TRAVIS_PULL_REQUEST"])
end
function current_pr_head_commit_sha(cfg::TravisCI; env=ENV, kwargs...)
    return env["TRAVIS_PULL_REQUEST_SHA"]
end
function directory_of_cloned_registry(cfg::TravisCI; env=ENV, kwargs...)
    return env["TRAVIS_BUILD_DIR"]
end
function username(api::GitHub.GitHubAPI, cfg::TravisCI; auth)
    return username(api, auth) # use /user endpoint
end

####################
## GitHub Actions ##
####################
struct GitHubActions <: CIService
    enable_cron_builds::Bool
    function GitHubActions(; enable_cron_builds=true)
        return new(enable_cron_builds)
    end
end

function conditions_met_for_pr_build(cfg::GitHubActions; env=ENV, kwargs...)
    # TODO: Should also check the PR is against "master" or maybe thats done later?
    return get(env, "GITHUB_EVENT_NAME", nothing) == "pull_request"
end
function conditions_met_for_merge_build(
    cfg::GitHubActions; env=ENV, master_branch, kwargs...
)
    ## Check that we are on the correct branch
    m = match(r"^refs\/heads\/(.*)$", get(env, "GITHUB_REF", ""))
    branch_ok = m !== nothing && m.captures[1] == master_branch
    ## Check that we are running a cron job
    event_type = get(env, "GITHUB_EVENT_NAME", nothing)
    is_schedule = event_type == "schedule"
    is_workflow_dispatch = event_type == "workflow_dispatch"
    is_schedule_or_workflow_dispatch = is_schedule || is_workflow_dispatch
    cron_ok = is_schedule_or_workflow_dispatch && cfg.enable_cron_builds
    result = branch_ok && cron_ok
    return result
end
function pull_request_number(cfg::GitHubActions; env=ENV, kwargs...)
    m = match(r"^refs\/pull\/(\d+)\/merge$", get(env, "GITHUB_REF", ""))
    always_assert(m !== nothing)
    return parse(Int, m.captures[1])
end
function current_pr_head_commit_sha(cfg::GitHubActions; env=ENV, kwargs...)
    always_assert(get(env, "GITHUB_EVENT_NAME", nothing) == "pull_request")
    file = get(env, "GITHUB_EVENT_PATH", nothing)
    file === nothing && return nothing
    content = JSON.parsefile(file)
    return content["pull_request"]["head"]["sha"]
end
function directory_of_cloned_registry(cfg::GitHubActions; env=ENV, kwargs...)
    return get(env, "GITHUB_WORKSPACE", nothing)
end
function username(api::GitHub.GitHubAPI, cfg::GitHubActions; auth)
    # /user endpoint of GitHub API not available
    # with the GITHUB_TOKEN authentication
    return "github-actions[bot]"
end

##############
## TeamCity ##
##############
struct TeamCity <: CIService end

function conditions_met_for_pr_build(cfg::TeamCity; env=ENV, kwargs...)
    pr_number_ok = tryparse(Int, get(env, "teamcity_pullRequest_number", "")) !== nothing
    return haskey(env, "teamcity_pullRequest_title") && pr_number_ok
end

function conditions_met_for_merge_build(cfg::TeamCity; env=ENV, master_branch, kwargs...)
    pr_number_ok = tryparse(Int, get(env, "teamcity_pullRequest_number", "")) !== nothing
    haskey(env, "teamcity_pullRequest_title") && pr_number_ok && return false
    ## Check that we are on the correct branch
    m = match(r"^refs\/heads\/(.*)$", get(env, "vcsroot_branch", ""))
    branch_ok = m !== nothing && m.captures[1] == master_branch
    return branch_ok
end

function pull_request_number(cfg::TeamCity; env=ENV, kwargs...)
    pr_number = tryparse(Int, get(env, "teamcity_pullRequest_number", ""))
    always_assert(pr_number !== nothing)
    return pr_number
end

function current_pr_head_commit_sha(cfg::TeamCity; env=ENV, kwargs...)
    # black magic relying on TC build parameter teamcity.git.fetchAllHeads=true
    tc_pr_branch_name = get(env, "teamcity_pullRequest_source_branch", nothing)
    always_assert(!isnothing(tc_pr_branch_name))
    git_info = read(pipeline(`git show-ref`, `grep $tc_pr_branch_name`), String)
    git_info_row = split(git_info, "\n")[1]
    pr_sha = split(git_info_row, " ")[1]
    return string(pr_sha)
end

directory_of_cloned_registry(cfg::TeamCity; env=ENV, kwargs...) = get(env, "PWD", nothing)

username(api::GitHub.GitHubAPI, cfg::TeamCity; auth) = "svc-aivision-reg"

####################
## Auto detection ##
####################
function auto_detect_ci_service(; env=ENV)
    if haskey(env, "TRAVIS_REPO_SLUG")
        return TravisCI()
    elseif haskey(env, "GITHUB_REPOSITORY")
        return GitHubActions()
    elseif haskey(env, "TEAMCITY_PROJECT_NAME")
        return TeamCity()
    else
        error("Could not detect system.")
    end
end
