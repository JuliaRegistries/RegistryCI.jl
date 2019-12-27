import GitHub

function all_specified_statuses_passed(registry::GitHub.Repo,
                                       pr::GitHub.PullRequest,
                                       sha::AbstractString,
                                       specified_status_context_list::AbstractVector{<:AbstractString};
                                       auth::GitHub.Authorization)
    specified_status_context_did_fail = Dict{String, Bool}()
    for context in specified_status_context_list
        specified_status_context_did_fail[context] = true
    end
    combined_status = GitHub.status(registry, sha; auth = auth)
    all_statuses = combined_status.statuses
    for status in all_statuses
        context = status.context
        if haskey(specified_status_context_did_fail, context)
            status_was_success = status.state == "success"
            status_was_failure = !status_was_success
            specified_status_context_did_fail[context] = status_was_failure
        end
    end
    if any(values(specified_status_context_did_fail))
        return false
    end
    return true
end

function all_specified_check_runs_passed(registry::GitHub.Repo,
                                         pr::GitHub.PullRequest,
                                         sha::AbstractString,
                                         specified_check_run_name_list::AbstractVector{<:AbstractString};
                                         auth::GitHub.Authorization)
    specified_check_run_name_did_fail = Dict{String, Bool}()
    for context in specified_check_run_name_list
        specified_check_run_name_did_fail[context] = true
    end
    endpoint = "/repos/$(repo.full_name)/commits/$(sha)/check-runs"
    check_runs = GitHub.gh_get_json(GitHub.DEFAULT_API,
                                    endpoint;
                                    auth = auth,
                                    headers = Dict("Accept" =>
                                                   "application/vnd.github.antiope-preview+json"))
    for check_run in check_runs["check_runs"]
        name = check_run["name"]
        check_run_was_success = (check_run["status"] == "completed") & (check_run["conclusion"] == "success")
        check_run_was_failure = !check_run_was_success
        if haskey(specified_check_run_name_did_fail, name)
            specified_check_run_name_did_fail[name] = check_run_was_failure
        end
    end
    if any(values(specified_check_run_name_did_fail))
        return false
    end
    return true
end

function pr_comment_is_blocking(c::GitHub.Comment)
    c_body = body(c)
    if occursin("[noblock]", c_body)
        return false
    else
        return true
    end
end

function pr_has_no_blocking_comments(registry::GitHub.Repo,
                                     pr::GitHub.PullRequest;
                                     auth::GitHub.Authorization)
    all_pr_comments = get_all_pull_request_comments(registry, pr; auth = auth)
    if isempty(all_pr_comments)
        return true
    else
        num_comments = length(all_pr_comments)
        comment_is_blocking = BitVector(undef, num_comments)
        for i = 1:num_comments
            comment_is_blocking[i] = pr_comment_is_blocking(all_pr_comments[i])
        end
        if any(comment_is_blocking)
            return false
        else
            return true
        end
    end
end

function pr_is_old_enough(pr_type::Symbol,
                          pr_age::Dates.Period;
                          new_package_waiting_period::Dates.Period,
                          new_version_waiting_period::Dates.Period)
    if pr_type == :NewPackage
        return pr_age > new_package_waiting_period
    elseif pr_type == :NewVersion
        return pr_age > new_version_waiting_period
    else
        throw(ArgumentError("pr_type must be either :NewPackage or :NewVersion"))
    end
end

function _get_all_pr_statuses(repo::GitHub.Repo,
                              pr::GitHub.PullRequest;
                              auth::GitHub.Authorization)
    combined_status = GitHub.status(repo, pr.head.sha)
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

function _postprocess_automerge_decision_status(status::GitHub.Status;
                                                whoami)
    @debug("status: ", status)
    @debug("status.creator: ", status.creator)
    new_package_passed_regex = r"New package. Approved. sha=\"(\w*)\""
    new_version_passed_regex = r"New version. Approved. sha=\"(\w*)\""
    status_description = _get_status_description(status)
    if status.state == "success" && occursin(new_package_passed_regex,
                                             status_description)
        m = match(new_package_passed_regex,
                  status_description)
        passed_pr_head_sha = m[1]
        return true, passed_pr_head_sha, :NewPackage
    end
    if status.state == "success" && occursin(new_version_passed_regex,
                                             status_description)
        m = match(new_version_passed_regex,
                  status_description)
        passed_pr_head_sha = m[1]
        return true, passed_pr_head_sha, :NewVersion
    end
    return false, "", :failing
end

function pr_has_passing_automerge_decision_status(repo::GitHub.Repo,
                                                  pr::GitHub.PullRequest;
                                                  auth::GitHub.Authorization,
                                                  whoami)
    all_statuses = _get_all_pr_statuses(repo, pr; auth = auth)
    for status in all_statuses
        if status.context == "automerge/decision"
            return _postprocess_automerge_decision_status(status;
                                                          whoami = whoami)
        end
    end
    return false, "", :failing
end

function cron_or_api_build(registry::GitHub.Repo;
                           auth::GitHub.Authorization,
                           authorized_authors::Vector{String},
                           merge_new_packages::Bool,
                           merge_new_versions::Bool,
                           new_package_waiting_period,
                           new_version_waiting_period,
                           whoami::String,
                           all_statuses::AbstractVector{<:AbstractString},
                           all_check_runs::AbstractVector{<:AbstractString})
    # first, get a list of ALL open pull requests on this repository
    # then, loop through each of them.
    all_currently_open_pull_requests = my_retry(() -> get_all_pull_requests(registry, "open"; auth = auth))
    reverse!(all_currently_open_pull_requests)
    at_least_one_exception_was_thrown = false
    num_retries = 0
    if isempty(all_currently_open_pull_requests)
        @info("There are no open pull requests.")
    else
        for pr in all_currently_open_pull_requests
            try
                my_retry(() -> cron_or_api_build(pr,
                                                 registry::GitHub.Repo;
                                                 auth = auth,
                                                 authorized_authors = authorized_authors,
                                                 merge_new_packages = merge_new_packages,
                                                 merge_new_versions = merge_new_versions,
                                                 new_package_waiting_period = new_package_waiting_period,
                                                 new_version_waiting_period = new_version_waiting_period,
                                                 whoami = whoami,
                                                 all_statuses = all_statuses,
                                                 all_check_runs = all_check_runs),
                         num_retries)
            catch ex
                at_least_one_exception_was_thrown = true
                showerror(stderr, ex)
                Base.show_backtrace(stderr, catch_backtrace())
                println(stderr)
            end
        end
        if at_least_one_exception_was_thrown
            error("At least one exception was thrown. Check the logs for details.")
        end
    end
    return nothing
end

function cron_or_api_build(pr::GitHub.PullRequest,
                           registry::GitHub.Repo;
                           auth::GitHub.Authorization,
                           authorized_authors::Vector{String},
                           merge_new_packages::Bool,
                           merge_new_versions::Bool,
                           new_package_waiting_period,
                           new_version_waiting_period,
                           whoami::String,
                           all_statuses::AbstractVector{<:AbstractString},
                           all_check_runs::AbstractVector{<:AbstractString})
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
    if pr_author in authorized_authors
        if is_new_package(pr) || is_new_version(pr)
            if is_new_package(pr) # it is a new package
                pr_type = :NewPackage
                pkg, version = parse_pull_request_title(NewPackage(), pr)
            else # it is a new version
                pr_type = :NewVersion
                pkg, version = parse_pull_request_title(NewVersion(), pr)
            end
            pr_age = time_since_pr_creation(pr)
            this_pr_is_old_enough = pr_is_old_enough(pr_type,
                                                 pr_age;
                                                 new_package_waiting_period = new_package_waiting_period,
                                                 new_version_waiting_period = new_version_waiting_period)
            if this_pr_is_old_enough
                i_passed_this_pr,
                    passed_pr_head_sha,
                    status_pr_type = pr_has_passing_automerge_decision_status(registry,
                                                                              pr;
                                                                              auth = auth,
                                                                              whoami = whoami)
                always_assert(pr.head.sha == passed_pr_head_sha)
                all_specified_statuses_passed(registry,
                                              pr,
                                              passed_pr_head_sha,
                                              all_statuses;
                                              auth = auth)
                all_specified_check_runs_passed(registry,
                                                pr,
                                                passed_pr_head_sha,
                                                all_check_runs;
                                                auth = auth)
                if i_passed_this_pr
                    if pr_has_no_blocking_comments(registry, pr; auth = auth)
                        "Pull request: $(pr_number). "
                        "Type: $(pr_type). "
                        "Decision: merge. "
                        if pr_type == :NewPackage # it is a new package
                            always_assert(status_pr_type == :NewPackage)
                            if merge_new_packages
                                my_comment = comment_text_merge_now()
                                @info(string("Pull request: $(pr_number). ",
                                             "Type: $(pr_type). ",
                                             "Decision: merge now."))
                                my_retry(() -> merge!(registry, pr, passed_pr_head_sha; auth = auth))
                            else
                                @info(string("Pull request: $(pr_number). ",
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
                                             "pull request right now."))
                            end
                        else # it is a new version
                            always_assert(pr_type == :NewVersion)
                            always_assert(status_pr_type == :NewVersion)
                            if merge_new_versions
                                my_comment = comment_text_merge_now()
                                @info(string("Pull request: $(pr_number). ",
                                             "Type: $(pr_type). ",
                                             "Decision: merge now."))
                                my_retry(() -> merge!(registry, pr, passed_pr_head_sha; auth = auth))
                            else
                                @info(string("Pull request: $(pr_number). ",
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
                                             "pull request right now."))
                            end
                        end
                    else
                        @info(string("Pull request: $(pr_number). ",
                                     "Type: $(pr_type). ",
                                     "Decision: do not merge. ",
                                     "Reason: pull request has one or more blocking comments."))
                    end
                else
                    @info(string("Pull request: $(pr_number). ",
                                 "Type: $(pr_type). ",
                                 "Decision: do not merge. ",
                                 "Reason: automerge/decision status is not passing"),
                          whoami)
                end
            else
                @info(string("Pull request: $(pr_number). ",
                             "Type: $(pr_type). ",
                             "Decision: do not merge. ",
                             "Reason: mandatory waiting period has not elapsed."),
                      pr_type,
                      pr_age,
                      new_package_waiting_period,
                      new_version_waiting_period)
            end
        else
            @info(string("Pull request: $(pr_number). ",
                         "Decision: do not merge. ",
                         "Reason: pull request is neither a new package nor a new version."),
                  title(pr))
        end
    else
        @info(string("Pull request: $(pr_number). ",
                     "Decision: do not merge. ",
                     "Reason: pull request author is not authorized to automerge."),
              pr_author,
              authorized_authors)
    end
    return nothing
end
