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
    pulls, pages = get_initial_pulls(repo; kwargs...)
    done = false
    while true
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
            pulls, pages = get_pulls(repo; kwargs...)
        else
            done = true
        end
        done && break
    end
    return acc
end

is_server_error(e) = hasproperty(e, :msg) && occursin("Server error", e.msg)

function get_initial_pulls(
    args...;
    retry_check=is_server_error,
    retry_delays=ExponentialBackOff(; n=10, first_delay=1, factor=2),
    kwargs...,
)
    return retry(
        () -> get_pulls(args...; kwargs...);
        check=(state, exception) -> retry_check(exception),
        delays=retry_delays,
    )()
end

function get_pulls(args...; kwargs...)
    return GH.pull_requests(args...; kwargs...)
end
