function update_automerge_comment!(api::GitHub.GitHubAPI,
                                   repo::GitHub.Repo,
                                   pr::GitHub.PullRequest;
                                   body::AbstractString,
                                   auth::GitHub.Authorization,
                                   whoami)::Nothing
    my_comments = my_retry(() -> get_all_my_pull_request_comments(api,
                                                                  repo,
                                                                  pr;
                                                                  auth = auth,
                                                                  whoami = whoami))
    num_comments = length(my_comments)
    _body::String = convert(String,
                                    strip(string(strip(body),
                                    "\n",
                                    "<!---\n",
                                    "this_is_the_single_automerge_comment\n",
                                    "--->\n")))::String
    if num_comments > 1
        for i = 2:num_comments
            comment_to_delete = my_comments[i]
            try
                my_retry(() -> delete_comment!(api, repo,
                                               pr,
                                               comment_to_delete;
                                               auth = auth))
            catch ex
                @error("Ignoring error: ", exception=(ex, catch_backtrace()))
            end
        end
        comment_to_update = my_comments[1]
        if strip(comment_to_update.body) != strip(_body)
            my_retry(() -> edit_comment!(api, repo,
                                         pr,
                                         comment_to_update,
                                         _body;
                                         auth = auth))
        end
    elseif num_comments == 1
        comment_to_update = my_comments[1]
        if strip(comment_to_update.body) != strip(_body)
            my_retry(() -> edit_comment!(api, repo,
                                         pr,
                                         comment_to_update,
                                         _body;
                                         auth = auth))
        end
    else
        always_assert(num_comments < 1)
        my_retry(() -> post_comment!(api, repo,
                                     pr,
                                     _body;
                                     auth = auth))
    end
    return nothing
end
