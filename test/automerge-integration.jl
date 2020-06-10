using Dates
# using GitCommand
using GitHub
using JSON
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
whoami = RegistryCI.AutoMerge.username(GitHub.DEFAULT_API, auth)
repo_url_without_auth = "https://github.com/$(AUTOMERGE_INTEGRATION_TEST_REPO)"
repo_url_with_auth = "https://$(whoami):$(TEST_USER_GITHUB_TOKEN)@github.com/$(AUTOMERGE_INTEGRATION_TEST_REPO)"
repo = GitHub.repo(AUTOMERGE_INTEGRATION_TEST_REPO; auth = auth)
@test success(`$(GIT) --version`)
@info("Authenticated to GitHub as \"$(whoami)\"")

close_all_pull_requests(GitHub.DEFAULT_API, repo; auth = auth, state = "open")
delete_stale_branches(repo_url_with_auth; GIT = GIT)

@testset "Integration tests" begin
    for (test_number, master_dir, feature_dir, title, pass) in [
            (1, "master_1", "feature_1", "New package: Requires v1.0.0", true),            # OK: new package
            (2, "master_2", "feature_2", "New version: Requires v2.0.0", true),            # OK: new version
            (3, "master_1", "feature_3", "New package: Req v1.0.0", false),                # FAIL: name too short
            (4, "master_2", "feature_4", "New version: Requires v2.0.1", false),           # FAIL: skips v2.0.0
            (5, "master_3", "feature_5", "New version: Requires v2.0.0", false),           # FAIL: modifies extra file
            (6, "master_1", "feature_6", "New package: HelloWorldC_jll v1.0.6+0", true),   # OK: new JLL package
            (7, "master_4", "feature_7", "New version: HelloWorldC_jll v1.0.8+0", true),   # OK: new JLL version
            (8, "master_1", "feature_8", "New package: HelloWorldC_jll v1.0.6+0", false),  # FAIL: unallowed dependency
        ]
        with_master_branch(templates(master_dir), "master"; GIT = GIT, repo_url = repo_url_with_auth) do master
            with_feature_branch(templates(feature_dir), master; GIT = GIT, repo_url = repo_url_with_auth) do feature
                head = feature
                base = master
                params = Dict("title" => title,
                              "head" => head,
                              "base" => base)
                pr = GitHub.create_pull_request(repo; auth = auth, params = params)
                pr = wait_pr_compute_mergeability(GitHub.DEFAULT_API, repo, pr; auth = auth)
                @test pr.mergeable
                with_pr_merge_commit(pr, repo_url_without_auth; GIT = GIT) do build_dir
                    withenv("AUTOMERGE_GITHUB_TOKEN" => TEST_USER_GITHUB_TOKEN,
                            "TRAVIS_BRANCH" => master,
                            "TRAVIS_BUILD_DIR" => build_dir,
                            "TRAVIS_EVENT_TYPE" => "pull_request",
                            "TRAVIS_PULL_REQUEST" => string(pr.number),
                            "TRAVIS_PULL_REQUEST_SHA" => string(AutoMerge.pull_request_head_sha(pr)),
                            "TRAVIS_REPO_SLUG" => AUTOMERGE_INTEGRATION_TEST_REPO) do
                        run_thunk = () -> AutoMerge.run(;
                                      merge_new_packages = true,
                                      merge_new_versions = true,
                                      new_package_waiting_period = Minute(typemax(Int32)),
                                      new_jll_package_waiting_period = Minute(typemax(Int32)),
                                      new_version_waiting_period = Minute(typemax(Int32)),
                                      new_jll_version_waiting_period = Minute(typemax(Int32)),
                                      registry = AUTOMERGE_INTEGRATION_TEST_REPO,
                                      authorized_authors = String[whoami],
                                      authorized_authors_special_jll_exceptions = String[whoami],
                                      master_branch = master,
                                      master_branch_is_default_branch = false)
                        @info "Running integration test for " test_number master_dir feature_dir title pass
                        if pass
                            run_thunk()
                        else
                            @test_throws(RegistryCI.AutoMerge.AutoMergeGuidelinesNotMet, run_thunk())
                        end

                    end
                    withenv("AUTOMERGE_GITHUB_TOKEN" => TEST_USER_GITHUB_TOKEN,
                            "TRAVIS_BRANCH" => master,
                            "TRAVIS_BUILD_DIR" => build_dir,
                            "TRAVIS_EVENT_TYPE" => "cron",
                            "TRAVIS_PULL_REQUEST" => "false",
                            "TRAVIS_PULL_REQUEST_SHA" => "",
                            "TRAVIS_REPO_SLUG" => AUTOMERGE_INTEGRATION_TEST_REPO) do
                        AutoMerge.run(;
                                      merge_new_packages = true,
                                      merge_new_versions = true,
                                      new_package_waiting_period = Minute(typemax(Int32)),
                                      new_jll_package_waiting_period = Minute(typemax(Int32)),
                                      new_version_waiting_period = Minute(typemax(Int32)),
                                      new_jll_version_waiting_period = Minute(typemax(Int32)),
                                      registry = AUTOMERGE_INTEGRATION_TEST_REPO,
                                      authorized_authors = String[whoami],
                                      authorized_authors_special_jll_exceptions = String[whoami],
                                      master_branch = master,
                                      master_branch_is_default_branch = false)
                        AutoMerge.run(;
                                      merge_new_packages = true,
                                      merge_new_versions = true,
                                      new_package_waiting_period = Minute(0),
                                      new_jll_package_waiting_period = Minute(0),
                                      new_version_waiting_period = Minute(0),
                                      new_jll_version_waiting_period = Minute(0),
                                      registry = AUTOMERGE_INTEGRATION_TEST_REPO,
                                      authorized_authors = String[whoami],
                                      authorized_authors_special_jll_exceptions = String[whoami],
                                      master_branch = master,
                                      master_branch_is_default_branch = false)
                    end
                end
            end
        end
    end
end
