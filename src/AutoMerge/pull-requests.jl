const new_package_title_regex = r"^New package: (\w*) v(.*)"

const new_version_title_regex = r"^New version: (\w*) v(.*)"

is_new_package(pull_request::GitHub.PullRequest) = occursin(new_package_title_regex, title(pull_request))

is_new_version(pull_request::GitHub.PullRequest) = occursin(new_version_title_regex, title(pull_request))

function parse_pull_request_title(::NewVersion,
                                  pull_request::GitHub.PullRequest)
    m = match(new_version_title_regex, title(pull_request))
    pkg = convert(String, m.captures[1])::String
    version = VersionNumber(m.captures[2])
    return pkg, version
end

function parse_pull_request_title(::NewPackage,
                                  pull_request::GitHub.PullRequest)
    m = match(new_package_title_regex, title(pull_request))
    pkg = convert(String, m.captures[1])::String
    version = VersionNumber(m.captures[2])
    return pkg, version
end

function travis_pull_request_build(pr_number::Integer,
                                   current_pr_head_commit_sha::String,
                                   registry::GitHub.Repo,
                                   registry_head::String;
                                   whoami::String,
                                   auth::GitHub.Authorization,
                                   authorized_authors::Vector{String},
                                   master_branch::String,
                                   master_branch_is_default_branch::Bool,
                                   suggest_onepointzero::Bool)
    pr = my_retry(() -> GitHub.pull_request(registry, pr_number; auth=auth))
    _github_api_pr_head_commit_sha = pull_request_head_sha(pr)
    if current_pr_head_commit_sha != _github_api_pr_head_commit_sha
        error("TRAVIS_PULL_REQUEST_SHA (\"$(current_pr_head_commit_sha)\") does not match what the GitHub API tells us (\"$(_github_api_pr_head_commit_sha)\")")
    end
    result = travis_pull_request_build(pr,
                                       current_pr_head_commit_sha,
                                       registry,
                                       registry_head;
                                       auth=auth,
                                       authorized_authors=authorized_authors,
                                       master_branch=master_branch,
                                       master_branch_is_default_branch=master_branch_is_default_branch,
                                       suggest_onepointzero=suggest_onepointzero,
                                       whoami=whoami)
    return result
end

function travis_pull_request_build(pr::GitHub.PullRequest,
                                   current_pr_head_commit_sha::String,
                                   registry::GitHub.Repo,
                                   registry_head::String;
                                   auth::GitHub.Authorization,
                                   authorized_authors::Vector{String},
                                   master_branch::String,
                                   master_branch_is_default_branch::Bool,
                                   suggest_onepointzero::Bool,
                                   whoami::String)
    if is_new_package(pr)
        registry_master = clone_repo(registry)
        if !master_branch_is_default_branch
            checkout_branch(registry_master, master_branch)
        end
        travis_pull_request_build(NewPackage(),
                                  pr,
                                  current_pr_head_commit_sha,
                                  registry;
                                  auth = auth,
                                  authorized_authors=authorized_authors,
                                  registry_head = registry_head,
                                  registry_master = registry_master,
                                  suggest_onepointzero = suggest_onepointzero,
                                  whoami=whoami)
        rm(registry_master; force = true, recursive = true)
    elseif is_new_version(pr)
        registry_master = clone_repo(registry)
        if !master_branch_is_default_branch
            checkout_branch(registry_master, master_branch)
        end
        travis_pull_request_build(NewVersion(),
                                  pr,
                                  current_pr_head_commit_sha,
                                  registry;
                                  auth = auth,
                                  authorized_authors=authorized_authors,
                                  registry_head = registry_head,
                                  registry_master = registry_master,
                                  suggest_onepointzero = suggest_onepointzero,
                                  whoami=whoami)
        rm(registry_master; force = true, recursive = true)
    else
        @info("Neither a new package nor a new version. Exiting...")
        return nothing
    end
end
