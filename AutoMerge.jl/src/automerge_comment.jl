function update_automerge_comment!(data::GitHubAutoMergeData, body::AbstractString)::Nothing
    if data.read_only
        @info "`read_only` mode; skipping updating automerge comment."
        return nothing
    end
    api = data.api
    repo = data.registry
    pr = data.pr
    auth = data.auth
    whoami = data.whoami

    my_comments = my_retry(
        () -> get_all_my_pull_request_comments(api, repo, pr; auth=auth, whoami=whoami)
    )
    num_comments = length(my_comments)
    _body = string(
        strip(
            string(
                body, "\n", "<!---\n", "this_is_the_single_automerge_comment\n", "--->\n"
            ),
        ),
    )
    if num_comments > 1
        for i in 2:num_comments
            comment_to_delete = my_comments[i]
            try
                my_retry(() -> delete_comment!(api, repo, pr, comment_to_delete; auth=auth))
            catch ex
                @error("Ignoring error: ", exception = (ex, catch_backtrace()))
            end
        end
        comment_to_update = my_comments[1]
        if strip(comment_to_update.body) != _body
            my_retry(
                () -> edit_comment!(api, repo, pr, comment_to_update, _body; auth=auth)
            )
        end
    elseif num_comments == 1
        comment_to_update = my_comments[1]
        if strip(comment_to_update.body) != _body
            my_retry(
                () -> edit_comment!(api, repo, pr, comment_to_update, _body; auth=auth)
            )
        end
    else
        always_assert(num_comments < 1)
        my_retry(() -> post_comment!(api, repo, pr, _body; auth=auth))
    end
    return nothing
end
