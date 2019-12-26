function pull_request_build(::NewVersion,
                            pr::GitHub.PullRequest,
                            current_pr_head_commit_sha::String,
                            registry::GitHub.Repo;
                            auth::GitHub.Authorization,
                            authorized_authors::Vector{String},
                            registry_head::String,
                            registry_master::String,
                            suggest_onepointzero::Bool,
                            whoami::String)
    # first check if the PR is open, and the author is authorized - if not, then quit
    # then, delete ALL reviews by me
    # then check rules 1-6. if fail, post comment.
    # if everything passed, add an approving review by me
    #
    # Rules:
    # 1. Only changes a subset of the following files:
    #     - `E/Example/Compat.toml`
    #     - `E/Example/Deps.toml`
    #     - `E/Example/Versions.toml`
    # 2. Sequential version number - if the last version was 1.2.3 then the next can be 1.2.4, 1.3.0 or 2.0.0
    # 3. Compat for all dependencies - all [deps] should also have [compat] entries (and Julia itself) - [compat] entries should have upper bounds
    # 4. If it is a patch release, then it does not narrow the Julia compat range
    # 5. Version can be installed - given the proposed changes to the registry, can we resolve and install the new version of the package?
    # 6. Version can be loaded - once it's been installed (and built?), can we load the code?
    pkg, version = parse_pull_request_title(NewVersion(), pr)
    @info("This is a new version pull request", pkg, version)
    pr_author_login = author_login(pr)
    if is_open(pr)
        if pr_author_login in authorized_authors
            my_retry(() -> delete_all_of_my_reviews!(registry,
                                                     pr;
                                                     auth = auth,
                                                     whoami = whoami))
            description = "New version. Pending."
            params = Dict("state" => "pending",
                          "context" => "automerge/decision",
                          "description" => description)
            my_retry(() -> GitHub.create_status(registry,
                                                current_pr_head_commit_sha;
                                                auth = auth,
                                                params=params))
            g1, m1 = pr_only_changes_allowed_files(NewVersion(),
                                                   registry,
                                                   pr,
                                                   pkg;
                                                   auth = auth)
            g2, m2, release_type = meets_sequential_version_number(pkg,
                                                                   version;
                                                                   registry_head = registry_head,
                                                                   registry_master = registry_master)
            g3, m3 = meets_compat_for_all_deps(registry_head,
                                               pkg,
                                               version)
            if release_type == :patch
                g4, m4 = meets_patch_release_does_not_narrow_julia_compat(pkg,
                                                                          version;
                                                                          registry_head = registry_head,
                                                                          registry_master = registry_master)
            else
                g4 = true
                m4 = ""
            end
            @info("Only modifies the files that it's allowed to modify",
                  meets_this_guideline = g1,
                  message = m1)
            @info("Sequential version number",
                  meets_this_guideline = g2,
                  message = m2)
            @info("Compat (with upper bound) for all dependencies",
                  meets_this_guideline = g3,
                  message = m3)
            @info("If it is a patch release, then it does not narrow the Julia compat range",
                  meets_this_guideline = g4,
                  message = m4)
            g1through4 = [g1, g2, g3, g4]
            if !all(g1through4)
                description = "New version. Failed."
                params = Dict("state" => "failure",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(registry,
                                                    current_pr_head_commit_sha;
                                                    auth = auth,
                                                    params = params))
            end
            g5and6, m5and6 = meets_version_can_be_loaded(registry_head,
                                                         pkg,
                                                         version)
            @info("Version can be installed and loaded",
                  meets_this_guideline = g5and6,
                  message = m5and6)
            g1through6 = [g1, g2, g3, g4, g5and6]
            allmessages1through6 = [m1, m2, m3, m4, m5and6]
            if all(g1through6) # success
                description = "New version. Approved. sha=\"$(current_pr_head_commit_sha)\""
                params = Dict("state" => "success",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(registry,
                                                    current_pr_head_commit_sha;
                                                    auth = auth,
                                                    params = params))
                this_pr_comment_pass = comment_text_pass(NewVersion(),
                                                         suggest_onepointzero,
                                                         version)
                my_retry(() -> delete_all_of_my_reviews!(registry,
                                                         pr;
                                                         auth = auth,
                                                         whoami = whoami))
                my_retry(() -> approve!(registry,
                                        pr,
                                        current_pr_head_commit_sha;
                                        auth = auth,
                                        body = this_pr_comment_pass,
                                        whoami = whoami))
                return nothing
            else # failure
                description = "New version. Failed."
                params = Dict("state" => "failure",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(registry,
                                                    current_pr_head_commit_sha;
                                                    auth=auth,
                                                    params=params))
                failingmessages1through6 = allmessages1through6[.!g1through6]
                this_pr_comment_fail = comment_text_fail(NewVersion(),
                                                         failingmessages1through6,
                                                         suggest_onepointzero,
                                                         version)
                my_retry(() -> post_comment!(registry,
                                             pr,
                                             this_pr_comment_fail;
                                             auth = auth))
                error("The automerge guidelines were not met.")
                return nothing
            end
        else
            @info("Author $(pr_author_login) is not authorized to automerge. Exiting...")
            return nothing
        end
    else
        @info("The pull request is not open. Exiting...")
        return nothing
    end
    return nothing
end
