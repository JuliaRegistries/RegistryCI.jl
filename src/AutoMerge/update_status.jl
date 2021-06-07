function update_status(data::GitHubAutoMergeData; kwargs...)
    if data.read_only
        @info "`read_only` mode; skipping updating the status"
        return nothing
    end
    return my_retry(
        () -> GitHub.create_status(
            data.api,
            data.registry,
            data.current_pr_head_commit_sha;
            auth=data.auth,
            params=Dict(kwargs...),
        ),
    )
end
