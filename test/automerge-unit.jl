using Dates
using GitHub
using JSON
using Pkg
using Printf
using RegistryCI
using Test
using TimeZones

const AutoMerge = RegistryCI.AutoMerge

@testset "Guidelines for new packages" begin
    @testset "Normal capitalization" begin
        @test AutoMerge.meets_normal_capitalization("Zygote")[1]
        @test AutoMerge.meets_normal_capitalization("Zygote")[1]
        @test !AutoMerge.meets_normal_capitalization("HTTP")[1]
        @test !AutoMerge.meets_normal_capitalization("HTTP")[1]
    end
    @testset "Not too short - at least five letters" begin
        @test AutoMerge.meets_name_length("Zygote")[1]
        @test AutoMerge.meets_name_length("Zygote")[1]
        @test !AutoMerge.meets_name_length("Flux")[1]
        @test !AutoMerge.meets_name_length("Flux")[1]
    end
    @testset "Standard initial version number" begin
        @test AutoMerge.meets_standard_initial_version_number(v"0.0.1")[1]
        @test AutoMerge.meets_standard_initial_version_number(v"0.1.0")[1]
        @test AutoMerge.meets_standard_initial_version_number(v"1.0.0")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"0.0.2")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"0.1.1")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"0.2.0")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"1.0.1")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"1.1.0")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"1.1.1")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"2.0.0")[1]
    end
    @testset "Repo URL ends with /name.jl.git where name is the package name" begin
        @test AutoMerge.url_has_correct_ending("https://github.com/FluxML/Flux.jl.git", "Flux")[1]
        @test !AutoMerge.url_has_correct_ending("https://github.com/FluxML/Flux.jl", "Flux")[1]
        @test !AutoMerge.url_has_correct_ending("https://github.com/FluxML/Zygote.jl.git", "Flux")[1]
        @test !AutoMerge.url_has_correct_ending("https://github.com/FluxML/Zygote.jl", "Flux")[1]
    end
end

@testset "Guidelines for new versions" begin
    @testset "Sequential version number" begin
        @test AutoMerge.meets_sequential_version_number(v"0.0.1", v"0.0.2")[1]
        @test AutoMerge.meets_sequential_version_number(v"0.1.0", v"0.1.1")[1]
        @test AutoMerge.meets_sequential_version_number(v"0.1.0", v"0.2.0")[1]
        @test AutoMerge.meets_sequential_version_number(v"1.0.0", v"1.0.1")[1]
        @test AutoMerge.meets_sequential_version_number(v"1.0.0", v"1.1.0")[1]
        @test AutoMerge.meets_sequential_version_number(v"1.0.0", v"2.0.0")[1]
        @test !AutoMerge.meets_sequential_version_number(v"0.0.1", v"0.0.3")[1]
        @test !AutoMerge.meets_sequential_version_number(v"0.1.0", v"0.3.0")[1]
        @test !AutoMerge.meets_sequential_version_number(v"1.0.0", v"1.0.2")[1]
        @test !AutoMerge.meets_sequential_version_number(v"1.0.0", v"1.2.0")[1]
        @test !AutoMerge.meets_sequential_version_number(v"1.0.0", v"3.0.0")[1]
        @test AutoMerge.meets_sequential_version_number(v"0.1.1", v"0.2.0")[1]
        @test AutoMerge.meets_sequential_version_number(v"0.1.2", v"0.2.0")[1]
        @test AutoMerge.meets_sequential_version_number(v"0.1.3", v"0.2.0")[1]
        @test AutoMerge.meets_sequential_version_number(v"1.0.1", v"1.1.0")[1]
        @test AutoMerge.meets_sequential_version_number(v"1.0.2", v"1.1.0")[1]
        @test AutoMerge.meets_sequential_version_number(v"1.0.3", v"1.1.0")[1]
        @test !AutoMerge.meets_sequential_version_number(v"0.1.1", v"0.2.1")[1]
        @test !AutoMerge.meets_sequential_version_number(v"0.1.2", v"0.2.2")[1]
        @test !AutoMerge.meets_sequential_version_number(v"1.0.1", v"1.1.1")[1]
        @test !AutoMerge.meets_sequential_version_number(v"1.0.3", v"1.2.0")[1]
        @test !AutoMerge.meets_sequential_version_number(v"1.0.3", v"1.2.1")[1]
        @test !AutoMerge.meets_sequential_version_number(v"1.0.3", v"1.1.1")[1]
        @test !AutoMerge.meets_sequential_version_number(v"1.0.0", v"2.0.1")[1]
        @test !AutoMerge.meets_sequential_version_number(v"1.0.0", v"2.1.0")[1]
        @test !AutoMerge.meets_sequential_version_number(v"1.0.0", v"2.1.0")[1]
    end
    @testset "Patch releases cannot narrow Julia compat" begin
        r1 = Pkg.Types.VersionRange("1.3-1.7")
        r2 = Pkg.Types.VersionRange("1.4-1.7")
        r3 = Pkg.Types.VersionRange("1.3-1.6")
        @test AutoMerge.range_did_not_narrow(r1, r1)[1]
        @test AutoMerge.range_did_not_narrow(r2, r2)[1]
        @test AutoMerge.range_did_not_narrow(r3, r3)[1]
        @test AutoMerge.range_did_not_narrow(r2, r1)[1]
        @test AutoMerge.range_did_not_narrow(r3, r1)[1]
        @test !AutoMerge.range_did_not_narrow(r1, r2)[1]
        @test !AutoMerge.range_did_not_narrow(r1, r3)[1]
        @test !AutoMerge.range_did_not_narrow(r2, r3)[1]
        @test !AutoMerge.range_did_not_narrow(r3, r2)[1]
    end
end

@testset "Unit tests" begin
    @testset "assert.jl" begin
        @test nothing == @test_nowarn AutoMerge.always_assert(1 == 1)
        @test_throws AutoMerge.AlwaysAssertionError AutoMerge.always_assert(1 == 2)
    end
end

@testset "CIService unit testing" begin
    @testset "Travis CI" begin
        # pull request build
        withenv("TRAVIS_BRANCH" => "master",
                "TRAVIS_EVENT_TYPE" => "pull_request",
                "TRAVIS_PULL_REQUEST" => "42",
                "TRAVIS_PULL_REQUEST_SHA" => "abc123",
                "TRAVIS_BUILD_DIR" => "/tmp/clone") do
            cfg = AutoMerge.TravisCI()
            @test AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="retsam")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
            @test AutoMerge.pull_request_number(cfg) == 42
            @test AutoMerge.current_pr_head_commit_sha(cfg) == "abc123"
            @test AutoMerge.directory_of_cloned_registry(cfg) == "/tmp/clone"
        end
        # merge build with cron
        withenv("TRAVIS_BRANCH" => "master",
                "TRAVIS_EVENT_TYPE" => "cron",
                "TRAVIS_PULL_REQUEST" => "false",
                "TRAVIS_PULL_REQUEST_SHA" => "abc123",
                "TRAVIS_BUILD_DIR" => "/tmp/clone") do
            cfg = AutoMerge.TravisCI()
            @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="retsam")
            @test !AutoMerge.conditions_met_for_merge_build(AutoMerge.TravisCI(enable_cron_builds=false); master_branch="master")
            @test AutoMerge.current_pr_head_commit_sha(cfg) == "abc123"
            @test AutoMerge.directory_of_cloned_registry(cfg) == "/tmp/clone"
        end
        # merge build with api
        withenv("TRAVIS_BRANCH" => "master",
                "TRAVIS_EVENT_TYPE" => "api",
                "TRAVIS_PULL_REQUEST" => "false",
                "TRAVIS_PULL_REQUEST_SHA" => "abc123",
                "TRAVIS_BUILD_DIR" => "/tmp/clone") do
            cfg = AutoMerge.TravisCI()
            @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="retsam")
            @test !AutoMerge.conditions_met_for_merge_build(AutoMerge.TravisCI(enable_api_builds=false); master_branch="master")
            @test AutoMerge.current_pr_head_commit_sha(cfg) == "abc123"
            @test AutoMerge.directory_of_cloned_registry(cfg) == "/tmp/clone"
        end
        # neither pull request nor merge build
        withenv("TRAVIS_BRANCH" => nothing,
                "TRAVIS_EVENT_TYPE" => nothing) do
            cfg = AutoMerge.TravisCI()
            @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
        end
    end

    @testset "GitHub Actions" begin; mktemp() do file, io
        # mimic the workflow file for GitHub Actions
        workflow = Dict("pull_request" => Dict("head" => Dict("sha" => "abc123")))
        JSON.print(io, workflow); close(io)

        # pull request build
        withenv("GITHUB_REF" => "refs/pull/42/merge",
                "GITHUB_EVENT_NAME" => "pull_request",
                "GITHUB_SHA" => "123abc", # "wrong", should be taken from workflow file
                "GITHUB_EVENT_PATH" => file,
                "GITHUB_WORKSPACE" => "/tmp/clone") do
            cfg = AutoMerge.GitHubActions()
            @test AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test_broken !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="retsam")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
            @test AutoMerge.pull_request_number(cfg) == 42
            @test AutoMerge.current_pr_head_commit_sha(cfg) == "abc123"
            @test AutoMerge.directory_of_cloned_registry(cfg) == "/tmp/clone"
        end
        # merge build with schedule: cron
        withenv("GITHUB_REF" => "refs/heads/master",
                "GITHUB_EVENT_NAME" => "schedule",
                "GITHUB_SHA" => "123abc",
                "GITHUB_WORKSPACE" => "/tmp/clone") do
            cfg = AutoMerge.GitHubActions()
            @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="retsam")
            @test !AutoMerge.conditions_met_for_merge_build(AutoMerge.GitHubActions(enable_cron_builds=false); master_branch="master")
            @test AutoMerge.directory_of_cloned_registry(cfg) == "/tmp/clone"
        end
        # neither pull request nor merge build
        withenv("GITHUB_REF" => nothing,
                "GITHUB_EVENT_NAME" => nothing) do
            cfg = AutoMerge.GitHubActions()
            @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
        end
    end end

    @testset "auto detection" begin
        withenv("TRAVIS_REPO_SLUG" => "JuliaRegistries/General",
                "GITHUB_REPOSITORY" => nothing) do
            @test AutoMerge.auto_detect_ci_service() == AutoMerge.TravisCI()
            @test AutoMerge.auto_detect_ci_service(env=ENV) == AutoMerge.TravisCI()
        end
        withenv("TRAVIS_REPO_SLUG" => nothing,
                "GITHUB_REPOSITORY" => "JuliaRegistries/General") do
            @test AutoMerge.auto_detect_ci_service() == AutoMerge.GitHubActions()
            @test AutoMerge.auto_detect_ci_service(env=ENV) == AutoMerge.GitHubActions()
        end
    end
end
