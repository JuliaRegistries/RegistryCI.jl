author_login(pull_request::GitHub.PullRequest) = pull_request.user.login

base_repo(pull_request::GitHub.PullRequest) = pull_request.base.repo

body(c::GitHub.Comment) = c.body

function created_at(pull_request::GitHub.PullRequest)
    result = time_is_already_in_utc(pull_request.created_at)
    return result
end

function delete_comment!(api::GitHub.GitHubAPI,
                         repo::GitHub.Repo,
                         pr::GitHub.PullRequest,
                         comment_to_delete::GitHub.Comment;
                         auth::GitHub.Authorization)
    GitHub.delete_comment(api, repo,
                          comment_to_delete,
                          :pr;
                          auth = auth)
    return nothing
end

function delete_merged_branch!(api::GitHub.GitHubAPI, repo::GitHub.Repo, pr::GitHub.PullRequest; auth::GitHub.Authorization)
    updated_pr = _get_updated_pull_request(api, pr; auth=auth)
    if is_merged(updated_pr)
        try
            head_branch = pull_request_head_branch(updated_pr)
            repo = head_branch.repo
            ref = "heads/$(head_branch.ref)"
            GitHub.delete_reference(api, repo, ref; auth=auth)
        catch ex
            showerror(stderr, ex)
            Base.show_backtrace(stderr, catch_backtrace())
            println(stderr)
        end
    end
    return nothing
end

function edit_comment!(api::GitHub.GitHubAPI,
                       repo::GitHub.Repo,
                       pr::GitHub.PullRequest,
                       comment::GitHub.Comment,
                       body::String;
                       auth::GitHub.Authorization)
    myparams = Dict("body" => body)
    GitHub.edit_comment(api, repo, comment, :pr; auth=auth, params = myparams)
    return nothing
end

full_name(repo::GitHub.Repo) = repo.full_name

function _get_updated_pull_request(api::GitHub.GitHubAPI, pull_request::GitHub.PullRequest; auth::GitHub.Authorization)
    pr_base_repo = base_repo(pull_request)
    pr_number = number(pull_request)
    updated_pr = GitHub.pull_request(api, pr_base_repo, pr_number; auth=auth)
    return updated_pr
end

function get_all_my_pull_request_comments(api::GitHub.GitHubAPI,
                                          repo::GitHub.Repo,
                                          pr::GitHub.PullRequest;
                                          auth::GitHub.Authorization,
                                          whoami)
    all_comments = get_all_pull_request_comments(api, repo,
                                                 pr;
                                                 auth = auth)
    my_comments = Vector{GitHub.Comment}(undef, 0)
    for c in all_comments
        if c.user.login == whoami
            push!(my_comments, c)
        end
    end
    unique!(my_comments)
    my_comments = my_comments[sortperm([x.created_at for x in my_comments])]
    return my_comments
end

function get_all_pull_request_comments(api::GitHub.GitHubAPI,
                                       repo::GitHub.Repo,
                                       pr::GitHub.PullRequest;
                                       auth::GitHub.Authorization)
    all_comments = Vector{GitHub.Comment}(undef, 0)
    myparams = Dict("per_page" => 100, "page" => 1)
    cs, page_data = GitHub.comments(api, repo, pr, :pr; auth=auth, params = myparams, page_limit = 100)
    append!(all_comments, cs)
    while haskey(page_data, "next")
        cs, page_data =  GitHub.comments(api, repo, pr, :pr; auth=auth, page_limit = 100, start_page = page_data["next"])
        append!(all_comments, cs)
    end
    unique!(all_comments)
    all_comments = all_comments[sortperm([x.created_at for x in all_comments])]
    return all_comments
end

function get_all_pull_requests(api::GitHub.GitHubAPI,
                               repo::GitHub.Repo,
                               state::String;
                               auth::GitHub.Authorization)
    all_pull_requests = Vector{GitHub.PullRequest}(undef, 0)
    myparams = Dict("state" => state, "per_page" => 100, "page" => 1)
    prs, page_data = GitHub.pull_requests(api, repo; auth=auth, params = myparams, page_limit = 100)
    append!(all_pull_requests, prs)
    while haskey(page_data, "next")
        prs, page_data = GitHub.pull_requests(api, repo; auth=auth, page_limit = 100, start_page = page_data["next"])
        append!(all_pull_requests, prs)
    end
    unique!(all_pull_requests)
    return all_pull_requests
end

function get_changed_filenames(api::GitHub.GitHubAPI, repo::GitHub.Repo, pull_request::GitHub.PullRequest; auth::GitHub.Authorization)
    files = GitHub.pull_request_files(api, repo, pull_request; auth=auth)
    n = length(files)
    filenames = Vector{String}(undef, n)
    for i = 1:n
        filenames[i] = files[i].filename
    end
    return filenames
end

is_merged(pull_request::GitHub.PullRequest) = pull_request.merged

function is_open(pull_request::GitHub.PullRequest)
    result = pr_state(pull_request) == "open"
    !result && @error("Pull request is not open")
    return result
end

function merge!(api::GitHub.GitHubAPI,
                registry_repo::GitHub.Repo,
                pr::GitHub.PullRequest,
                approved_pr_head_sha::AbstractString;
                auth::GitHub.Authorization)
    pr = wait_pr_compute_mergeability(api, registry_repo, pr; auth = auth)
    _approved_pr_head_sha = convert(String, strip(approved_pr_head_sha))::String
    pr_number = number(pr)
    @info("Attempting to squash-merge pull request #$(pr_number)")
    @debug("sha = $(_approved_pr_head_sha)")
    @debug("pr.mergeable = $(pr.mergeable)")
    params = Dict("sha" => _approved_pr_head_sha, "merge_method" => "squash")
    try
        GitHub.merge_pull_request(api, registry_repo,
                                  pr_number;
                                  auth=auth,
                                  params=params)
    catch ex
        showerror(stderr, ex)
        Base.show_backtrace(stderr, catch_backtrace())
        println(stderr)
    end
    try
        delete_merged_branch!(api, registry_repo, pr; auth=auth)
    catch
    end
    return nothing
end

function wait_pr_compute_mergeability(api::GitHub.GitHubAPI,
                                      repo::GitHub.Repo,
                                      pr::GitHub.PullRequest;
                                      auth::GitHub.Authorization)
    sleep(5)
    max_tries = 10
    num_tries = 0
    pr = GitHub.pull_request(api, repo, pr.number; auth = auth)
    while !(pr.mergeable isa Bool) && num_tries <= max_tries
        num_tries = num_tries + 1
        sleep(5)
        pr = GitHub.pull_request(api, repo, pr.number; auth = auth)
    end
    return pr
end

num_changed_files(pull_request::GitHub.PullRequest) = pull_request.changed_files

number(pull_request::GitHub.PullRequest) = pull_request.number

function post_comment!(api::GitHub.GitHubAPI,
                       repo::GitHub.Repo,
                       pr::GitHub.PullRequest,
                       body::String;
                       auth::GitHub.Authorization)
    myparams = Dict("body" => body)
    GitHub.create_comment(api, repo, pr, :pr; auth=auth, params = myparams)
    return nothing
end

pull_request_head_branch(pull_request::GitHub.PullRequest) = pull_request.head

pull_request_head_sha(pull_request::GitHub.PullRequest) = pull_request.head.sha

repo_url(repo::GitHub.Repo) = repo.html_url.uri

pr_state(pull_request::GitHub.PullRequest) = pull_request.state

function time_since_pr_creation(pull_request::GitHub.PullRequest)
    _pr_created_at_utc = created_at(pull_request)
    _now_utc = now_utc()
    result = _now_utc - _pr_created_at_utc
    return result
end

title(pull_request::GitHub.PullRequest) = pull_request.title

function username(api::GitHub.GitHubAPI, auth::GitHub.Authorization)
    user_information = GitHub.gh_get_json(api,
                                          "/user";
                                          auth = auth)
    return user_information["login"]::String
end
