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
    @info("This is a new package pull request", data.pkg, data.version,
          data.this_is_jll_package)

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

    guideline_jll_only_authorization =
        Guideline("JLL-only authors cannot register non-JLL packages.",
                  data -> (false, "This package is not a JLL package. The author of this pull request is not authorized to register non-JLL packages."))
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

    guideline_pr_only_changes_allowed_files =
        Guideline("Only modifies the files that it's allowed to modify",
                  data -> pr_only_changes_allowed_files(data.api,
                                                        data.registration_type,
                                                        data.registry,
                                                        data.pr,
                                                        data.pkg;
                                                        auth = data.auth))

    G1 = guideline_pr_only_changes_allowed_files
    g1, m1 = check!(G1)

    guideline_unimplemented =
        Guideline("TODO: implement this check",
                  data -> (true, ""))
    G2 = guideline_unimplemented
    g2, m2 = check!(G2)

    guideline_normal_capitalization =
        Guideline("Normal capitalization",
                  data -> meets_normal_capitalization(data.pkg))
    G3 = guideline_normal_capitalization

    guideline_name_length =
        Guideline("Name not too short",
                  data -> meets_name_length(data.pkg))
    G4 = guideline_name_length

    if this_pr_can_use_special_jll_exceptions
        g3 = true
        g4 = true
        m3 = ""
        m4 = ""
    else
        g3, m3 = check!(G3)
        g4, m4 = check!(G4)
    end

    guideline_julia_name_check =
        Guideline("Name does not include \"julia\" or start with \"Ju\"",
                  data -> meets_julia_name_check(data.pkg))
    G5 = guideline_julia_name_check
    g5, m5 = check!(G5)

    guideline_standard_initial_version_number =
        Guideline("Standard initial version number ",
                  data -> meets_standard_initial_version_number(data.version))
    G6 = guideline_standard_initial_version_number
    if this_pr_can_use_special_jll_exceptions
        g6 = true
        m6 = ""
    else
        # g6, m6 = check!(G6)
        g6 = true
        m6 = ""
    end

    guideline_repo_url_requirement =
        Guideline("Repo URL ends with /name.jl.git",
                  data -> meets_repo_url_requirement(data.pkg;
                                                     registry_head = data.registry_head))
    G7 = guideline_repo_url_requirement
    # g7, m7 = check!(G7)
    g7 = true
    m7 = ""

    guideline_compat_for_all_deps =
        Guideline("Compat (with upper bound) for all dependencies",
                  data -> meets_compat_for_all_deps(data.registry_head,
                                                    data.pkg,
                                                    data.version))
    G8 = guideline_compat_for_all_deps
    g8, m8 = check!(G8)

    guideline_allowed_jll_nonrecursive_dependencies =
        Guideline("If this is a JLL package, only deps are Pkg, Libdl, and other JLL packages",
                  data -> meets_allowed_jll_nonrecursive_dependencies(data.registry_head,
                                                                      data.pkg,
                                                                      data.version))
    G9 = guideline_allowed_jll_nonrecursive_dependencies
    if this_is_jll_package
        g9, m9 = check!(G9)
    else
        g9 = true
        m9 = ""
    end

    guideline_distance_check =
        Guideline("Name is not too similar to existing package names",
                  data -> meets_distance_check(data.pkg, data.registry_master))
    G10 = guideline_distance_check
    g10, m10 = check!(G10)

    guideline_name_ascii =
        Guideline("Name is composed of ASCII characters only",
                  data -> meets_name_ascii(data.pkg))
    G11 = guideline_name_ascii
    g11, m11 = check!(G11)

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
    @info(G6.info,
          meets_this_guideline = g6,
          message = m6)
    @info(G7.info,
          meets_this_guideline = g7,
          message = m7)
    @info(G8.info,
          meets_this_guideline = g8,
          message = m8)
    @info(G9.info,
          meets_this_guideline = g9,
          message = m9)
    @info(G10.info,
          meets_this_guideline = g10,
          message = m10)
    @info(G11.info,
          meets_this_guideline = g11,
          message = m11)
    g0through11 = Bool[g0,
                      g1,
                      g2,
                      g3,
                      g4,
                      g5,
                      g6,
                      g7,
                      g8,
                      g9,
                      g10,
                      g11]
    if !all(g0through11)
        update_status(data;
                      state = "failure",
                      context = "automerge/decision",
                      description = "New package. Failed.")
    end

    guideline_version_can_be_pkg_added =
        Guideline("Version can be `Pkg.add`ed",
                  data -> meets_version_can_be_pkg_added(data.registry_head,
                                                         data.pkg,
                                                         data.version;
                                                         registry_deps = data.registry_deps))
    G12 = guideline_version_can_be_pkg_added
    g12, m12 = check!(G12)
    @info(G12.info,
          meets_this_guideline = g12,
          message = m12)

    guideline_version_can_be_imported =
        Guideline("Version can be `import`ed",
                  data -> meets_version_can_be_imported(data.registry_head,
                                           data.pkg,
                                           data.version;
                                           registry_deps = data.registry_deps))
    G13 = guideline_version_can_be_imported
    g13, m13 = check!(G13)
    @info(G13.info,
          meets_this_guideline = g13,
          message = m13)

    g0through13 = Bool[g0,
                       g1,
                       g2,
                       g3,
                       g4,
                       g5,
                       g6,
                       g7,
                       g8,
                       g9,
                       g10,
                       g11,
                       g12,
                       g13]
    allmessages0through13 = String[m0,
                                   m1,
                                   m2,
                                   m3,
                                   m4,
                                   m5,
                                   m6,
                                   m7,
                                   m8,
                                   m9,
                                   m10,
                                   m11,
                                   m12,
                                   m13]
    if all(g0through13) # success
        description = "New package. Approved. name=\"$(pkg)\". sha=\"$(current_pr_head_commit_sha)\""
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
        failingmessages0through13 = allmessages0through13[.!g0through13]
        this_pr_comment_fail = comment_text_fail(data.registration_type,
                                                 failingmessages0through13,
                                                 data.suggest_onepointzero,
                                                 data.version)
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_fail))
        throw(AutoMergeGuidelinesNotMet("The automerge guidelines were not met."))
    end
    return nothing
end
