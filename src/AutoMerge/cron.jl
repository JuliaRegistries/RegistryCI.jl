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
    all_pr_comments = get_all_pull_request_comments(registry, pr; auth=auth)
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

@inline my_isless(r1::GitHub.Review, r2::GitHub.Review) = isless(r1.id, r2.id)

function pr_was_approved_by_me(repo::GitHub.Repo,
                               pr::GitHub.PullRequest;
                               auth::GitHub.Authorization,
                               whoami::String)
    all_pr_reviews = get_all_pull_request_reviews(repo, pr; auth=auth)
    my_pr_reviews = Vector{GitHub.Review}(undef, 0)
    i_left_at_least_one_approving_review = false
    i_did_not_leave_any_nonapproving_reviews = true
    for rev in all_pr_reviews
        if reviewer_login(rev) == whoami
            if review_state(rev) == "APPROVED"
                i_left_at_least_one_approving_review = true
            else
                i_did_not_leave_any_nonapproving_reviews = false
            end
            push!(my_pr_reviews, rev)
        end
    end
    i_approved_this_pr = i_left_at_least_one_approving_review && i_did_not_leave_any_nonapproving_reviews
    if i_approved_this_pr
        if length(my_pr_reviews) == 1
            my_review = my_pr_reviews[1]
        else
            @warn("I did not leave exactly one review. Using the most recent review")
            sort!(my_pr_reviews; lt = my_isless)
            my_review = my_pr_reviews[end]
        end
        my_review_body = my_review.body
        approving_review_regex = r"approved_pr_head_commit_sha=\"([A-Za-z0-9]*?)\""
        if occursin(approving_review_regex, my_review_body)
            m = match(approving_review_regex, my_review_body)
            approved_pr_head_sha = m[1]
            return true, approved_pr_head_sha
        else
            @error("The review I left does not match the regex", my_review_body)
            return false, ""
        end
    else
        return false, ""
    end
end

function cron_or_api_build(registry::GitHub.Repo;
                           auth::GitHub.Authorization,
                           authorized_authors::Vector{String},
                           merge_new_packages::Bool,
                           merge_new_versions::Bool,
                           new_package_waiting_period,
                           new_version_waiting_period,
                           whoami::String)
    # first, get a list of ALL open pull requests on this repository
    # then, loop through each of them.
    all_currently_open_pull_requests = my_retry(() -> get_all_pull_requests(registry, "open"; auth=auth))
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
                                                 whoami = whoami),
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
                           whoami::String)
    #       first, see if the author is an approved author. if not, then skip.
    #       next, see if the title matches either the "New Version" regex or
    #               the "New Package regex". if it is not either a new
    #               package or a new version, skip.
    #       next, see if it is old enough. if it is not old enough, then skip.
    #       then, get all of the reviews. make sure that (1) I left at least one
    #               review, and (2) all of my reviews are approving. if this criterion
    #               is not met, skip
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
            _pr_is_old_enough = pr_is_old_enough(pr_type,
                                                 pr_age;
                                                 new_package_waiting_period = new_package_waiting_period,
                                                 new_version_waiting_period = new_version_waiting_period)
            if _pr_is_old_enough
                i_approved_this_pr, approved_pr_head_sha = pr_was_approved_by_me(registry,
                                                                                 pr;
                                                                                 auth = auth,
                                                                                 whoami = whoami)
                if i_approved_this_pr
                    if pr_has_no_blocking_comments(registry, pr; auth = auth)
                        "Pull request: $(pr_number). "
                        "Type: $(pr_type). "
                        "Decision: merge. "
                        if pr_type == :NewPackage # it is a new package
                            if merge_new_packages
                                my_comment = comment_text_merge_now()
                                @info(string("Pull request: $(pr_number). ",
                                             "Type: $(pr_type). ",
                                             "Decision: merge now."))
                                # my_retry(() -> post_comment!(registry, pr, my_comment; auth = auth))
                                my_retry(() -> merge!(registry, pr, approved_pr_head_sha; auth = auth))
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
                            if merge_new_versions
                                my_comment = comment_text_merge_now()
                                @info(string("Pull request: $(pr_number). ",
                                             "Type: $(pr_type). ",
                                             "Decision: merge now."))
                                # my_retry(() -> post_comment!(registry, pr, my_comment; auth = auth))
                                my_retry(() -> merge!(registry, pr, approved_pr_head_sha; auth = auth))
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
                                 "Reason: it is not the case that ",
                                 "both of the following conditions ",
                                 "are true: ",
                                 "(1) I left at least one approving ",
                                 "review. ",
                                 "(2) I did not leave any ",
                                 "non-approving reviews."),
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
