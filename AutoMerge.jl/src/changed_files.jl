function allowed_changed_files(::NewPackage, pkg::String)
    _package_relpath_per_scheme = _get_package_relpath_per_name_scheme(; package_name=pkg)
    result = String[
        "Registry.toml",
        "$(_package_relpath_per_scheme)/Compat.toml",
        "$(_package_relpath_per_scheme)/WeakCompat.toml",
        "$(_package_relpath_per_scheme)/Deps.toml",
        "$(_package_relpath_per_scheme)/WeakDeps.toml",
        "$(_package_relpath_per_scheme)/Package.toml",
        "$(_package_relpath_per_scheme)/Versions.toml",
    ]
    return result
end

function allowed_changed_files(::NewVersion, pkg::String)
    _package_relpath_per_scheme = _get_package_relpath_per_name_scheme(; package_name=pkg)
    result = String[
        "$(_package_relpath_per_scheme)/Compat.toml",
        "$(_package_relpath_per_scheme)/WeakCompat.toml",
        "$(_package_relpath_per_scheme)/Deps.toml",
        "$(_package_relpath_per_scheme)/WeakDeps.toml",
        "$(_package_relpath_per_scheme)/Versions.toml",
    ]
    return result
end

const guideline_pr_only_changes_allowed_files = Guideline(;
    info="Only modifies the files that it's allowed to modify.",
    docs=nothing,
    check=data -> pr_only_changes_allowed_files(
        data.api,
        data.registration_type,
        data.registry,
        data.pr,
        data.pkg;
        auth=data.auth,
    ),
)

function pr_only_changes_allowed_files(
    api::GitHub.GitHubAPI,
    t::Union{NewPackage,NewVersion},
    registry::GitHub.Repo,
    pr::GitHub.PullRequest,
    pkg::String;
    auth::GitHub.Authorization,
)
    _allowed_changed_files = allowed_changed_files(t, pkg)
    _num_allowed_changed_files = length(_allowed_changed_files)
    this_pr_num_changed_files = num_changed_files(pr)
    if this_pr_num_changed_files > _num_allowed_changed_files
        g0 = false
        m0 = "This PR is allowed to modify at most $(_num_allowed_changed_files) files, but it actually modified $(this_pr_num_changed_files) files."
        return g0, m0
    else
        this_pr_changed_files = get_changed_filenames(api, registry, pr; auth=auth)
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
                m0 = string(
                    "This pull request modified at least one file ",
                    "that it is not allowed to modify. It is only ",
                    "allowed to modify the following files ",
                    "(or a subset thereof): ",
                    "$(join(_allowed_changed_files, ", "))",
                )
                return g0, m0
            end
        end
    end
end
