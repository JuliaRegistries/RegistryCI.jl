function pull_request_build(::NewPackage,
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
    # then check rules 1-8. if fail, post comment.
    # if everything passed, add an approving review by me
    #
    # Rules:
    # 1. Only changes a subset of the following files:
    #     - `Registry.toml`,
    #     - `E/Example/Compat.toml`
    #     - `E/Example/Deps.toml`
    #     - `E/Example/Package.toml`
    #     - `E/Example/Versions.toml`
    # 2. Normal capitalization - name should match r"^[A-Z]\w*[a-z][0-9]?$" - i.e. starts with a capital letter, ASCII alphanumerics only, ends in lowercase
    # 3. Not too short - at least five letters - you can register names shorter than this, but doing so requires someone to approve
    # 4. Standard initial version number - one of 0.0.1, 0.1.0, 1.0.0
    # 5. Repo URL ends with /$name.jl.git where name is the package name
    # 6. Compat for all dependencies - all [deps] should also have [compat] entries (and Julia itself) - [compat] entries should have upper bounds
    # 7. Version can be installed - given the proposed changes to the registry, can we resolve and install the new version of the package?
    # 8. Version can be loaded - once it's been installed (and built?), can we load the code?
    pkg, version = parse_pull_request_title(NewPackage(), pr)
    @info("This is a new package pull request", pkg, version)
    pr_author_login = author_login(pr)
    if is_open(pr)
        if pr_author_login in authorized_authors
            my_retry(() -> delete_all_of_my_reviews!(registry,
                                                     pr;
                                                     auth = auth,
                                                     whoami = whoami))
            description = "New package. Pending."
            params = Dict("state" => "pending",
                          "context" => "automerge/decision",
                          "description" => description)
            my_retry(() -> GitHub.create_status(registry,
                                                current_pr_head_commit_sha;
                                                auth = auth,
                                                params = params))
            g1, m1 = pr_only_changes_allowed_files(NewPackage(),
                                                   registry,
                                                   pr,
                                                   pkg;
                                                   auth = auth)
            g2, m2 = meets_normal_capitalization(pkg)
            g3, m3 = meets_name_length(pkg)
            g4, m4 = meets_standard_initial_version_number(version)
            g5, m5 = meets_repo_url_requirement(pkg;
                                                registry_head = registry_head)
            g6, m6 = meets_compat_for_all_deps(registry_head,
                                               pkg,
                                               version)

            @info("Only modifies the files that it's allowed to modify",
                  meets_this_guideline = g1,
                  message = m1)
            @info("Normal capitalization",
                  meets_this_guideline = g2,
                  message = m2)
            @info("Name not too short",
                  meets_this_guideline = g3,
                  message = m3)
            @info("Standard initial version number ",
                  meets_this_guideline = g4,
                  message = m4)
            @info("Repo URL ends with /name.jl.git",
                  meets_this_guideline = g5,
                  message = m5)
            @info("Compat (with upper bound) for all dependencies",
                  meets_this_guideline = g6,
                  message = m6)
            g1through6 = [g1, g2, g3, g4, g5, g6]
            if !all(g1through6)
                description = "New package. Failed."
                params = Dict("state" => "failure",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(registry,
                                                    current_pr_head_commit_sha;
                                                    auth = auth,
                                                    params = params))
            end
            g7, m7 = meets_version_can_be_pkg_added(registry_head,
                                                    pkg,
                                                    version)
            @info("Version can be `Pkg.add`ed",
                  meets_this_guideline = g7,
                  message = m7)
            g8, m8 = meets_version_can_be_imported(registry_head,
                                                   pkg,
                                                   version)
            @info("Version can be `import`ed,
                  meets_this_guideline = g8,
                  message = m8)
            g1through8 = [g1, g2, g3, g4, g5, g6, g7, g8]
            allmessages1through8 = [m1, m2, m3, m4, m5, m7, m8]
            if all(g1through8) # success
                description = "New package. Approved. sha=\"$(current_pr_head_commit_sha)\""
                params = Dict("state" => "success",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(registry,
                                                    current_pr_head_commit_sha;
                                                    auth = auth,
                                                    params = params))
                this_pr_comment_pass = comment_text_pass(NewPackage(),
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
                description = "New package. Failed."
                params = Dict("state" => "failure",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(registry,
                                                    current_pr_head_commit_sha;
                                                    auth = auth,
                                                    params = params))
                failingmessages1through8 = allmessages1through8[.!g1through8]
                this_pr_comment_fail = comment_text_fail(NewPackage(),
                                                         failingmessages1through8,
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
