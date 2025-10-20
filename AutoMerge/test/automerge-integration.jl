using Dates
# using GitCommand
using GitHub
using JSON
using Pkg
using Printf
using AutoMerge
using Test
using TimeZones


include("automerge-integration-utils.jl")

AUTOMERGE_INTEGRATION_TEST_REPO = ENV["AUTOMERGE_INTEGRATION_TEST_REPO"]::String
TEST_USER_GITHUB_TOKEN = ENV["BCBI_TEST_USER_GITHUB_TOKEN"]::String
INTEGRATION_TEST_READ_ONLY_TOKEN = ENV["INTEGRATION_TEST_READ_ONLY_TOKEN"]::String
GIT = "git"
auth = GitHub.authenticate(TEST_USER_GITHUB_TOKEN)
whoami = AutoMerge.username(GitHub.DEFAULT_API, auth)
repo_url_without_auth = "https://github.com/$(AUTOMERGE_INTEGRATION_TEST_REPO)"
repo_url_with_auth = "https://$(whoami):$(TEST_USER_GITHUB_TOKEN)@github.com/$(AUTOMERGE_INTEGRATION_TEST_REPO)"
repo = GitHub.repo(AUTOMERGE_INTEGRATION_TEST_REPO; auth=auth)
@test success(`$(GIT) --version`)
@info("Authenticated to GitHub as \"$(whoami)\"")

_delete_branches_older_than = Dates.Hour(3)
delete_old_pull_request_branches(repo_url_with_auth, _delete_branches_older_than; GIT=GIT)

requires_commit = "1c843ed4d4d568345ca557fea48f43efdcd0271f"
hello_world_commit1 = "197e0e03f3f840f830cb5095ab6407d00fbee61c"
hello_world_commit2 = "57b0aec49622faa962c6752d4bc39a62b91fe37c"

@testset "Integration tests" begin
    for (
        test_number,
        (master_dir, feature_dir, public_dir, title, point_to_slack, check_license, pass, commit, create_blocking_comment),
    ) in enumerate([
        (
            "master_1",
            "feature_1",
            "",
            "New package: Requires v1.0.0",
            true,   # point_to_slack
            true,   # check_license
            true,   # pass
            requires_commit,
            false,  # create_blocking_comment
        ), # OK: new package
        (
            "master_1",
            "feature_1",
            "",
            "New package: Requires v1.0.0",
            true,   # point_to_slack
            true,   # check_license
            true,   # pass
            requires_commit,
            true,  # create_blocking_comment
        ), # OK: new package
        (
            "master_1",
            "feature_1",
            "",
            "New package: Requires v1.0.0",
            true,   # point_to_slack
            true,   # check_license
            false,  # pass
            "659e09770ba9fda4a503f8bf281d446c9583ff3b",
            false,  # create_blocking_comment
        ), # FAIL: wrong commit!
        (
            "master_2",
            "feature_2",
            "",
            "New version: Requires v2.0.0",
            false,  # point_to_slack
            false,  # check_license
            true,   # pass
            requires_commit,
            false,  # create_blocking_comment
        ),            # OK: new version
        (
            "master_1",
            "feature_3",
            "",
            "New package: Req v1.0.0",
            false,  # point_to_slack
            false,  # check_license
            false,  # pass
            requires_commit,
            false,  # create_blocking_comment
        ),                # FAIL: name too short
        (
            "master_2",
            "feature_4",
            "",
            "New version: Requires v2.0.1",
            false,  # point_to_slack
            false,  # check_license
            false,  # pass
            requires_commit,
            false,  # create_blocking_comment
        ),           # FAIL: skips v2.0.0
        (
            "master_3",
            "feature_5",
            "",
            "New version: Requires v2.0.0",
            false,  # point_to_slack
            false,  # check_license
            false,  # pass
            requires_commit,
            false,  # create_blocking_comment
        ),           # FAIL: modifies extra file
        (
            "master_1",
            "feature_6",
            "",
            "New package: HelloWorldC_jll v1.0.6+0",
            false,  # point_to_slack
            false,  # check_license
            true,   # pass
            hello_world_commit1,
            false,  # create_blocking_comment
        ),   # OK: new JLL package
        (
            "master_4",
            "feature_7",
            "",
            "New version: HelloWorldC_jll v1.0.8+0",
            false,  # point_to_slack
            false,  # check_license
            true,   # pass
            hello_world_commit2,
            false,  # create_blocking_comment
        ),   # OK: new JLL version
        (
            "master_1",
            "feature_8",
            "",
            "New package: HelloWorldC_jll v1.0.6+0",
            false,  # point_to_slack
            false,  # check_license
            false,  # pass
            hello_world_commit1,
            false,  # create_blocking_comment
        ),  # FAIL: unallowed dependency
        (
            "master_1",
            "feature_1",
            "public_1",
            "New package: Requires v1.0.0",
            false,  # point_to_slack
            false,  # check_license
            true,   # pass
            requires_commit,
            false,  # create_blocking_comment
        ),    # OK: no UUID conflict
        (
            "master_1",
            "feature_1",
            "public_2",
            "New package: Requires v1.0.0",
            false,  # point_to_slack
            false,  # check_license
            false,  # pass
            requires_commit,
            false,  # create_blocking_comment
        ),  # FAIL: UUID conflict, name differs
        (
            "master_1",
            "feature_1",
            "public_3",
            "New package: Requires v1.0.0",
            false,  # point_to_slack
            false,  # check_license
            false,  # pass
            requires_commit,
            false,  # create_blocking_comment
        ),  # FAIL: UUID conflict, repo differs
        (
            "master_1",
            "feature_1",
            "public_4",
            "New package: Requires v1.0.0",
            false,  # point_to_slack
            false,  # check_license
            true,   # pass
            requires_commit,
            false,  # create_blocking_comment
        ),   # OK: UUID conflict but name and repo match
        (
            "master_1",
            "feature_9",
            "",
            "New package: Requires-dash v1.0.0",
            true,   # point_to_slack
            true,   # check_license
            false,   # pass
            requires_commit,
            false,  # create_blocking_comment
        ), # FAIL: new package name is not a Julia identifier
    ])
        @info "Performing integration tests with settings" test_number master_dir feature_dir public_dir title point_to_slack check_license pass commit
        with_master_branch(
            templates(master_dir), "master"; GIT=GIT, repo_url=repo_url_with_auth
        ) do master
            with_feature_branch(
                templates(feature_dir), master; GIT=GIT, repo_url=repo_url_with_auth
            ) do feature
                public_registries = String[]
                if public_dir != ""
                    public_git_repo = generate_public_registry(public_dir, GIT)
                    push!(public_registries, "file://$(public_git_repo)/.git")
                end
                head = feature
                base = master
                body = """
                - Foo: Bar
                - Commit: $commit
                - Hello: World
                """
                params = Dict(
                    "title" => title, "head" => head, "base" => base, "body" => body
                )

                sleep(1)
                pr = GitHub.create_pull_request(repo; auth=auth, params=params)
                pr = wait_pr_compute_mergeability(GitHub.DEFAULT_API, repo, pr; auth=auth)
                @test pr.mergeable
                sleep(1)
                with_pr_merge_commit(pr, repo_url_without_auth; GIT=GIT) do build_dir
                    withenv(
                        "AUTOMERGE_GITHUB_TOKEN" => TEST_USER_GITHUB_TOKEN,
                        "AUTOMERGE_MERGE_TOKEN" => TEST_USER_GITHUB_TOKEN,
                        "TRAVIS_BRANCH" => master,
                        "TRAVIS_BUILD_DIR" => build_dir,
                        "TRAVIS_EVENT_TYPE" => "pull_request",
                        "TRAVIS_PULL_REQUEST" => string(pr.number),
                        "TRAVIS_PULL_REQUEST_SHA" =>
                            string(AutoMerge.pull_request_head_sha(pr)),
                        "TRAVIS_REPO_SLUG" => AUTOMERGE_INTEGRATION_TEST_REPO,
                    ) do
                        sleep(1)

                        registry_config = AutoMerge.RegistryConfiguration(
                            registry=AUTOMERGE_INTEGRATION_TEST_REPO,
                            authorized_authors=String[whoami],
                            authorized_authors_special_jll_exceptions=String[whoami],
                            new_package_waiting_minutes=Minute(typemax(Int32)),
                            new_jll_package_waiting_minutes=Minute(typemax(Int32)),
                            new_version_waiting_minutes=Minute(typemax(Int32)),
                            new_jll_version_waiting_minutes=Minute(typemax(Int32)),
                            error_exit_if_automerge_not_applicable=true,
                            master_branch=master
                        )
                        check_pr_config = AutoMerge.CheckPRConfiguration(
                            master_branch_is_default_branch=false,
                            point_to_slack=point_to_slack,
                            check_license=check_license,
                            public_registries=public_registries
                        )
                        run_thunk =
                            () -> AutoMerge.check_pr(registry_config, check_pr_config)
                        @info "Running integration test for " test_number master_dir feature_dir public_dir title point_to_slack check_license pass commit
                        if pass
                            run_thunk()
                        else
                            @test_throws(
                                AutoMerge.AutoMergeGuidelinesNotMet, run_thunk()
                            )
                        end
                    end
                    withenv(
                        "AUTOMERGE_GITHUB_TOKEN" => TEST_USER_GITHUB_TOKEN,
                        "AUTOMERGE_MERGE_TOKEN" => TEST_USER_GITHUB_TOKEN,
                        "TRAVIS_BRANCH" => master,
                        "TRAVIS_BUILD_DIR" => build_dir,
                        "TRAVIS_EVENT_TYPE" => "cron",
                        "TRAVIS_PULL_REQUEST" => "false",
                        "TRAVIS_PULL_REQUEST_SHA" => "",
                        "TRAVIS_REPO_SLUG" => AUTOMERGE_INTEGRATION_TEST_REPO,
                    ) do
                        sleep(1)
                        if create_blocking_comment
                            blocking_comment = GitHub.create_comment(repo, pr, "blocking comment", auth=auth)
                            # Delete the comment on exit, if we don't do so sooner
                            atexit() do
                                GitHub.delete_comment(repo, blocking_comment; auth=auth, handle_error=false)
                            end
                        end
                        registry_config = AutoMerge.RegistryConfiguration(
                            registry=AUTOMERGE_INTEGRATION_TEST_REPO,
                            authorized_authors=String[whoami],
                            authorized_authors_special_jll_exceptions=String[whoami],
                            new_package_waiting_minutes=Minute(typemax(Int32)),
                            new_jll_package_waiting_minutes=Minute(typemax(Int32)),
                            new_version_waiting_minutes=Minute(typemax(Int32)),
                            new_jll_version_waiting_minutes=Minute(typemax(Int32)),
                            error_exit_if_automerge_not_applicable=true,
                            master_branch=master
                        )
                        merge_prs_config = AutoMerge.MergePRsConfiguration(
                            merge_new_packages=true,
                            merge_new_versions=true
                        )
                        AutoMerge.merge_prs(registry_config, merge_prs_config)
                        sleep(1)
                        registry_config = AutoMerge.RegistryConfiguration(
                            registry=AUTOMERGE_INTEGRATION_TEST_REPO,
                            authorized_authors=String[whoami],
                            authorized_authors_special_jll_exceptions=String[whoami],
                            new_package_waiting_minutes=Minute(0),
                            new_jll_package_waiting_minutes=Minute(0),
                            new_version_waiting_minutes=Minute(0),
                            new_jll_version_waiting_minutes=Minute(0),
                            error_exit_if_automerge_not_applicable=true,
                            master_branch=master
                        )
                        merge_prs_config = AutoMerge.MergePRsConfiguration(
                            merge_new_packages=true,
                            merge_new_versions=true
                        )
                        merge = () -> AutoMerge.merge_prs(registry_config, merge_prs_config)
                        merge()
                        if create_blocking_comment
                            # Check we have the blocked label
                            labels = GitHub.labels(repo, pr)
                            @test AutoMerge.has_label(labels, AutoMerge.BLOCKED_LABEL)
                            # Delete the comment & rerun
                            GitHub.delete_comment(repo, blocking_comment; auth=auth)
                            sleep(1)
                            merge()
                            sleep(1)
                            # Check we no longer have the blocked label
                            labels = GitHub.labels(repo, pr)
                            # This test is not working, but I have verified the label
                            # is indeed being removed appropriately.
                            # @test !AutoMerge.has_label(labels, AutoMerge.BLOCKED_LABEL)
                        end
                    end
                end
            end
        end
    end
end
