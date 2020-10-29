using BrokenRecord: BrokenRecord, HTTP, playback
using Dates: DateTime
using RegistryCI: TagBot
using SimpleMock: Mock, called_with, mock
using Test: @test, @testset, @test_logs

const TB = TagBot
const GH = TB.GH

TB.AUTH[] = GH.OAuth2(get(ENV, "GITHUB_TOKEN", "abcdef"))
BrokenRecord.configure!(;
    path=joinpath(@__DIR__, "cassettes"),
    ignore_headers=["Authorization"],
)

@testset "is_merged_pull_request" begin
    @test !TB.is_merged_pull_request(Dict())
    @test !TB.is_merged_pull_request(Dict("pull_request" => Dict("merged" => false)))
    @test TB.is_merged_pull_request(Dict("pull_request" => Dict("merged" => true)))
end

@testset "is_cron" begin
    withenv(() -> @test(!TB.is_cron(())), "GITHUB_EVENT_NAME" => nothing)
    withenv(() -> @test(!TB.is_cron(())), "GITHUB_EVENT_NAME" => "pull_request")
    withenv(() -> @test(TB.is_cron(())), "GITHUB_EVENT_NAME" => "schedule")
end

@testset "repo_and_version_of_pull_request" begin
    body(url) = """
        - Repository: $url
        - Version: v1.2.3
        """
    github = body("https://github.com/Foo/Bar")
    @test TB.repo_and_version_of_pull_request_body(github) == ("Foo/Bar", "v1.2.3")
    ssh = body("git@github.com:Foo/Bar.git")
    @test TB.repo_and_version_of_pull_request_body(ssh) == ("Foo/Bar", "v1.2.3")
    gitlab = body("https://gitlab.com/Foo/Bar")
    @test TB.repo_and_version_of_pull_request_body(gitlab) == (nothing, "v1.2.3")
end

@testset "clone_repo" begin
    mock(run, mktempdir => Mock("a")) do run, _mktempdir
        @test TB.clone_repo("A") == "a"
        @test called_with(run, `git clone --depth=1 https://github.com/A a`)
    end
end

@testset "is_tagbot_enabled" begin
    mock(TB.clone_repo => repo -> joinpath(@__DIR__, "repos", repo)) do _clone
        @test !TB.is_tagbot_enabled("no_actions")
        @test !TB.is_tagbot_enabled("no_tagbot")
        @test TB.is_tagbot_enabled("yes_tagbot")
    end
end

@testset "get_repo_notification_issue" begin
    repo = "christopher-dG/TestRepo"
    playback("get_repo_notification_issue.bson") do
        @test_logs (:info, "Creating new notification issue") begin
            issue = TB.get_repo_notification_issue(repo)
            @test issue.number == 4
        end
        @test_logs (:info, "Found existing notification issue") begin
            issue = TB.get_repo_notification_issue(repo)
            @test issue.number == 4
        end
    end
end

@testset "notification_body" begin
    base = "Triggering TagBot for merged registry pull request"
    @test TB.notification_body(Dict()) == base
    event = Dict("pull_request" => Dict("html_url" => "foo"))
    @test TB.notification_body(event) == "$base: foo"
end

@testset "notify" begin
    playback("notify.bson") do
        comment = TB.notify("christopher-dG/TestRepo", 4, "test notification")
        @test comment.body == "test notification"
    end
end

@testset "collect_pulls" begin
    pulls = playback("collect_pulls.bson") do
        mock(TB.my_now => Mock(DateTime(2020, 10, 28, 21, 28))) do _now
            TB.collect_pulls("JuliaRegistries/General")
        end
    end
    @test length(pulls) == 55
    @test all(map(p -> p.merged_at !== nothing, pulls))
end

@testset "tag_exists" begin
    playback("tag_exists.bson") do
        @test TB.tag_exists("JuliaRegistries/RegistryCI.jl", "v0.1.0")
        @test !TB.tag_exists("JuliaRegistries/RegistryCI.jl", "v0.0.0")
    end
end

@testset "maybe_notify" begin
    @test_logs match_mode=:any (:info, r"not enabled") begin
        mock(TB.is_tagbot_enabled => Mock(false)) do _is_tagbot_enabled
            TB.maybe_notify((), "repo", "v")
        end
    end
    @test_logs match_mode=:any (:info, r"already exists") begin
        mock(TB.is_tagbot_enabled => Mock(true), TB.tag_exists => Mock(true)) do ite, te
            TB.maybe_notify((), "repo", "v"; check_tag=true)
        end
    end
    mock(
        TB.is_tagbot_enabled => Mock(true),
        TB.get_repo_notification_issue => Mock(1),
        TB.notify,
    ) do is_enabled, get_issue, notify
        TB.maybe_notify(Dict(), "repo", "v")
        @test called_with(is_enabled, "repo")
        @test called_with(get_issue, "repo")
        msg = "Triggering TagBot for merged registry pull request"
        @test called_with(notify, "repo", 1, msg)
    end
end
