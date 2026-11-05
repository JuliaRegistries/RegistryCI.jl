#####
##### Versions added by a pull request, derived from the registry diff
#####

# All versions of `pkg` in the registry at `registry_path`; empty if `pkg` is not registered there.
function registered_versions(pkg::String, registry_path::String)
    packages = parse_registry_toml(registry_path, "Registry.toml")["packages"]
    any(p -> p["name"] == pkg, values(packages)) || return VersionNumber[]
    return sort!(all_versions(pkg, registry_path))
end

"""
    versions_added_by_pr(pkg; registry_master, registry_head) -> Vector{VersionNumber}

The versions of `pkg` that are in `registry_head` but not in `registry_master`, sorted ascending.
"""
function versions_added_by_pr(pkg::String; registry_master::String, registry_head::String)
    head_versions = registered_versions(pkg, registry_head)
    master_versions = registered_versions(pkg, registry_master)
    return sort!(setdiff(head_versions, master_versions))
end

"""
    versions_preceding_in_pr(pkg, version; registry_master, registry_head) -> Vector{VersionNumber}

The versions that `version` should be compared against by the version-number guidelines:
every version already in `registry_master`, plus the versions below `version` that the
same pull request adds. For a pull request that adds a single version this is just the
versions in `registry_master`.
"""
function versions_preceding_in_pr(
    pkg::String, version::VersionNumber; registry_master::String, registry_head::String
)
    master_versions = registered_versions(pkg, registry_master)
    added_below = filter(<(version), versions_added_by_pr(pkg; registry_master, registry_head))
    return sort!(unique!(vcat(master_versions, added_below)))
end

#####
##### The registry diff must match the pull request title
#####

const guideline_registry_changes_match_title = Guideline(;
    info="The versions added to the registry are exactly the ones named in the title, and no existing registry entries are changed.",
    docs=nothing,
    check=data -> meets_registry_changes_match_title(
        data.api,
        data.registry,
        data.pr,
        data.registration_type;
        auth=data.auth,
        registry_master=data.registry_master,
        registry_head=data.registry_head,
    ),
)

function meets_registry_changes_match_title(
    api::GitHub.GitHubAPI,
    registry::GitHub.Repo,
    pr::GitHub.PullRequest,
    registration_type::Union{NewPackage,NewVersion};
    auth::GitHub.Authorization,
    registry_master::String,
    registry_head::String,
)
    pkg, title_versions = parse_pull_request_title_versions(registration_type, pr)
    if num_changed_files(pr) > length(allowed_changed_files(registration_type, pkg))
        return false, "This pull request changes more files than a registration of $(pkg) may change, so I did not compare its registry changes with its title."
    end
    changed_files = get_changed_filenames(api, registry, pr; auth=auth)
    if length(changed_files) != num_changed_files(pr)
        return false, "Something weird happened when I tried to get the list of changed files"
    end
    return meets_registry_changes_match_title(
        changed_files, pkg, title_versions; registry_master, registry_head
    )
end

_load_toml_or_empty(path) = isfile(path) ? TOML.parsefile(path) : Dict{String,Any}()

# Values of a compressed `Compat.toml`-like file, made comparable across different but
# equivalent ways of writing the same version ranges.
function _normalize_compat_value(value)
    try
        return Pkg.Types.VersionSpec(value)
    catch
        return value
    end
end

function _uncompressed_entries(path::String, versions::Vector{VersionNumber}, is_compat::Bool)
    isfile(path) || return Dict{VersionNumber,Dict{Any,Any}}()
    uncompressed = RegistryTools.Compress.load(path, versions)
    if is_compat
        for entries in values(uncompressed), k in collect(keys(entries))
            entries[k] = _normalize_compat_value(entries[k])
        end
    end
    return uncompressed
end

"""
    meets_registry_changes_match_title(changed_files, pkg, title_versions; registry_master, registry_head)

Check the registry diff of a registration pull request against its title:

- every `Versions.toml` entry the pull request adds belongs to `pkg`, and the added versions,
  in ascending order, are exactly `title_versions`;
- no existing `Versions.toml` entry is removed or modified;
- the `Deps.toml`, `Compat.toml`, `WeakDeps.toml` and `WeakCompat.toml` data of versions
  that already exist in `registry_master` is unchanged;
- if `Registry.toml` changes, the only change is adding `pkg`.

`changed_files` lists the paths (relative to the registry root) that the pull request changes.
"""
function meets_registry_changes_match_title(
    changed_files::AbstractVector{<:AbstractString},
    pkg::String,
    title_versions::Vector{VersionNumber};
    registry_master::String,
    registry_head::String,
)
    problems = String[]
    added = Dict{String,Vector{VersionNumber}}()

    if "Registry.toml" in changed_files
        master_packages = parse_registry_toml(registry_master, "Registry.toml")["packages"]
        head_packages = parse_registry_toml(registry_head, "Registry.toml")["packages"]
        for (uuid, entry) in master_packages
            if get(head_packages, uuid, nothing) != entry
                push!(problems, "It changes or removes the existing `Registry.toml` entry of $(entry["name"]).")
            end
        end
        for (uuid, entry) in head_packages
            haskey(master_packages, uuid) && continue
            if entry["name"] != pkg
                push!(problems, "It adds $(entry["name"]) to `Registry.toml`, but its title names $(pkg).")
            end
        end
    end

    package_dirs = unique(dirname(f) for f in changed_files if f != "Registry.toml")
    for dir in package_dirs
        head_versions_toml = _load_toml_or_empty(joinpath(registry_head, dir, "Versions.toml"))
        master_versions_toml = _load_toml_or_empty(joinpath(registry_master, dir, "Versions.toml"))
        package_toml = _load_toml_or_empty(joinpath(registry_head, dir, "Package.toml"))
        dir_pkg = get(package_toml, "name", dir)

        for (v, entry) in master_versions_toml
            if get(head_versions_toml, v, nothing) != entry
                push!(problems, "It changes or removes the existing version v$(v) of $(dir_pkg) in `Versions.toml`.")
            end
        end
        new_versions = sort!([VersionNumber(v) for v in keys(head_versions_toml) if !haskey(master_versions_toml, v)])
        isempty(new_versions) || (added[dir_pkg] = new_versions)

        existing_versions = sort!([VersionNumber(v) for v in keys(master_versions_toml)])
        isempty(existing_versions) && continue
        for (file, is_compat) in (("Deps.toml", false), ("Compat.toml", true),
                                  ("WeakDeps.toml", false), ("WeakCompat.toml", true))
            master_path = joinpath(registry_master, dir, file)
            head_path = joinpath(registry_head, dir, file)
            master_entries = try
                _uncompressed_entries(master_path, existing_versions, is_compat)
            catch e
                # Pre-existing damage in the registry is not this pull request's doing.
                @warn "Could not load $(master_path); not checking its existing entries" exception = e
                continue
            end
            head_entries = try
                _uncompressed_entries(head_path, existing_versions, is_compat)
            catch e
                push!(problems, "Could not load `$(dir)/$(file)`: $(sprint(showerror, e))")
                continue
            end
            changed = [v for v in existing_versions if get(master_entries, v, nothing) != get(head_entries, v, nothing)]
            if !isempty(changed)
                push!(problems, string(
                    "It changes the `$(file)` data of $(dir_pkg) for existing version(s) ",
                    join(string.("v", changed), ", "), ".",
                ))
            end
        end
    end

    other_packages = sort!(filter(!=(pkg), collect(keys(added))))
    if !isempty(other_packages)
        push!(problems, string(
            "It adds versions of $(join(other_packages, ", ")), but its title names only $(pkg). ",
            "A registration pull request may only register versions of a single package.",
        ))
    end
    added_versions = get(added, pkg, VersionNumber[])
    if added_versions != title_versions
        push!(problems, string(
            "Its title names version(s) ", join(string.("v", title_versions), ", "),
            " of $(pkg) (in that order), but it adds ",
            isempty(added_versions) ? "no versions" : join(string.("v", added_versions), ", "),
            ". The title must list every added version, in ascending order.",
        ))
    end

    if isempty(problems)
        return true, ""
    end
    return false, string(
        "This pull request's registry changes do not match its title. ",
        join(problems, " "),
    )
end
