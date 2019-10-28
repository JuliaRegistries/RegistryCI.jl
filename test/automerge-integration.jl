using Dates
using GitHub
using Pkg
using Printf
using RegistryCI
using Test
using TimeZones

const AutoMerge = RegistryCI.AutoMerge

include("automerge-integration-utils.jl")

AUTOMERGE_INTEGRATION_TEST_REPO = ENV["AUTOMERGE_INTEGRATION_TEST_REPO"]::String
TEST_USER_GITHUB_TOKEN = ENV["BCBI_TEST_USER_GITHUB_TOKEN"]::String
GIT = "git"
auth = GitHub.authenticate(TEST_USER_GITHUB_TOKEN)
whoami = RegistryCI.AutoMerge.username(auth)
repo_url_without_auth = "https://github.com/$(AUTOMERGE_INTEGRATION_TEST_REPO)"
repo_url_with_auth = "https://$(whoami):$(TEST_USER_GITHUB_TOKEN)@github.com/$(AUTOMERGE_INTEGRATION_TEST_REPO)"
repo = GitHub.repo(AUTOMERGE_INTEGRATION_TEST_REPO; auth = auth)
@test success(`$(GIT) --version`)
@info("Authenticated to GitHub as \"$(whoami)\"")

close_all_pull_requests(repo; auth = auth, state = "open")
delete_stale_branches(repo_url_with_auth; GIT = GIT)

with_master_branch(templates("master_1"), "master"; GIT = GIT, repo_url = repo_url_with_auth) do master_1
    with_feature_branch(templates("feature_1"), master_1; GIT = GIT, repo_url = repo_url_with_auth) do feature_1
        title = "New package: Requires v1.0.0"
        head = feature_1
        base = master_1
        params = Dict("title" => title,
                      "head" => head,
                      "base" => base)
        pr_1_1 = GitHub.create_pull_request(repo; auth = auth, params = params)
        pr_1_1 = wait_pr_compute_mergeability(repo, pr_1_1; auth = auth)
        @test pr_1_1.mergeable
        with_pr_merge_commit(pr_1_1, repo_url_without_auth; GIT = GIT) do build_dir
            withenv("AUTOMERGE_GITHUB_TOKEN" => TEST_USER_GITHUB_TOKEN,
                    "TRAVIS_BRANCH" => master_1,
                    "TRAVIS_BUILD_DIR" => build_dir,
                    "TRAVIS_EVENT_TYPE" => "pull_request",
                    "TRAVIS_PULL_REQUEST" => string(pr_1_1.number),
                    "TRAVIS_PULL_REQUEST_SHA" => string(AutoMerge.pull_request_head_sha(pr_1_1))) do
                AutoMerge.travis(;
                                 merge_new_packages = true,
                                 merge_new_versions = true,
                                 new_package_waiting_period = Minute(typemax(Int32)),
                                 new_version_waiting_period = Minute(typemax(Int32)),
                                 registry = AUTOMERGE_INTEGRATION_TEST_REPO,
                                 authorized_authors = String[whoami],
                                 master_branch = master_1,
                                 master_branch_is_default_branch = false)

            end
            withenv("AUTOMERGE_GITHUB_TOKEN" => TEST_USER_GITHUB_TOKEN,
                    "TRAVIS_BRANCH" => master_1,
                    "TRAVIS_BUILD_DIR" => build_dir,
                    "TRAVIS_EVENT_TYPE" => "cron",
                    "TRAVIS_PULL_REQUEST" => "false",
                    "TRAVIS_PULL_REQUEST_SHA" => "") do
                AutoMerge.travis(;
                                 merge_new_packages = true,
                                 merge_new_versions = true,
                                 new_package_waiting_period = Minute(typemax(Int32)),
                                 new_version_waiting_period = Minute(typemax(Int32)),
                                 registry = AUTOMERGE_INTEGRATION_TEST_REPO,
                                 authorized_authors = String[whoami],
                                 master_branch = master_1,
                                 master_branch_is_default_branch = false)

            end
        end
    end
end

with_master_branch(templates("master_2"), "master"; GIT = GIT, repo_url = repo_url_with_auth) do master_2
    with_feature_branch(templates("feature_2"), master_2; GIT = GIT, repo_url = repo_url_with_auth) do feature_2
        title = "New version: Requires v2.0.0"
        head = feature_2
        base = master_2
        params = Dict("title" => title,
                      "head" => head,
                      "base" => base)
        pr_2_2 = GitHub.create_pull_request(repo; auth = auth, params = params)
        pr_2_2 = wait_pr_compute_mergeability(repo, pr_2_2; auth = auth)
        @test pr_2_2.mergeable
        with_pr_merge_commit(pr_2_2, repo_url_without_auth; GIT = GIT) do build_dir
            withenv("AUTOMERGE_GITHUB_TOKEN" => TEST_USER_GITHUB_TOKEN,
                    "TRAVIS_BRANCH" => master_2,
                    "TRAVIS_BUILD_DIR" => build_dir,
                    "TRAVIS_EVENT_TYPE" => "pull_request",
                    "TRAVIS_PULL_REQUEST" => string(pr_2_2.number),
                    "TRAVIS_PULL_REQUEST_SHA" => string(AutoMerge.pull_request_head_sha(pr_2_2))) do
                AutoMerge.travis(;
                                 merge_new_packages = true,
                                 merge_new_versions = true,
                                 new_package_waiting_period = Minute(typemax(Int32)),
                                 new_version_waiting_period = Minute(typemax(Int32)),
                                 registry = AUTOMERGE_INTEGRATION_TEST_REPO,
                                 authorized_authors = String[whoami],
                                 master_branch = master_2,
                                 master_branch_is_default_branch = false)

            end
            withenv("AUTOMERGE_GITHUB_TOKEN" => TEST_USER_GITHUB_TOKEN,
                    "TRAVIS_BRANCH" => master_2,
                    "TRAVIS_BUILD_DIR" => build_dir,
                    "TRAVIS_EVENT_TYPE" => "cron",
                    "TRAVIS_PULL_REQUEST" => "false",
                    "TRAVIS_PULL_REQUEST_SHA" => "") do
                AutoMerge.travis(;
                                 merge_new_packages = true,
                                 merge_new_versions = true,
                                 new_package_waiting_period = Minute(typemax(Int32)),
                                 new_version_waiting_period = Minute(typemax(Int32)),
                                 registry = AUTOMERGE_INTEGRATION_TEST_REPO,
                                 authorized_authors = String[whoami],
                                 master_branch = master_2,
                                 master_branch_is_default_branch = false)

            end
        end
    end
end
