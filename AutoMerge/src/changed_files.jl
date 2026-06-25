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
    allowed_changed_filenames = allowed_changed_files(t, pkg)
    this_pr_changed_filenames = get_changed_filenames(api, registry, pr; auth=auth)

    if !issubset(this_pr_changed_filenames, allowed_changed_filenames)
        message = string(
            "This pull request modified at least one file ",
            "that it is not allowed to modify. It is only ",
            "allowed to modify the following files ",
            "(or a subset thereof): ",
            "$(join(allowed_changed_filenames, ", "))",
        )
        return false, message
    end

    return true, ""
end
