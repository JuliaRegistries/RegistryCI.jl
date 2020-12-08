module TagBot

using Base64: base64decode, base64encode
using Dates: Day, Minute, UTC, now
using Random: randstring
using SHA: sha1

using GitHub: GitHub
using JSON: JSON

const GH = GitHub

const AUTH = Ref{GH.OAuth2}()
const TAGBOT_USER = Ref{String}()
const ISSUE_TITLE = "TagBot trigger issue"
const ISSUE_BODY = """
This issue is used to trigger TagBot; feel free to unsubscribe.

If you haven't already, you should update your `TagBot.yml` to include issue comment triggers.
Please see [this post on Discourse](https://discourse.julialang.org/t/ann-required-updates-to-tagbot-yml/49249) for instructions and more details.

If you'd like for me to do this for you, comment `TagBot fix` on this issue.
I'll open a PR within a few hours, please be patient!
"""
const CRON_ADDENDUM = """


This extra notification is being sent because I expected a tag to exist by now, but it doesn't.
You may want to check your TagBot configuration to ensure that it's running, and if it is, check the logs to make sure that there are no errors.
"""

include("cron.jl")
include("pull_request.jl")
include("fixup.jl")

function main()
    AUTH[] = GH.authenticate(ENV["GITHUB_TOKEN"])
    TAGBOT_USER[] = GH.whoami(; auth=AUTH[]).login
    event = JSON.parse(read(ENV["GITHUB_EVENT_PATH"], String))
    if is_merged_pull_request(event)
        handle_merged_pull_request(event)
    elseif is_cron(event)
        handle_cron(event)
    end
end

function repo_and_version_of_pull_request_body(body)
    if occursin("JLL package", body)
        @info "Skipping JLL package registration"
        return nothing, nothing
    end
    m = match(r"Repository: .*github\.com[:/](.*)", body)
    repo = m === nothing ? nothing : strip(m[1])
    repo !== nothing && endswith(repo, ".git") && (repo = repo[1:end-4])
    m = match(r"Version: (.*)", body)
    version = m === nothing ? nothing : strip(m[1])
    return repo, version
end

function tagbot_file(repo; issue_comments=false)
    files, pages = try
        GH.directory(repo, ".github/workflows"; auth=AUTH[])
    catch e
        occursin("404", e.msg) && return nothing
        rethrow()
    end
    for f in files
        f.typ == "file" || continue
        file = GH.file(repo, f.path; auth=AUTH[])
        contents = String(base64decode(file.content))
        if occursin("JuliaRegistries/TagBot", contents)
            issue_comments && !occursin("issue_comment", contents) && continue
            return f.path, contents
        end
    end
    return nothing
end

function get_repo_notification_issue(repo)
    issues, _ = GH.issues(repo; auth=AUTH[], params=(;
        creator=TAGBOT_USER[],
        state="closed",
    ))
    filter!(x -> x.pull_request === nothing, issues)
    return if isempty(issues)
        @info "Creating new notification issue"
        issue = try
            GH.create_issue(repo; auth=AUTH[], params=(;
                title=ISSUE_TITLE,
                body=ISSUE_BODY,
            ))
        catch e
            occursin("Issues are disabled", e.msg) || rethrow()
            @info "Issues are disabled on $repo"
            return nothing
        end
        GH.edit_issue(repo, issue; auth=AUTH[], params=(; state="closed"))
        issue
    else
        @info "Found existing notification issue"
        issues[1]
    end
end

function notification_body(event; cron=false)
    url = get(get(event, "pull_request", Dict()), "html_url", "")
    body = "Triggering TagBot for merged registry pull request"
    isempty(url) || (body = "$body: $url")
    cron && (body *= CRON_ADDENDUM)
    return body
end

function notify(repo, issue, body)
    return GH.create_comment(repo, issue, :issue; auth=AUTH[], params=(; body=body))
end

function tag_exists(repo, version)
    return try
        GH.tag(repo, version; auth=AUTH[])
        true
    catch e
        if !occursin("404", e.msg)
            @warn "Unknown error when checking for existing tag" ex=(e, catch_backtrace())
        end
        false
    end
end

function maybe_notify(event, repo, version; cron=false)
    @info "Processing version $version of $repo"
    if tagbot_file(repo) === nothing
        @info "TagBot is not enabled on $repo"
        return
    end
    if cron && tag_exists(repo, version)
        @info "Tag $version already exists for $repo"
        return
    end
    issue = get_repo_notification_issue(repo)
    if issue === nothing
        @info "Couldn't get notification issue for $repo"
        return
    end
    if cron && should_fixup(repo, issue)
        @info "Opening fixup PR for $repo"
        open_fixup_pr(repo)
    end
    body = notification_body(event; cron=cron)
    notify(repo, issue, body)
end

end
