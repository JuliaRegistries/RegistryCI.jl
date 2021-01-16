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
    @info("This is a new package pull request",
          pkg = data.pkg,
          version = data.version,
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

    jll_only_authorization = (!this_is_jll_package
                              && pr_author_login ∉ data.authorized_authors)

    # Each element is a tuple of a guideline and whether it's
    # applicable. Instead of a guideline there can be the symbol
    # `:update_status` in which case the PR status will be updated
    # with the results so far before continuing to the following
    # guidelines.
    guidelines =
        [(guideline_jll_only_authorization, jll_only_authorization), #0
         (guideline_pr_only_changes_allowed_files, true), # 1
         (guideline_sequential_version_number,
          !this_pr_can_use_special_jll_exceptions), # 2
         (guideline_compat_for_all_deps, true), # 3
         (guideline_patch_release_does_not_narrow_julia_compat,
          !this_pr_can_use_special_jll_exceptions), # 4
         (guideline_allowed_jll_nonrecursive_dependencies,
          this_is_jll_package), # 5
         (:update_status, true),
         (guideline_version_can_be_pkg_added, true), # 6
         (guideline_version_can_be_imported, true)] # 7

    checked_guidelines = Guideline[]

    for (guideline, applicable) in guidelines
        applicable || continue
        if guideline == :update_status
            if !all(passed, checked_guidelines)
                update_status(data;
                              state = "failure",
                              context = "automerge/decision",
                              description = "New version. Failed.")
            end
        else
            check!(guideline, data)
            @info(guideline.info,
                  meets_this_guideline = passed(guideline),
                  message = message(guideline))
            push!(checked_guidelines, guideline)
        end
    end

    if all(passed, checked_guidelines) # success
        description = "New version. Approved. name=\"$(data.pkg)\". sha=\"$(data.current_pr_head_commit_sha)\""
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
        failing_messages = message.(filter(!passed, checked_guidelines))
        this_pr_comment_fail = comment_text_fail(data.registration_type,
                                                 failing_messages,
                                                 data.suggest_onepointzero,
                                                 data.version)
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_fail))
        throw(AutoMergeGuidelinesNotMet("The automerge guidelines were not met."))
    end
    return nothing
end
