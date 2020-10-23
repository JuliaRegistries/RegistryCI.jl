module TagBot

using GitHub: GitHub
using JSON: JSON

const GH = GitHub

const ISSUE_TITLE = "TagBot trigger issue"
const ISSUE_BODY = "This issue is used to trigger TagBot; feel free to unsubscribe from it."

const AUTH = Ref{GH.OAuth2}()
const USER = Ref{String}()

function main()
    AUTH[] = GH.authenticate(ENV["GITHUB_TOKEN"])
    event = JSON.parse(read(ENV["GITHUB_EVENT_PATH"], String))
    if is_merged_pull_request(event)
        handle_merged_pull_request(event)
    elseif is_cron(event)
        handle_cron(event)
    end
end

is_merged_pull_request(event) = event["pull_request"]["merged"]

is_cron(event) = get(ENV, "GITHUB_EVENT_NAME", "") == "schedule"

function repo_of_pull_request_body(body)
    m = match(r"Repository: .*github\.com[:/](.*)", body)
    return m === nothing ? nothing : m[1]
end

function clone_repo(repo)
    dir = mktempdir()
    run(`git clone --depth=1 https://github.com/$repo $dir`)
    return dir
end

function is_tagbot_enabled(repo; dir=nothing)
    if dir === nothing
        dir = clone_repo(repo)
    end
    workflows = joinpath(dir, ".github", "workflows")
    isdir(workflows) || return false
    for workflow in readdir(workflows)
        contents = read(joinpath(workflows, workflow), String)
        occursin("JuliaRegistries/TagBot", contents) && return true
    end
    return false
end

function get_repo_notification_issue(repo)
    # TODO: Populate `USER` (how?) and use it as `creator`.
    params = (; creator="JuliaTagBot", state="closed")
    issues, _ = GH.issues(repo; auth=AUTH[], params=params)
    return if isempty(issues)
        @info "Creating new notification issue"
        params = (; title=ISSUE_TITLE, body=ISSUE_BODY)
        issue = GH.create_issue(repo; auth=AUTH[], params=params)
        GH.edit_issue(repo, issue; auth=AUTH[], params=(; state="closed",))
        issue
    else
        @info "Found existing notification issue"
        issues[1]
    end
end

function notification_body(event)
    url = event["pull_request"]["html_url"]
    return "Triggering TagBot for merged registry pull request: $url"
end

function notify(repo, issue, body)
    GH.create_comment(repo, issue, :issue; auth=AUTH[], params=(; body=body,))
end

function handle_merged_pull_request(event)
    repo = repo_of_pull_request_body(event["pull_request"]["body"])
    if repo === nothing
        @info "Failed to parse GitHub repository from merge request"
        return
    end
    @info "Processing merged PR for $repo"
    if !is_tagbot_enabled(repo)
        @info "TagBot is not enabled on $repo"
        return
    end
    issue = get_repo_notification_issue(repo)
    body = notification_body(event)
    notify(repo, issue, body)
end

function handle_cron(event)
end

end
