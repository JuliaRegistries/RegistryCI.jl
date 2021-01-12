function pull_request_build(data::GitHubAutoMergeData, ::NewVersion)::Nothing
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
    pr_author_login = author_login(data.pr)
    this_is_jll_package = is_jll_name(data.pkg)
    @info("This is a new package pull request", data.pkg, data.version,
          this_is_jll_package)

    update_status(data;
                  state = "pending",
                  context = "automerge/decision",
                  description = "New version. Pending.")

    if this_is_jll_package
        if pr_author_login in data.authorized_authors_special_jll_exceptions
            this_pr_can_use_special_jll_exceptions = true
        else
            this_pr_can_use_special_jll_exceptions = false
        end
    else
        this_pr_can_use_special_jll_exceptions = false
    end

    G0 = guideline_jll_only_authorization
    if this_is_jll_package
        g0 = true
        m0 = ""
    else
        if pr_author_login in data.authorized_authors
            g0 = true
            m0 = ""
        else
            g0, m0 = check!(G0)
        end
    end

    G1 = guideline_pr_only_changes_allowed_files
    g1, m1 = check!(G1)

    G2 = guideline_sequential_version_number

    if this_pr_can_use_special_jll_exceptions
        g2 = true
        m2 = ""
    else
        g2, m2 = check!(G2)
    end

    G3 = guideline_compat_for_all_deps
    g3, m3 = check!(G3)

    G4 = guideline_patch_release_does_not_narrow_julia_compat
    if this_pr_can_use_special_jll_exceptions
        g4 = true
        m4 = ""
    else
        g4, m4 = check!(G4)
    end

    G5 = guideline_allowed_jll_nonrecursive_dependencies
    if this_is_jll_package
        g5, m5 = check!(G5)
    else
        g5 = true
        m5 = ""
    end

    @info(G0.info,
          meets_this_guideline = g0,
          message = m0)
    @info(G1.info,
          meets_this_guideline = g1,
          message = m1)
    @info(G2.info,
          meets_this_guideline = g2,
          message = m2)
    @info(G3.info,
          meets_this_guideline = g3,
          message = m3)
    @info(G4.info,
          meets_this_guideline = g4,
          message = m4)
    @info(G5.info,
          meets_this_guideline = g5,
          message = m5)
    g0through5 = Bool[g0,
                      g1,
                      g2,
                      g3,
                      g4,
                      g5]
    if !all(g0through5)
        update_status(data;
                      state = "failure",
                      context = "automerge/decision",
                      description = "New version. Failed.")
    end

    G6 = guideline_version_can_be_pkg_added
    g6, m6 = check!(G6)
    @info(G6.info,
          meets_this_guideline = g6,
          message = m6)

    G7 = guideline_version_can_be_imported
    g7, m7 = check!(G7)
    @info(G7.info,
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
        update_status(data;
                      state = "success",
                      context = "automerge/decision",
                      description = description)
        this_pr_comment_pass = comment_text_pass(data.registration_type,
                                                 data.suggest_onepointzero,
                                                 version)
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_pass))
    else # failure
        update_status(data;
                      state = "failure",
                      context = "automerge/decision",
                      description = "New version. Failed.")
        failingmessages0through7 = allmessages0through7[.!g0through7]
        this_pr_comment_fail = comment_text_fail(data.registration_type,
                                                 failingmessages0through7,
                                                 data.suggest_onepointzero,
                                                 data.version)
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_fail))
        throw(AutoMergeGuidelinesNotMet("The automerge guidelines were not met."))
    end
    return nothing
end
