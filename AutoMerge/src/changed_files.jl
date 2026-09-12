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

# Package.toml is only allowed to change subdir information, which is
# checked separately.
function allowed_changed_files(::NewVersion, pkg::String)
    _package_relpath_per_scheme = _get_package_relpath_per_name_scheme(; package_name=pkg)
    result = String[
        "$(_package_relpath_per_scheme)/Compat.toml",
        "$(_package_relpath_per_scheme)/WeakCompat.toml",
        "$(_package_relpath_per_scheme)/Deps.toml",
        "$(_package_relpath_per_scheme)/WeakDeps.toml",
        "$(_package_relpath_per_scheme)/Package.toml",
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
    changed_files = get_changed_files(api, registry, pr; auth)
    changed_filenames = [file.filename for file in changed_files]

    if !issubset(changed_filenames, allowed_changed_filenames)
        message = string(
            "This pull request modified at least one file ",
            "that it is not allowed to modify. It is only ",
            "allowed to modify the following files ",
            "(or a subset thereof): ",
            "$(join(_allowed_changed_files, ", "))",
        )
        return false, message
    end

    if !check_package_toml_changes(t, changed_files)
        message = "This pull request modified Package.toml and changed something other than subdir, which is not allowed."
        return false, message
    end

    return true, ""
end

# No restrictions for new packages.
check_package_toml_changes(::NewPackage, _) = true

# New versions may only change subdir information in Package.toml.
#
# (Currently Registrator wouldn't change anything else, so this is
# some extra safety belt against future Registrator/RegistryTools
# changes or someone managing to forge a Registrator PR.)
function check_package_toml_changes(::NewVersion, changed_files)
    for file in changed_files
        if basename(file.filename) == "Package.toml"
            for line in vcat(get_removed_lines(file), get_added_lines(file))
                if !startswith(line, "subdir")
                    return false
                end
            end
        end
    end
    return true
end
