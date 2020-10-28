module TagBot

using Dates: Day, UTC, now

using GitHub: GitHub
using JSON: JSON

const GH = GitHub

const AUTH = Ref{GH.OAuth2}()
const ISSUE_TITLE = "TagBot trigger issue"
const ISSUE_BODY = """
This issue is used to trigger TagBot; feel free to unsubscribe.

If you haven't already, you should update your `TagBot.yml` to include issue comment triggers.
Please see [this post on Discourse](TODO: Discourse URL) for instructions and more details.
"""

function main()
    AUTH[] = GH.authenticate(ENV["GITHUB_TOKEN"])
    event = JSON.parse(read(ENV["GITHUB_EVENT_PATH"], String))
    if is_merged_pull_request(event)
        handle_merged_pull_request(event)
    elseif is_cron(event)
        handle_cron(event)
    end
end

is_merged_pull_request(event) = get(get(event, "pull_request", Dict()), "merged", false)

is_cron(event) = get(ENV, "GITHUB_EVENT_NAME", "") == "schedule"

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

function clone_repo(repo)
    dir = mktempdir()
    run(`git clone --depth=1 https://github.com/$repo $dir`)
    return dir
end

function is_tagbot_enabled(repo)
    # TODO: Traversing the file tree should be possible via GitHub API,
    # but GitHub.jl doesn't seem capable.
    dir = clone_repo(repo)
    workflows = joinpath(dir, ".github", "workflows")
    isdir(workflows) || return false
    for workflow in readdir(workflows)
        contents = read(joinpath(workflows, workflow), String)
        occursin("JuliaRegistries/TagBot", contents) && return true
    end
    return false
end

function get_repo_notification_issue(repo)
    # TODO: Get the authenticated user (how?) and use it as `creator`.
    params = (; creator="JuliaTagBot", state="closed")
    issues, _ = GH.issues(repo; auth=AUTH[], params=params)
    return if isempty(issues)
        @info "Creating new notification issue"
        params = (; title=ISSUE_TITLE, body=ISSUE_BODY)
        issue = GH.create_issue(repo; auth=AUTH[], params=params)
        GH.edit_issue(repo, issue; auth=AUTH[], params=(; state="closed"))
        issue
    else
        @info "Found existing notification issue"
        issues[1]
    end
end

function notification_body(event)
    url = get(get(event, "pull_request", Dict()), "html_url", "")
    body = "Triggering TagBot for merged registry pull request"
    return isempty(url) ? body : "$body: $url"
end

function notify(repo, issue, body)
    return GH.create_comment(repo, issue, :issue; auth=AUTH[], params=(; body=body))
end

function handle_merged_pull_request(event)
    number = event["pull_request"]["number"]
    @info "Processing pull request $number"
    repo, version = repo_and_version_of_pull_request_body(event["pull_request"]["body"])
    if repo === nothing
        @info "Failed to parse GitHub repository from pull request"
        return
    end
    maybe_notify(event, repo, version)
end

function collect_pulls(repo)
    acc = GH.PullRequest[]
    params = (; state="closed", sort="updated", direction="desc")
    kwargs = Dict(:auth => AUTH[], :params => params, :page_limit => 1)
    done = false
    while !done
        pulls, pages = GH.pull_requests(repo; kwargs...)
        for pull in pulls
            pull.merged_at === nothing && continue
            if now(UTC) - pull.merged_at < Day(1)
                push!(acc, pull)
            else
                done = true
            end
        end
        if haskey(pages, "next")
            delete!(kwargs, :params)
            kwargs[:start_page] = pages["next"]
        else
            done = true
        end
    end
    return acc
end

function tag_exists(repo, version)
    return try
        GH.tag(repo, version; auth=AUTH[])
        true
    catch e
        if !occursin("404", string(e))
            @warn "Unknown error when checking for existing tag" ex=(e, catch_backtrace())
        end
        false
    end
end

function handle_cron(event)
    pulls = collect_pulls(event["repository"]["full_name"])
    repos_versions = map(pull -> repo_and_version_of_pull_request_body(pull.body), pulls)
    filter!(rv -> first(rv) !== nothing, repos_versions)
    unique!(first, repos_versions)  # Send at most one notification per repo.
    for (repo, version) in repos_versions
        maybe_notify(event, repo, version; check_tag=true)
    end
end

function maybe_notify(event, repo, version; check_tag=false)
    @info "Processing version $version of $repo"
    if !is_tagbot_enabled(repo)
        @info "TagBot is not enabled on $repo"
        return
    end
    if check_tag && tag_exists(repo, version)
        @info "Tag $version already exists for $repo"
        return
    end
    issue = get_repo_notification_issue(repo)
    body = notification_body(event)
    notify(repo, issue, body)
end

end
