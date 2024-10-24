using GitHub: GitHub

const OVERRIDE_BLOCKS_LABEL = "Override AutoMerge: ignore blocking comments"
const BLOCKED_LABEL = "AutoMerge: last run blocked by comment"

function all_specified_statuses_passed(
    api::GitHub.GitHubAPI,
    registry::GitHub.Repo,
    pr::GitHub.PullRequest,
    sha::AbstractString,
    specified_status_contexts::AbstractVector{<:AbstractString};
    auth::GitHub.Authorization,
)
    # Keep track of the values of the specified statuses. If all of
    # these are switched over to true, the result is a success. Do not
    # care about the result of unspecified statuses.
    status_passed = Dict{String,Bool}(
        context => false for context in specified_status_contexts
    )
    combined_status = GitHub.status(api, registry, sha; auth=auth)
    all_statuses = combined_status.statuses
    for status in all_statuses
        context = status.context
        if haskey(status_passed, context)
            status_passed[context] = status.state == "success"
        end
    end
    return all(values(status_passed))
end

function all_specified_check_runs_passed(
    api::GitHub.GitHubAPI,
    registry::GitHub.Repo,
    pr::GitHub.PullRequest,
    sha::AbstractString,
    specified_checks::AbstractVector{<:AbstractString};
    auth::GitHub.Authorization,
)
    # Keep track of the results of the specified checks. If all of
    # these are switched over to true, the result is a success. Do not
    # care about the result of unspecified checks.
    check_passed = Dict{String,Bool}(context => false for context in specified_checks)
    endpoint = "/repos/$(registry.full_name)/commits/$(sha)/check-runs"
    check_runs = GitHub.gh_get_json(
        api,
        endpoint;
        auth=auth,
        headers=Dict("Accept" => "application/vnd.github.antiope-preview+json"),
    )
    for check_run in check_runs["check_runs"]
        name = check_run["name"]
        check_run_was_success =
            (check_run["status"] == "completed") && (check_run["conclusion"] == "success")
        if haskey(check_passed, name)
            check_passed[name] = check_run_was_success
        end
    end
    return all(values(check_passed))
end

function pr_comment_is_blocking(c::GitHub.Comment)
    # Note: `[merge approved]` is not case sensitive, to match the semantics of `contains` on GitHub Actions
    not_blocking = occursin("[noblock]", body(c)) || occursin("[merge approved]", lowercase(body(c)))
    return !not_blocking
end

function pr_has_blocking_comments(
    api::GitHub.GitHubAPI,
    registry::GitHub.Repo,
    pr::GitHub.PullRequest;
    auth::GitHub.Authorization,
)
    all_pr_comments = get_all_pull_request_comments(api, registry, pr; auth=auth)
    return any(pr_comment_is_blocking, all_pr_comments)
end

function pr_is_old_enough(
    pr_type::Symbol,
    pr_age::Dates.Period;
    pkg::AbstractString,
    new_package_waiting_period::Dates.Period,
    new_jll_package_waiting_period::Dates.Period,
    new_version_waiting_period::Dates.Period,
    new_jll_version_waiting_period::Dates.Period,
    pr_author,
    authorized_authors,
    authorized_authors_special_jll_exceptions,
)
    this_is_jll_package = is_jll_name(pkg)

    if this_is_jll_package
        if pr_author in authorized_authors_special_jll_exceptions
            this_pr_can_use_special_jll_exceptions = true
        else
            this_pr_can_use_special_jll_exceptions = false
        end
    else
        this_pr_can_use_special_jll_exceptions = false
    end

    if this_pr_can_use_special_jll_exceptions
        if pr_type == :NewPackage
            return pr_age > new_jll_package_waiting_period
        elseif pr_type == :NewVersion
            return pr_age > new_jll_version_waiting_period
        else
            throw(ArgumentError("pr_type must be either :NewPackage or :NewVersion"))
        end
    else
        if pr_type == :NewPackage
            return pr_age > new_package_waiting_period
        elseif pr_type == :NewVersion
            return pr_age > new_version_waiting_period
        else
            throw(ArgumentError("pr_type must be either :NewPackage or :NewVersion"))
        end
    end
end

function _get_all_pr_statuses(
    api::GitHub.GitHubAPI,
    repo::GitHub.Repo,
    pr::GitHub.PullRequest;
    auth::GitHub.Authorization,
)
    combined_status = GitHub.status(api, repo, pr.head.sha; auth=auth)
    all_statuses = combined_status.statuses
    return all_statuses
end

function _get_status_description(status::GitHub.Status)::String
    if hasproperty(status, :description)
        if status.description === nothing
            return ""
        else
            return status.description
        end
    else
        return ""
    end
end

function _postprocess_automerge_decision_status(status::GitHub.Status; whoami)
    @debug("status: ", status)
    @debug("status.creator: ", status.creator)
    new_package_passed_regex = r"New package. Approved. name=\"(\w*)\". sha=\"(\w*)\""
    new_version_passed_regex = r"New version. Approved. name=\"(\w*)\". sha=\"(\w*)\""
    status_description = _get_status_description(status)
    if status.state == "success" && occursin(new_package_passed_regex, status_description)
        m = match(new_package_passed_regex, status_description)
        passed_pkg_name = m[1]
        passed_pr_head_sha = m[2]
        return true, passed_pkg_name, passed_pr_head_sha, :NewPackage
    end
    if status.state == "success" && occursin(new_version_passed_regex, status_description)
        m = match(new_version_passed_regex, status_description)
        passed_pkg_name = m[1]
        passed_pr_head_sha = m[2]
        return true, passed_pkg_name, passed_pr_head_sha, :NewVersion
    end
    return false, "", "", :failing
end

function pr_has_passing_automerge_decision_status(
    api::GitHub.GitHubAPI,
    repo::GitHub.Repo,
    pr::GitHub.PullRequest;
    auth::GitHub.Authorization,
    whoami,
)
    all_statuses = _get_all_pr_statuses(api, repo, pr; auth=auth)
    for status in all_statuses
        if status.context == "automerge/decision"
            return _postprocess_automerge_decision_status(status; whoami=whoami)
        end
    end
    return false, "", "", :failing
end

function cron_or_api_build(
    api::GitHub.GitHubAPI,
    registry::GitHub.Repo;
    auth::GitHub.Authorization,
    authorized_authors::Vector{String},
    authorized_authors_special_jll_exceptions::Vector{String},
    merge_new_packages::Bool,
    merge_new_versions::Bool,
    new_package_waiting_period,
    new_jll_package_waiting_period,
    new_version_waiting_period,
    new_jll_version_waiting_period,
    whoami::String,
    all_statuses::AbstractVector{<:AbstractString},
    all_check_runs::AbstractVector{<:AbstractString},
    read_only::Bool,
)

    if !read_only
        # first, create `BLOCKED_LABEL` as a label in the repo if it doesn't
        # already exist. This way we can add it to PRs as needed.
        maybe_create_blocked_label(api, registry; auth=auth)
    end

    # next, get a list of ALL open pull requests on this repository
    # then, loop through each of them.
    all_currently_open_pull_requests = my_retry(
        () -> get_all_pull_requests(api, registry, "open"; auth=auth)
    )
    reverse!(all_currently_open_pull_requests)
    at_least_one_exception_was_thrown = false
    if isempty(all_currently_open_pull_requests)
        @info("There are no open pull requests.")
    else
        for pr in all_currently_open_pull_requests
            try
                my_retry() do
                    cron_or_api_build(
                        api,
                        pr,
                        registry;
                        auth=auth,
                        authorized_authors=authorized_authors,
                        authorized_authors_special_jll_exceptions=authorized_authors_special_jll_exceptions,
                        merge_new_packages=merge_new_packages,
                        merge_new_versions=merge_new_versions,
                        new_package_waiting_period=new_package_waiting_period,
                        new_jll_package_waiting_period=new_jll_package_waiting_period,
                        new_version_waiting_period=new_version_waiting_period,
                        new_jll_version_waiting_period=new_jll_version_waiting_period,
                        whoami=whoami,
                        all_statuses=all_statuses,
                        all_check_runs=all_check_runs,
                        read_only=read_only,
                    )
                end
            catch ex
                at_least_one_exception_was_thrown = true
                showerror(stderr, ex)
                Base.show_backtrace(stderr, catch_backtrace())
                println(stderr)
            end
        end
        if at_least_one_exception_was_thrown
            throw(
                AutoMergeCronJobError(
                    "At least one exception was thrown. Check the logs for details."
                ),
            )
        end
    end
    return nothing
end

function cron_or_api_build(
    api::GitHub.GitHubAPI,
    pr::GitHub.PullRequest,
    registry::GitHub.Repo;
    auth::GitHub.Authorization,
    authorized_authors::Vector{String},
    authorized_authors_special_jll_exceptions::Vector{String},
    merge_new_packages::Bool,
    merge_new_versions::Bool,
    new_package_waiting_period,
    new_jll_package_waiting_period,
    new_version_waiting_period,
    new_jll_version_waiting_period,
    whoami::String,
    all_statuses::AbstractVector{<:AbstractString},
    all_check_runs::AbstractVector{<:AbstractString},
    read_only::Bool,
)
    #       first, see if the author is an authorized author. if not, then skip.
    #       next, see if the title matches either the "New Version" regex or
    #               the "New Package regex". if it is not either a new
    #               package or a new version, skip.
    #       next, see if it is old enough. if it is not old enough, then skip.
    #       then, get the `automerge/decision` status and make sure it is passing
    #       then, get all of the pull request comments. if there is any comment that is
    #               (1) not by me, and (2) does not contain the text [noblock], then skip
    #       if all of the above criteria were met, then merge the pull request
    pr_number = number(pr)
    @info("Now examining pull request $(pr_number)")
    pr_author = author_login(pr)
    if pr_author ∉ vcat(authorized_authors, authorized_authors_special_jll_exceptions)
        @info(
            string(
                "Pull request: $(pr_number). ",
                "Decision: do not merge. ",
                "Reason: pull request author is not authorized to automerge.",
            ),
            pr_author,
            authorized_authors,
            authorized_authors_special_jll_exceptions
        )
        return nothing
    end

    if !(is_new_package(pr) || is_new_version(pr))
        @info(
            string(
                "Pull request: $(pr_number). ",
                "Decision: do not merge. ",
                "Reason: pull request is neither a new package nor a new version.",
            ),
            title(pr)
        )
        return nothing
    end

    if is_new_package(pr) # it is a new package
        pr_type = :NewPackage
        pkg, version = parse_pull_request_title(NewPackage(), pr)
    else # it is a new version
        pr_type = :NewVersion
        pkg, version = parse_pull_request_title(NewVersion(), pr)
    end
    pr_age = time_since_pr_creation(pr)
    this_pr_is_old_enough = pr_is_old_enough(
        pr_type,
        pr_age;
        pkg=pkg,
        new_package_waiting_period=new_package_waiting_period,
        new_jll_package_waiting_period=new_jll_package_waiting_period,
        new_version_waiting_period=new_version_waiting_period,
        new_jll_version_waiting_period=new_jll_version_waiting_period,
        pr_author=pr_author,
        authorized_authors=authorized_authors,
        authorized_authors_special_jll_exceptions=authorized_authors_special_jll_exceptions,
    )
    if !this_pr_is_old_enough
        @info(
            string(
                "Pull request: $(pr_number). ",
                "Type: $(pr_type). ",
                "Decision: do not merge. ",
                "Reason: mandatory waiting period has not elapsed.",
            ),
            pr_type,
            pr_age,
            _canonicalize_period(pr_age),
            pkg,
            is_jll_name(pkg),
            new_package_waiting_period,
            _canonicalize_period(new_package_waiting_period),
            new_jll_package_waiting_period,
            _canonicalize_period(new_jll_package_waiting_period),
            new_version_waiting_period,
            _canonicalize_period(new_version_waiting_period),
            new_jll_version_waiting_period,
            _canonicalize_period(new_jll_version_waiting_period),
            pr_author,
            authorized_authors,
            authorized_authors_special_jll_exceptions
        )
        return nothing
    end

    i_passed_this_pr, passed_pkg_name, passed_pr_head_sha, status_pr_type = pr_has_passing_automerge_decision_status(
        api, registry, pr; auth=auth, whoami=whoami
    )
    if !i_passed_this_pr
        @info(
            string(
                "Pull request: $(pr_number). ",
                "Type: $(pr_type). ",
                "Decision: do not merge. ",
                "Reason: automerge/decision status is not passing",
            ),
            whoami
        )
        return nothing
    end

    always_assert(pkg == passed_pkg_name)
    always_assert(pr.head.sha == passed_pr_head_sha)
    _statuses_good = all_specified_statuses_passed(
        api, registry, pr, passed_pr_head_sha, all_statuses; auth=auth
    )
    _checkruns_good = all_specified_check_runs_passed(
        api, registry, pr, passed_pr_head_sha, all_check_runs; auth=auth
    )
    if !(_statuses_good && _checkruns_good)
        @error(
            string(
                "Pull request: $(pr_number). ",
                "Type: $(pr_type). ",
                "Decision: do not merge. ",
                "Reason: ",
                "It is not the case that ",
                "all of the specified statuses and ",
                "check runs passed. ",
            )
        )
        return nothing
    end

    blocked = pr_has_blocking_comments(api, registry, pr; auth=auth) && !has_label(pr.labels, OVERRIDE_BLOCKS_LABEL)
    if blocked
        if !read_only
            # add `BLOCKED_LABEL` to communicate to users
            # that the PR is blocked from automerging
            GitHub.add_labels(api, registry.full_name, pr_number, [BLOCKED_LABEL]; auth=auth)
        end
        @info(
            string(
                "Pull request: $(pr_number). ",
                "Type: $(pr_type). ",
                "Decision: do not merge. ",
                "Reason: pull request has one or more blocking comments.",
            )
        )
        return nothing
    elseif has_label(pr.labels, BLOCKED_LABEL) && !read_only
        # remove block label BLOCKED_LABEL if it exists
        # note we use `try_remove_label` to avoid crashing the job
        # if there is some race condition or manual intervention
        # and the blocked label was removed at some point between
        # when the `pr` object was created and now.
        try_remove_label(api, registry.full_name, pr_number, BLOCKED_LABEL; auth=auth)
    end

    if pr_type == :NewPackage # it is a new package
        always_assert(status_pr_type == :NewPackage)
        if merge_new_packages
            @info(
                string(
                    "Pull request: $(pr_number). ",
                    "Type: $(pr_type). ",
                    "Decision: merge now.",
                )
            )
            if read_only
                @info "`read_only` mode on; skipping merge"
            else
                my_retry(() -> merge!(api, registry, pr, passed_pr_head_sha; auth=auth))
            end
        else
            @info(
                string(
                    "Pull request: $(pr_number). ",
                    "Type: $(pr_type). ",
                    "Decision: do not merge. ",
                    "Reason: ",
                    "This is a new package pull request. ",
                    "All of the criteria for automerging ",
                    "were met. ",
                    "However, merge_new_packages is false, ",
                    "so I will not merge. ",
                    "If merge_new_packages had been set to ",
                    "true, I would have merged this ",
                    "pull request right now.",
                )
            )
        end
    else # it is a new version
        always_assert(pr_type == :NewVersion)
        always_assert(status_pr_type == :NewVersion)
        if merge_new_versions
            @info(
                string(
                    "Pull request: $(pr_number). ",
                    "Type: $(pr_type). ",
                    "Decision: merge now.",
                )
            )
            if read_only
                @info "`read_only` mode on; skipping merge"
            else
                my_retry(() -> merge!(api, registry, pr, passed_pr_head_sha; auth=auth))
            end
        else
            @info(
                string(
                    "Pull request: $(pr_number). ",
                    "Type: $(pr_type). ",
                    "Decision: do not merge. ",
                    "Reason: merge_new_versions is false",
                    "This is a new version pull request. ",
                    "All of the criteria for automerging ",
                    "were met. ",
                    "However, merge_new_versions is false, ",
                    "so I will not merge. ",
                    "If merge_new_versions had been set to ",
                    "true, I would have merged this ",
                    "pull request right now.",
                )
            )
        end
    end
    return nothing
end
