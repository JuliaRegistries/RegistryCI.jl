using Dates: Day, UTC, now
using RegistryCI: TagBot
using SimpleMock: called_with, mock, ncalls

const TB = TagBot
const GH = TB.GH

TB.AUTH[] = GH.OAuth2("abcdef")

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

@testset "is_tagbot_enabled" begin
    mock(TB.clone_repo => repo -> joinpath(@__DIR__, "repos", repo)) do _clone
        @test !TB.is_tagbot_enabled("no_actions")
        @test !TB.is_tagbot_enabled("no_tagbot")
        @test TB.is_tagbot_enabled("yes_tagbot")
    end
end

@testset "get_repo_notification_issue" begin
end

@testset "notification_body" begin
    base = "Triggering TagBot for merged registry pull request"
    @test TB.notification_body(Dict()) == base
    event = Dict("pull_request" => Dict("html_url" => "foo"))
    @test TB.notification_body(event) == "$base: foo"
end

@testset "notify" begin
    mock(GH.create_comment) do cc
        TB.notify("repo", "issue", "body")
        @test called_with(cc, "repo", "issue", :issue; auth=TB.AUTH[], params=(; body="body",))
    end
end

@testset "collect_pulls" begin
    pulls = [
        GH.PullRequest(),
        GH.PullRequest(; merged_at=now(UTC)),
        GH.PullRequest(; merged_at=now(UTC) - Day(2)),
    ]
    mock(GH.pull_requests => Mock((pulls, Dict()))) do prs
        @test TB.collect_pulls("A/B") == [pulls[2]]
        @test ncalls(prs) == 1
    end
    mock(GH.pull_requests => Mock([([], Dict("next" => "a")), ([], Dict())])) do prs
        TB.collect_pulls("A/B")
        @test ncalls(prs) == 2
    end
end

@testset "tag_exists" begin
    mock(GH.tag) do tag
        @test TB.tag_exists("A/B", "v1.2.3")
        @test called_with(tag, "A/B", "v1.2.3"; auth=TB.AUTH[])
    end
    @test !TB.tag_exists("ThisWillThrow/AnError", "v4.5.6")
end


@testset "handle_merged_pull_request" begin
end

@testset "handle_cron" begin
end

@testset "maybe_notify" begin
    # mock(
    #     TB.clone_repo => repo -> joinpath(@__DIR__, "repos", repo),
    #     TB.tag_exists => (r, v) -> true,
    #     TB.get_repo_notification_issue,
    #     TB.notify,
    # ) do _clone, tag_exists, get_issue, notify
    #     @test_logs match_mode=:any (:info, r"not enabled") TB.maybe_notify((), "no_tagbot", "0")
    #     @test ncalls(get_issue) == 0
    #     @test_logs match_mode=:any (:info, r"already exists") TB.maybe_notify((), "yes_tagbot", "1"; check=true)
    #     @test ncalls(get_issue) == 0
    #     TB.maybe_notify(Dict(), "yes_tagbot", "2")
    #     @test called_with(get_issue, "yes_tagbot")
    # end
end
