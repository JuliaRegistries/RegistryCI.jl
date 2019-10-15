function allowed_changed_files(::NewPackage, pkg::String)
    first_letter = uppercase(pkg[1:1])
    result = String["Registry.toml",
                    "$(first_letter)/$(pkg)/Compat.toml",
                    "$(first_letter)/$(pkg)/Deps.toml",
                    "$(first_letter)/$(pkg)/Package.toml",
                    "$(first_letter)/$(pkg)/Versions.toml"]
    return result
end

function allowed_changed_files(::NewVersion, pkg::String)
    first_letter = uppercase(pkg[1:1])
    result = String["$(first_letter)/$(pkg)/Compat.toml",
                    "$(first_letter)/$(pkg)/Deps.toml",
                    "$(first_letter)/$(pkg)/Versions.toml"]
    return result
end

function pr_only_changes_allowed_files(t::Union{NewPackage, NewVersion},
                                       registry::GitHub.Repo,
                                       pr::GitHub.PullRequest,
                                       pkg::String;
                                       auth::GitHub.Authorization)
    _allowed_changed_files = allowed_changed_files(t, pkg)
    _num_allowed_changed_files = length(_allowed_changed_files)
    this_pr_num_changed_files = num_changed_files(pr)
    if this_pr_num_changed_files > _num_allowed_changed_files
        g0 = false
        m0 = "This PR is allowed to modify at most $(_num_allowed_changed_files) files, but it actually modified $(this_pr_num_changed_files) files."
        return g0, m0
    else
        this_pr_changed_files = get_changed_filenames(registry, pr; auth = auth)
        if length(this_pr_changed_files) != this_pr_num_changed_files
            g0 = false
            m0 = "Something weird happened when I tried to get the list of changed files"
            return g0, m0
        else
            if issubset(this_pr_changed_files, _allowed_changed_files)
                g0 = true
                m0 = ""
                return g0, m0
            else
                g0 = false
                m0 = string("This pull request modified at least one file ",
                            "that it is not allowed to modify. It is only ",
                            "allowed to modify the following files ",
                            "(or a subset thereof): ",
                            "$(join(_allowed_changed_files, ", "))")
                return g0, m0
            end
        end
    end
end
