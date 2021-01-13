# TODO: Probably want to get rid of this pseudo-guideline.
const guideline_unimplemented =
    Guideline("TODO: implement this check",
              data -> (true, ""))

# TODO: This function should probably be moved to some other file,
#       unless new_package.jl and new_version.jl are merged into one.
function update_status(data::GitHubAutoMergeData; kwargs...)
    my_retry(() -> GitHub.create_status(data.api,
                                        data.registry,
                                        data.current_pr_head_commit_sha;
                                        auth = data.auth,
                                        params = Dict(kwargs...)))
end

function pull_request_build(data::GitHubAutoMergeData, ::NewPackage)::Nothing
    # Rules:
    # 0. A JLL-only author (e.g. `jlbuild`) is not allowed to register non-JLL packages.
    # 1. Only changes a subset of the following files:
    #     - `Registry.toml`,
    #     - `E/Example/Compat.toml`
    #     - `E/Example/Deps.toml`
    #     - `E/Example/Package.toml`
    #     - `E/Example/Versions.toml`
    # 2. TODO: implement this check. When implemented, this check will make sure that the changes to `Registry.toml` only modify the specified package.
    # 3. Normal capitalization
    #     - name should match r"^[A-Z]\w*[a-z]\w*[0-9]?$"
    #     - i.e. starts with a capital letter, ASCII alphanumerics only, contains at least 1 lowercase letter
    # 4. Not too short
    #     - at least five letters
    #     - you can register names shorter than this, but doing so requires someone to approve
    # 5. Meets julia name check
    #     - does not include the string "julia" with any case
    #     - does not start with "Ju"
    # 6. DISABLED. Standard initial version number - one of 0.0.1, 0.1.0, 1.0.0, X.0.0
    #     - does not apply to JLL packages
    # 7. DISABLED. Repo URL ends with /$name.jl.git where name is the package name. Now that we have support for multiple packages in different subdirectories of a repo, we have disabled this check.
    # 8. Compat for all dependencies
    #     - there should be a [compat] entry for Julia
    #     - all [deps] should also have [compat] entries
    #     - all [compat] entries should have upper bounds
    #     - dependencies that are standard libraries do not need [compat] entries
    #     - dependencies that are JLL packages do not need [compat] entries
    # 9. (only applies to JLL packages) The only dependencies of the package are:
    #     - Pkg
    #     - Libdl
    #     - other JLL packages
    # 10. Package's name is sufficiently far from existing package names in the registry
    #     - We exclude JLL packages from the "existing names"
    #     - We use three checks:
    #         - that the lowercased name is at least 1 away in Damerau Levenshtein distance from any other lowercased name
    #         - that the name is at least 2 away in Damerau Levenshtein distance from any other name
    #         - that the name is sufficiently far in a visual distance from any other name
    # 11. Package's name has only ASCII characters
    # 12. Version can be installed
    #     - given the proposed changes to the registry, can we resolve and install the new version of the package?
    #     - i.e. can we run `Pkg.add("Foo")`
    # 13. Version can be loaded
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
                  description = "New package. Pending.")

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
          guideline_pr_only_changes_allowed_files, # 1
          guideline_unimplemented) # 2

    if !this_pr_can_use_special_jll_exceptions
        push!(guidelines,
              guideline_normal_capitalization, # 3
              guideline_name_length) # 4
    end

    push!(guidelines,
          guideline_julia_name_check) # 5

    if !this_pr_can_use_special_jll_exceptions
        # push!(guidelines,
        #       guideline_standard_initial_version_number) # 6
    end

    push!(guidelines,
          # guideline_repo_url_requirement, #7
          guideline_compat_for_all_deps) #8

    if this_is_jll_package
        push!(guidelines,
              guideline_allowed_jll_nonrecursive_dependencies) # 9
    end

    push!(guidelines,
          guideline_distance_check, # 10
          guideline_name_ascii) # 11

    for guideline in guidelines
        check!(guideline, data)
        @info(guideline.info,
              meets_this_guideline = passed(guideline),
              message = message(guideline))
    end

    if !all(passed, guidelines)
        update_status(data;
                      state = "failure",
                      context = "automerge/decision",
                      description = "New package. Failed.")
    end

    push!(guidelines,
          guideline_version_can_be_pkg_added, # 12
          guideline_version_can_be_imported) # 13

    for guideline in guidelines[end-1:end]
        check!(guideline, data)
        @info(guideline.info,
              meets_this_guideline = passed(guideline),
              message = message(guideline))
    end

    if all(passed, guidelines) # success
        description = "New package. Approved. name=\"$(data.pkg)\". sha=\"$(data.current_pr_head_commit_sha)\""
        update_status(data;
                      state = "success",
                      context = "automerge/decision",
                      description = description)
        this_pr_comment_pass = comment_text_pass(data.registration_type,
                                                 data.suggest_onepointzero,
                                                 data.version,
                                                 this_pr_can_use_special_jll_exceptions)
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_pass))
    else # failure
        update_status(data;
                      state = "failure",
                      context = "automerge/decision",
                      description = "New package. Failed.")
        failing_messages = message.(filter(!passed, guidelines))
        this_pr_comment_fail = comment_text_fail(data.registration_type,
                                                 failing_messages,
                                                 data.suggest_onepointzero,
                                                 data.version)
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_fail))
        throw(AutoMergeGuidelinesNotMet("The automerge guidelines were not met."))
    end
    return nothing
end
