function travis(env = ENV;
                merge_new_packages::Bool,
                merge_new_versions::Bool,
                new_package_waiting_period,
                new_version_waiting_period,
                registry::String,
                authorized_authors::Vector{String},
                #
                enable_travis_api_builds::Bool = true,
                enable_travis_cron_builds::Bool = true,
                master_branch::String = "master",
                master_branch_is_default_branch::Bool = true,
                suggest_onepointzero::Bool = true)
    registry_head = env["TRAVIS_BUILD_DIR"]::String
    RegistryCI.test(registry_head)

    TRAVIS_BRANCH = env["TRAVIS_BRANCH"]::String
    TRAVIS_EVENT_TYPE = env["TRAVIS_EVENT_TYPE"]::String
    TRAVIS_PULL_REQUEST = env["TRAVIS_PULL_REQUEST"]::String
    current_pr_head_commit_sha = env["TRAVIS_PULL_REQUEST_SHA"]::String
    is_pull_request = TRAVIS_EVENT_TYPE == "pull_request"
    is_cron = TRAVIS_BRANCH == master_branch && TRAVIS_EVENT_TYPE == "cron" && enable_travis_cron_builds
    is_api = TRAVIS_BRANCH == master_branch && TRAVIS_EVENT_TYPE == "api" && enable_travis_api_builds
    if is_pull_request || is_cron || is_api
        auth = my_retry(() -> GitHub.authenticate(env["AUTOMERGE_GITHUB_TOKEN"]))
        whoami = my_retry(() -> username(auth))
        @info("Authenticated to GitHub as \"$(whoami)\"")
        registry_repo = my_retry(() -> GitHub.repo(registry; auth=auth))
    end
    if is_pull_request
        pr_number = parse(Int, TRAVIS_PULL_REQUEST)::Int
        travis_pull_request_build(pr_number,
                                  current_pr_head_commit_sha,
                                  registry_repo,
                                  registry_head;
                                  auth = auth,
                                  authorized_authors = authorized_authors,
                                  master_branch = master_branch,
                                  master_branch_is_default_branch = master_branch_is_default_branch,
                                  suggest_onepointzero = suggest_onepointzero,
                                  whoami = whoami)
        return nothing
    else
        if TRAVIS_BRANCH == master_branch
            if is_cron || is_api
                travis_cron_or_api_build(registry_repo;
                                         auth = auth,
                                         authorized_authors = authorized_authors,
                                         merge_new_packages = merge_new_packages,
                                         merge_new_versions = merge_new_versions,
                                         new_package_waiting_period = new_package_waiting_period,
                                         new_version_waiting_period = new_version_waiting_period,
                                         whoami = whoami)
                return nothing
            else
                @info("This is not a pull request build, cron build, or API build. Exiting...")
                return nothing
            end
        else
            @info("This is not a build against the \"$(master_branch)\" branch. Exiting...")
            return nothing
        end
    end
end
