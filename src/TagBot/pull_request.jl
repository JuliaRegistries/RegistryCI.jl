is_merged_pull_request(event) = get(get(event, "pull_request", Dict()), "merged", false)

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
