using BrokenRecord: BrokenRecord, HTTP, playback
using Dates: DateTime, Day, UTC, now
using RegistryCI: TagBot
using SimpleMock: Mock, called_with, mock
using Test: @test, @testset, @test_logs

const TB = TagBot
const GH = TB.GH

TB.AUTH[] = GH.OAuth2(get(ENV, "GITHUB_TOKEN", "abcdef"))
TB.TAGBOT_USER[] = "JuliaTagBot"
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

@testset "tagbot_file" begin
    playback("tagbot_file.bson") do
        @test TB.tagbot_file("Repo/DoesNotExist") === nothing
        @test TB.tagbot_file("torvalds/linux") === nothing
        path, contents = TB.tagbot_file("JuliaRegistries/RegistryCI.jl")
        @test path == ".github/workflows/TagBot.yml"
        @test occursin("JuliaRegistries/TagBot", contents)
        @test TB.tagbot_file("JuliaWeb/HTTP.jl") !== nothing
        @test TB.tagbot_file("JuliaWeb/HTTP.jl"; issue_comments=true) === nothing
    end
end

@testset "get_repo_notification_issue" begin
    playback("get_repo_notification_issue.bson") do
        @test_logs match_mode=:any (:info, "Creating new notification issue") begin
            issue = TB.get_repo_notification_issue("christopher-dG/TestRepo")
            @test issue.number == 11
        end
        @test_logs match_mode=:any (:info, "Found existing notification issue") begin
            issue = TB.get_repo_notification_issue("christopher-dG/TestRepo")
            @test issue.number == 11
        end
    end
end

@testset "notification_body" begin
    base = "Triggering TagBot for merged registry pull request"
    @test TB.notification_body(Dict()) == base
    event = Dict("pull_request" => Dict("html_url" => "foo"))
    @test TB.notification_body(event) == "$base: foo"
    @test occursin("extra notification", TB.notification_body(event; cron=true))
end

@testset "notify" begin
    playback("notify.bson") do
        comment = TB.notify("christopher-dG/TestRepo", 4, "test notification")
        @test comment.body == "test notification"
    end
end

@testset "collect_pulls" begin
    PR = GH.PullRequest
    prs = [
        [PR(), PR(; merged_at=now(UTC))],
        [PR(; merged_at=now(UTC) - Day(2)), PR(; merged_at=now(UTC) - Day(4))],
    ]
    pages = [Dict("next" => "abc"), Dict()]
    pulls = mock(GH.pull_requests => Mock(collect(zip(prs, pages)))) do _prs
        TB.collect_pulls("JuliaRegistries/General")
    end
    @test pulls == [prs[1][2], prs[2][1]]
end

@testset "tag_exists" begin
    playback("tag_exists.bson") do
        @test TB.tag_exists("JuliaRegistries/RegistryCI.jl", "v0.1.0")
        @test !TB.tag_exists("JuliaRegistries/RegistryCI.jl", "v0.0.0")
    end
end

@testset "maybe_notify" begin
    @test_logs match_mode=:any (:info, r"not enabled") begin
        mock(TB.tagbot_file => Mock(nothing)) do _tf
            TB.maybe_notify((), "repo", "v")
        end
    end
    @test_logs match_mode=:any (:info, r"already exists") begin
        mock(TB.tagbot_file => Mock(true), TB.tag_exists => Mock(true)) do tf, te
            TB.maybe_notify((), "repo", "v"; cron=true)
        end
    end
    mock(
        TB.tagbot_file => Mock(("path", "contents")),
        TB.get_repo_notification_issue => Mock(1),
        TB.should_fixup => Mock(false),
        TB.notification_body => Mock("foo"),
        TB.notify,
    ) do tagbot_file, get_issue, should_fixup, body, notify
        TB.maybe_notify(Dict(), "repo", "v"; cron=true)
        @test called_with(tagbot_file, "repo")
        @test called_with(get_issue, "repo")
        @test called_with(should_fixup, "repo", 1)
        @test called_with(notify, "repo", 1, "foo")
    end
end

@testset "should_fixup" begin
    mock(
        TB.fixup_comment_exists => Mock([false, true, true, true]),
        TB.fixup_done => Mock([true, false, false]),
        TB.tagbot_file => Mock([("path", "contents"), nothing]),
    ) do fce, fd, tf
        @test !TB.should_fixup("repo", 1)
        @test !TB.should_fixup("repo", 2)
        @test !TB.should_fixup("repo", 3)
        @test TB.should_fixup("repo", 4)
    end
end

@testset "get_fork" begin
    playback("get_fork.bson") do
        mock(now => tz -> DateTime(2020, 11, 5, 19, 2)) do _now
            fork = TB.get_fork("christopher-dG/TestRepo")
            @test fork isa GH.Repo
        end
    end
end

@testset "open_fixup_pr" begin
    playback("open_fixup_pr.bson") do
        fork = GH.repo("JuliaTagBot/TestRepo"; auth=TB.AUTH[])
        pr = TB.open_fixup_pr("christopher-dG/TestRepo"; branch="abc", fork=fork)
        @test pr.number == 10
    end
end

@testset "fixup_comment_exists" begin
    playback("fixup_comment_exists.bson") do
        no = GH.issue("christopher-dG/TestRepo", 7; auth=TB.AUTH[])
        yes = GH.issue("christopher-dG/TestRepo", 8; auth=TB.AUTH[])
        @test !TB.fixup_comment_exists("christopher-dG/TestRepo",no)
        @test TB.fixup_comment_exists("christopher-dG/TestRepo", yes)
    end
end

@testset "is_fixup_trigger" begin
    comment = GH.Comment(Dict("user" => Dict("login" => "foo"), "body" => "foo"))
    @test !TB.is_fixup_trigger(comment)
    comment.body = "foo bar tagbot fix baz"
    @test TB.is_fixup_trigger(comment)
    comment.user.login = TB.TAGBOT_USER[]
    @test !TB.is_fixup_trigger(comment)
end

@testset "fixup_done" begin
    playback("fixup_done.bson") do
        @test !TB.fixup_done("JuliaWeb/HTTP.jl")
        @test TB.fixup_done("christopher-dG/TestRepo")
    end
end
