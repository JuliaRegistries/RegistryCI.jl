is_cron(event) = get(ENV, "GITHUB_EVENT_NAME", "") == "schedule"

function handle_cron(event)
    pulls = collect_pulls(event["repository"]["full_name"])
    repos_versions = map(pull -> repo_and_version_of_pull_request_body(pull.body), pulls)
    filter!(rv -> first(rv) !== nothing, repos_versions)
    unique!(first, repos_versions)  # Send at most one notification per repo.
    for (repo, version) in repos_versions
        maybe_notify(event, repo, version; check_tag=true)
    end
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
