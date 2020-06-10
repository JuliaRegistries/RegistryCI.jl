function pull_request_build(api::GitHub.GitHubAPI,
                            ::NewVersion,
                            pr::GitHub.PullRequest,
                            current_pr_head_commit_sha::String,
                            registry::GitHub.Repo;
                            auth::GitHub.Authorization,
                            authorized_authors::Vector{String},
                            authorized_authors_special_jll_exceptions::Vector{String},
                            registry_head::String,
                            registry_master::String,
                            suggest_onepointzero::Bool,
                            whoami::String,
                            registry_deps::Vector{<:AbstractString} = String[])::Nothing
    # first check if the PR is open, and the author is authorized - if not, then quit
    # if the PR is open and the author is authorized, then check rules 0 through 7.
    # Rules:
    # 0. A JLL-only author (e.g. `jlbuild`) is not allowed to register non-JLL packages.
    # 1. Only changes a subset of the following files:
    #     - `E/Example/Compat.toml`
    #     - `E/Example/Deps.toml`
    #     - `E/Example/Versions.toml`
    # 2. Sequential version number
    #     - if the last version was 1.2.3 then the next can be 1.2.4, 1.3.0 or 2.0.0
    #     - does not apply to JLL packages
    # 3. Compat for all dependencies
    #     - there should be a [compat] entry for Julia
    #     - all [deps] should also have [compat] entries
    #     - all [compat] entries should have upper bounds
    #     - dependencies that are standard libraries do not need [compat] entries
    #     - dependencies that are JLL packages do not need [compat] entries
    # 4. If it is a patch release, then it does not narrow the Julia compat range
    # 5. (only applies to JLL packages) The only dependencies of the package are:
    #     - Pkg
    #     - Libdl
    #     - other JLL packages
    # 6. Version can be installed
    #     - given the proposed changes to the registry, can we resolve and install the new version of the package?
    #     - i.e. can we run `Pkg.add("Foo")`
    # 7. Version can be loaded
    #     - once it's been installed (and built?), can we load the code?
    #     - i.e. can we run `import Foo`
    pkg, version = parse_pull_request_title(NewVersion(), pr)
    this_is_jll_package = is_jll_name(pkg)
    @info("This is a new package pull request", pkg, version, this_is_jll_package)
    pr_author_login = author_login(pr)
    if is_open(pr)
        if pr_author_login in vcat(authorized_authors, authorized_authors_special_jll_exceptions)
            description = "New version. Pending."
            params = Dict("state" => "pending",
                          "context" => "automerge/decision",
                          "description" => description)
            my_retry(() -> GitHub.create_status(api, registry,
                                                current_pr_head_commit_sha;
                                                auth = auth,
                                                params=params))

            if this_is_jll_package
                if pr_author_login in authorized_authors_special_jll_exceptions
                    this_pr_can_use_special_jll_exceptions = true
                else
                    this_pr_can_use_special_jll_exceptions = false
                end
            else
                this_pr_can_use_special_jll_exceptions = false
            end

            if this_is_jll_package
                g0 = true
                m0 = ""
            else
                if pr_author_login in authorized_authors
                    g0 = true
                    m0 = ""
                else
                    g0 = false
                    m0 = "This package is not a JLL package. The author of this pull request is not authorized to register non-JLL packages."
                end
            end

            g1, m1 = pr_only_changes_allowed_files(api,
                                                   NewVersion(),
                                                   registry,
                                                   pr,
                                                   pkg;
                                                   auth = auth)
            if this_pr_can_use_special_jll_exceptions
                g2 = true
                m2 = ""
                release_type = :jll_release
            else
                g2, m2, release_type = meets_sequential_version_number(pkg,
                                                                       version;
                                                                       registry_head = registry_head,
                                                                       registry_master = registry_master)
            end
            g3, m3 = meets_compat_for_all_deps(registry_head,
                                               pkg,
                                               version)
            g4_if_patch, m4_if_patch = meets_patch_release_does_not_narrow_julia_compat(pkg,
                                                                                        version;
                                                                                        registry_head = registry_head,
                                                                                        registry_master = registry_master)
            if release_type == :patch
                g4 = g4_if_patch
                m4 = m4_if_patch
            else
                g4 = true
                m4 = ""
            end
            g5_if_jll, m5_if_jll = meets_allowed_jll_nonrecursive_dependencies(registry_head,
                                                                               pkg,
                                                                               version)
            if this_is_jll_package
                g5 = g5_if_jll
                m5 = m5_if_jll
            else
                g5 = true
                m5 = ""
            end

            @info("JLL-only authors cannot register non-JLL packages.",
                  meets_this_guideline = g0,
                  message = m0)
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
            @info("If this is a JLL package, only deps are Pkg, Libdl, and other JLL packages",
                  meets_this_guideline = g5,
                  message = m5)
            g0through5 = Bool[g0,
                              g1,
                              g2,
                              g3,
                              g4,
                              g5]
            if !all(g0through5)
                description = "New version. Failed."
                params = Dict("state" => "failure",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(api, registry,
                                                    current_pr_head_commit_sha;
                                                    auth = auth,
                                                    params = params))
            end
            g6, m6 = meets_version_can_be_pkg_added(registry_head,
                                                    pkg,
                                                    version;
                                                    registry_deps = registry_deps)
            @info("Version can be `Pkg.add`ed",
                  meets_this_guideline = g6,
                  message = m6)
            g7, m7 = meets_version_can_be_imported(registry_head,
                                                   pkg,
                                                   version;
                                                   registry_deps = registry_deps)
            @info("Version can be `import`ed",
                  meets_this_guideline = g7,
                  message = m7)
            g0through7 = Bool[g0,
                              g1,
                              g2,
                              g3,
                              g4,
                              g5,
                              g6,
                              g7]
            allmessages0through7 = String[m0,
                                          m1,
                                          m2,
                                          m3,
                                          m4,
                                          m5,
                                          m6,
                                          m7]
            if all(g0through7) # success
                description = "New version. Approved. name=\"$(pkg)\". sha=\"$(current_pr_head_commit_sha)\""
                params = Dict("state" => "success",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(api,
                                                    registry,
                                                    current_pr_head_commit_sha;
                                                    auth = auth,
                                                    params = params))
                this_pr_comment_pass = comment_text_pass(NewVersion(),
                                                         suggest_onepointzero,
                                                         version)
                my_retry(() -> update_automerge_comment!(api,
                                                         registry,
                                                         pr;
                                                         auth = auth,
                                                         body = this_pr_comment_pass,
                                                         whoami = whoami))
                return nothing
            else # failure
                description = "New version. Failed."
                params = Dict("state" => "failure",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(api, registry,
                                                    current_pr_head_commit_sha;
                                                    auth=auth,
                                                    params=params))
                failingmessages0through7 = allmessages0through7[.!g0through7]
                this_pr_comment_fail = comment_text_fail(NewVersion(),
                                                         failingmessages0through7,
                                                         suggest_onepointzero,
                                                         version)
                my_retry(() -> update_automerge_comment!(api,
                                                         registry,
                                                         pr;
                                                         body = this_pr_comment_fail,
                                                         auth = auth,
                                                         whoami = whoami))
                throw(AutoMergeGuidelinesNotMet("The automerge guidelines were not met."))
            end
        else
            throw(AutoMergeAuthorNotAuthorized("Author $(pr_author_login) is not authorized to automerge. Exiting..."))
        end
    else
        throw(AutoMergePullRequestNotOpen("The pull request is not open. Exiting..."))
    end
end
