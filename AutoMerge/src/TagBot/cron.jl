is_cron(event) = get(ENV, "GITHUB_EVENT_NAME", "") in ("schedule", "workflow_dispatch")

function handle_cron(event)
    pulls = collect_pulls(ENV["GITHUB_REPOSITORY"])
    repos_versions = map(pull -> repo_and_version_of_pull_request_body(pull.body), pulls)
    filter!(rv -> first(rv) !== nothing, repos_versions)
    unique!(first, repos_versions)  # Send at most one notification per repo.
    for (repo, version) in repos_versions
        maybe_notify(event, repo, version; cron=true)
    end
end

function collect_pulls(repo)
    acc = GH.PullRequest[]
    kwargs = Dict(
        :auth => AUTH[],
        :page_limit => 1,
        :params => (; state="closed", sort="updated", direction="desc", per_page=100),
    )
    done = false
    while !done
        pulls, pages = get_pulls(repo; kwargs...)
        for pull in pulls
            pull.merged_at === nothing && continue
            if now(UTC) - pull.merged_at < Day(3)
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

function get_pulls(args...; kwargs...)
    return retry(
        () -> GH.pull_requests(args...; kwargs...);
        check=(s, e) -> occursin("Server error", e.msg),
        delays=ExponentialBackOff(; n=5, first_delay=1, factor=2),
    )()
end
