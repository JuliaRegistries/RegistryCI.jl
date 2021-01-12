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
    pkg, version = data.pkg, data.version
    @info("This is a new package pull request", pkg, version,
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

    guidelines = Guideline[]
    if !this_is_jll_package && pr_author_login ∉ data.authorized_authors
        push!(guidelines,
              guideline_jll_only_authorization) # 0
    end

    push!(guidelines,
          guideline_pr_only_changes_allowed_files) # 1

    if !this_pr_can_use_special_jll_exceptions
        push!(guidelines,
              guideline_sequential_version_number) # 2
    end

    push!(guidelines,
          guideline_compat_for_all_deps) # 3

    if !this_pr_can_use_special_jll_exceptions
        push!(guidelines,
              guideline_patch_release_does_not_narrow_julia_compat) # 4
    end

    push!(guidelines,
          guideline_allowed_jll_nonrecursive_dependencies) # 5

    for guideline in guidelines
        check!(guideline)
        @info(guideline.info,
              meets_this_guideline = passed(guideline),
              message = message(guideline))
    end

    if !all(passed, guidelines)
        update_status(data;
                      state = "failure",
                      context = "automerge/decision",
                      description = "New version. Failed.")
    end

    push!(guidelines,
          guideline_version_can_be_pkg_added, # 6
          guideline_version_can_be_imported) # 7

    for guideline in guidelines[end-1:end]
        check!(guideline)
        @info(guideline.info,
              meets_this_guideline = passed(guideline),
              message = message(guideline))
    end

    if all(passed, guidelines) # success
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
        failing_messages = messages.(filter(!passed, guidelines))
        this_pr_comment_fail = comment_text_fail(data.registration_type,
                                                 failing_messages,
                                                 data.suggest_onepointzero,
                                                 data.version)
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_fail))
        throw(AutoMergeGuidelinesNotMet("The automerge guidelines were not met."))
    end
    return nothing
end
