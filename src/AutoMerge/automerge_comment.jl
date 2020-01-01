function update_automerge_comment!(repo::GitHub.Repo,
                                   pr::GitHub.PullRequest;
                                   body::AbstractString,
                                   auth::GitHub.Authorization,
                                   whoami)::Nothing
    my_comments = my_retry(() -> get_all_my_pull_request_comments(repo,
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
                my_retry(() -> delete_comment!(repo,
                                               pr,
                                               comment_to_delete;
                                               auth = auth))
            catch ex
                @error("Ignoring error: ", exception=(ex, catch_backtrace()))
            end
        end
        comment_to_update = my_comments[1]
        my_retry(() -> edit_comment!(repo,
                                     pr,
                                     comment_to_update,
                                     _body;
                                     auth = auth))
    elseif num_comments == 1
        comment_to_update = my_comments[1]
        my_retry(() -> edit_comment!(repo,
                                     pr,
                                     comment_to_update,
                                     _body;
                                     auth = auth))
    else
        always_assert(num_comments < 1)
        my_retry(() -> post_comment!(repo,
                                     pr,
                                     _body;
                                     auth = auth))
    end
    return nothing
end
