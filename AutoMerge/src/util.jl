function checkout_branch(
    dir::AbstractString, branch::AbstractString; git_command::AbstractString="git"
)
    return Base.run(Cmd(`$(git_command) checkout $(branch)`; dir=dir))
end

clone_repo(repo::GitHub.Repo) = clone_repo(repo_url(repo))

function clone_repo(url::AbstractString)
    parent_dir = mktempdir(; cleanup=true)
    repo_dir = joinpath(parent_dir, "REPO")
    my_retry(() -> _clone_repo_into_dir(url, repo_dir))
    @info("Clone was successful")
    return repo_dir
end

function _clone_repo_into_dir(url::AbstractString, repo_dir)
    @info("Attempting to clone...")
    rm(repo_dir; force=true, recursive=true)
    mkpath(repo_dir)
    LibGit2.clone(url, repo_dir)
    return repo_dir
end

"""
    load_files_from_url_and_tree_hash(f, destination::String, url::String, tree_hash::String, pkg_clone_dir::String) -> Bool

Attempts to clone a git repo from `url` into `pkg_clone_dir` (or reuse existing clone if it exists),
runs `f(dir)` on that directory, then extract the files and folders from a given `tree_hash`, placing them in `destination`.

The repository is cloned into `pkg_clone_dir`.

Returns a boolean indicating if the cloning succeeded.
"""
function load_files_from_url_and_tree_hash(
    f, destination::String, url::String, tree_hash::String, pkg_clone_dir::String
)
    clone_success = try
        _clone_repo_into_dir(url, pkg_clone_dir)
        true
    catch e
        @error "Cloning $url failed" e
        false
    end

    # if cloning failed, bail now
    !clone_success && return clone_success

    f(pkg_clone_dir)
    Tar.extract(Cmd(`git archive $tree_hash`; dir=pkg_clone_dir), destination)
    return clone_success
end

"""
    parse_registry_pkg_info(registry_path, pkg, version=nothing) -> @NamedTuple{uuid::String, repo::String, subdir::String, tree_hash::Union{Nothing, String}}

Searches the registry located at `registry_path` for a package with name `pkg`. Upon finding it,
it parses the associated `Package.toml` file and returns the UUID and repository URI, and `subdir`.

If `version` is supplied, then the associated `tree_hash` will be returned. Otherwise, `tree_hash` will be `nothing`.
"""
function parse_registry_pkg_info(registry_path, pkg, version=nothing)
    # We know the name of this package but not its uuid. Look it up in
    # the registry that includes the current PR.
    packages = parse_registry_toml(registry_path, "Registry.toml")["packages"]
    uuid = only((key for (key, value) in packages if value["name"] == pkg))
    # Also need to find out the package repository.
    package = parse_registry_toml(registry_path, packages[uuid]["path"], "Package.toml")
    repo = package["repo"]
    subdir = get(package, "subdir", "")
    if version === nothing
        tree_hash = nothing
    else
        versions = parse_registry_toml(registry_path, packages[uuid]["path"], "Versions.toml")
        tree_hash = convert(String, versions[string(version)]["git-tree-sha1"])
    end
    return (; uuid=uuid, repo=repo, subdir=subdir, tree_hash=tree_hash)
end

#####
##### Version diff functionality
#####

"""
    find_previous_semver_version(pkg::AbstractString, current_version::VersionNumber, registry_path::AbstractString) -> Union{VersionNumber, Nothing}

Finds the previous semver version for a package. Returns the maximum version that is less than the current version,
or `nothing` if there are no previous versions.
"""
function find_previous_semver_version(pkg::AbstractString, current_version::VersionNumber, registry_path::AbstractString)
    all_pkg_versions = all_versions(pkg, registry_path)
    previous_versions = filter(<(current_version), all_pkg_versions)
    return isempty(previous_versions) ? nothing : maximum(previous_versions)
end

"""
    tree_sha_to_commit_sha(tree_sha::AbstractString, clone_dir::AbstractString; subdir::AbstractString="") -> Union{AbstractString, Nothing}

Converts a git tree SHA to a commit SHA by finding a commit that has that tree.
Returns the commit SHA string, or `nothing` if no commit is found.
"""
function tree_sha_to_commit_sha(tree_sha::AbstractString, clone_dir::AbstractString; subdir::AbstractString = "")
    isdir(clone_dir) || error("$clone_dir is not a directory")
    # Normalize to a full tree object ID; return nothing if it’s not a tree reachable in this repo
    full_tree = try
        # --verify fails if not found; --quiet suppresses stderr noise
        sha_cmd = "$tree_sha^{tree}"
        readchomp(`git -C $(clone_dir) rev-parse --verify --quiet $sha_cmd`)
    catch e
        @warn e
        return nothing
    end
    isempty(full_tree) && return nothing

    if isempty(subdir)
        # Single pass: (commit_sha tree_sha) per line for all commits across all refs
        try
            for line in eachline(`git -C $(clone_dir) log --all --format="%H %T"`)
                commit_sha, tree_sha = split(line)
                if tree_sha == full_tree
                    return commit_sha
                end
            end
        catch e
            @warn e
        end
        return nothing
    else
        # Only commits that touched `subdir` (much smaller set)
        commits = try
            readlines(`git -C $(clone_dir) log --all --format=%H -- $subdir`)
        catch e
            @warn e
            return nothing
        end
        isempty(commits) && return nothing

        # Check subdir tree per candidate commit (fast enough in practice)
        for c in commits
            t = try
                readchomp(`git -C $(clone_dir) rev-parse $c:$subdir`)
            catch
                continue  # subdir may not exist at this commit
            end
            if t == full_tree
                return c
            end
        end
        return nothing
    end
end

"""
    is_github_repo(repo_url::AbstractString) -> Bool

Checks if a repository URL is a GitHub repository.
"""
function is_github_repo(repo_url::AbstractString)
    return occursin(r"github\.com[:/]", repo_url)
end

"""
    extract_github_owner_repo(repo_url::AbstractString)

Extracts the owner and repository name from a GitHub URL.
Returns a tuple (owner, repo) or `nothing` if the URL is not a valid GitHub URL.
"""
function extract_github_owner_repo(repo_url::AbstractString)
    # Handle both HTTPS and SSH GitHub URLs
    # HTTPS: https://github.com/owner/repo.git
    # SSH: git@github.com:owner/repo.git
    m = match(r"github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$", repo_url)
    return m === nothing ? nothing : (m.captures[1], m.captures[2])
end

"""
    generate_github_diff_url(repo_url::AbstractString, previous_commit_sha::AbstractString, current_commit_sha::AbstractString) -> Union{AbstractString, Nothing}

Generates a GitHub diff URL comparing two commits.
Returns the URL AbstractString, or `nothing` if the repository is not on GitHub.
"""
function generate_github_diff_url(repo_url::AbstractString, previous_commit_sha::AbstractString, current_commit_sha::AbstractString)
    if !is_github_repo(repo_url)
        return nothing
    end

    owner_repo = extract_github_owner_repo(repo_url)
    if owner_repo === nothing
        return nothing
    end

    owner, repo = owner_repo
    return "https://github.com/$owner/$repo/compare/$previous_commit_sha...$current_commit_sha"
end

"""
    get_version_diff_info(data) -> Union{NamedTuple, Nothing}

Gets diff information for a new version registration. Returns a NamedTuple with fields:
- `diff_url`: GitHub diff URL
- `previous_version`: Previous version number
- `current_version`: Current version number

Returns `nothing` if no previous version exists or if the repository is not on GitHub.
"""
function get_version_diff_info(data)
    # Only applicable for new versions
    if !(data.registration_type isa NewVersion)
        return nothing
    end

    # Find the previous version
    previous_version = find_previous_semver_version(data.pkg, data.version, data.registry_master)
    if previous_version === nothing
        return nothing
    end

    # Get package repository info
    current_pkg_info = parse_registry_pkg_info(data.registry_head, data.pkg, data.version)
    previous_pkg_info = parse_registry_pkg_info(data.registry_master, data.pkg, previous_version)

    # Check if it's a GitHub repo
    if !is_github_repo(current_pkg_info.repo)
        return nothing
    end

    # Get current commit SHA from PR
    current_commit_sha = commit_from_pull_request_body(data.pr)

    # Convert previous tree SHA to commit SHA
    previous_commit_sha = tree_sha_to_commit_sha(
        previous_pkg_info.tree_hash,
        data.pkg_clone_dir;
        subdir=previous_pkg_info.subdir
    )

    if previous_commit_sha === nothing
        return nothing
    end

    # Generate diff URL
    diff_url = generate_github_diff_url(current_pkg_info.repo, previous_commit_sha, current_commit_sha)

    if diff_url === nothing
        return nothing
    end

    return (
        diff_url=diff_url,
        previous_version=previous_version,
        current_version=data.version,
    )
end

#####
##### AutoMerge comment
#####

# The AutoMerge comment is divided into numbered sections.
# Besides the "AutoMerge Guidelines which are not met" and "AutoMerge Guidelines have all passed!"
# sections, we keep these minimally customized, and instead simply include or exclude
# whole sections depending on the context. This way, users can understand the message
# without necessarily reading the details of each section each time.
# We hope they will at least read the section titles, and if they aren't
# familiar, hopefully they will also read the sections themselves.

function _comment_bot_intro()
    return string("Hello, I am an automated registration bot.",
    " I help manage the registration process by checking your registration against a set of ","[AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/). ",
    "If all these guidelines are met, this pull request will be merged automatically, completing your registration. It is **strongly recommended** to follow the guidelines, since otherwise ",
    "the pull request needs to be manually reviewed and merged by a human.\n\n")
end

function _new_package_section(n)
    return string("## $n. New package registration", "\n\n",
    "Please make sure that you have read the ",
    "[package naming guidelines](https://pkgdocs.julialang.org/dev/creating-packages/#Package-naming-guidelines).\n\n")
end

function _what_next_if_fail(n; point_to_slack=false)
    msg = """
    ## $n. *Needs action*: here's what to do next

    1. Please try to update your package to conform to these guidelines. The [General registry's README](https://github.com/JuliaRegistries/General/blob/master/README.md) has an FAQ that can help figure out how to do so."""
    msg = string(msg, "\n",
        "2. After you have fixed the AutoMerge issues, simply retrigger Registrator, the same way you did in the initial registration. This will automatically update this pull request. You do not need to change the version number in your `Project.toml` file (unless the AutoMerge issue is that you skipped a version number).",
        "\n\n",
        "If you need help fixing the AutoMerge issues, or want your pull request to be manually merged instead, please post a comment explaining what you need help with or why you would like this pull request to be manually merged.")

    if point_to_slack
        msg = string(msg, " Then, send a message to the `#pkg-registration` channel in the [public Julia Slack](https://julialang.org/slack/) for better visibility.")
    end
    msg = string(msg, "\n\n")
    return msg
end

function _automerge_guidelines_failed_section_title(n)
    return "## $n. [AutoMerge Guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) which are not met ❌\n\n"
end

function _automerge_guidelines_passed_section_title(n)
    "## $n. [AutoMerge Guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) are all met! ✅\n\n"
end

function _comment_noblock(n)
    result = string(
        "## $n. To pause or stop registration\n\n",
        "If you want to prevent this pull request from ",
        "being auto-merged, simply leave a comment. ",
        "If you want to post a comment without blocking ",
        "auto-merging, you must include the text ",
        "`[noblock]` in your comment.",
        "\n\n_Tip: You can edit blocking comments to add `[noblock]` ",
        "in order to unblock auto-merging._\n\n",
    )
    return result
end

function _version_diff_section(n, diff_info)
    return string(
        "## $n. Code changes since last version\n\n",
        "Since the last version (v$(diff_info.previous_version)), ",
        "you can see the code changes here:\n\n",
        "[View diff]($(diff_info.diff_url))\n\n",
    )
end

function comment_text_pass(
    ::NewVersion, suggest_onepointzero::Bool, version::VersionNumber, is_jll::Bool; new_package_waiting_minutes, data=nothing
)
    # Need to know this ahead of time to get the section numbers right
    suggest_onepointzero &= version < v"1.0.0"

    # Get diff information if data is available
    diff_info = data !== nothing ? get_version_diff_info(data) : nothing
    has_diff = diff_info !== nothing

    # Calculate section numbers
    guidelines_section = 1
    diff_section = 2
    onepointzero_section = has_diff ? 3 : 2
    noblock_section = suggest_onepointzero ? (has_diff ? 4 : 3) : (has_diff ? 3 : 2)

    result = string(
        _comment_bot_intro(),
        _automerge_guidelines_passed_section_title(guidelines_section),
        "Your new version registration met all of the ",
        "guidelines for auto-merging and is scheduled to ",
        "be merged in the next round (~20 minutes).\n\n",
        has_diff ? _version_diff_section(diff_section, diff_info) : "",
        _onepointzero_suggestion(onepointzero_section, suggest_onepointzero, version),
        _comment_noblock(noblock_section),
        "<!-- [noblock] -->",
    )
    return result
end

# We allow passing `data` since the NewVersion method uses it.
# This way `comment_text_pass` can be called generically.
function comment_text_pass(
    ::NewPackage, suggest_onepointzero::Bool, version::VersionNumber, is_jll::Bool; new_package_waiting_minutes, data = nothing
)
    suggest_onepointzero &= version < v"1.0.0"
    if is_jll
        result = string(
            _comment_bot_intro(),
            _automerge_guidelines_passed_section_title(1),
            "Your new `_jll` package registration met all of the ",
            "guidelines for auto-merging and is scheduled to ",
            "be merged in the next round (~20 minutes).\n\n",
            _onepointzero_suggestion(2, suggest_onepointzero, version),
            _comment_noblock(suggest_onepointzero ? 3 : 2),
            "<!-- [noblock] -->",
        )
    else
        wait = Dates.canonicalize(new_package_waiting_minutes)

        result = string(
            _comment_bot_intro(),
            _new_package_section(1),
            _automerge_guidelines_passed_section_title(2),
            "Your new package registration met all of the ",
            "guidelines for auto-merging and is scheduled to ",
            "be merged when the mandatory waiting period ($wait) has elapsed.\n\n",
            _onepointzero_suggestion(3, suggest_onepointzero, version),
            _comment_noblock(suggest_onepointzero ? 4 : 3),
            "<!-- [noblock] -->",
        )
    end
    return result
end

function comment_text_fail(
    ::NewPackage,
    reasons::Vector{String},
    suggest_onepointzero::Bool,
    version::VersionNumber;
    point_to_slack::Bool=false,
)
    suggest_onepointzero &= version < v"1.0.0"
    reasons_formatted = string(join(string.("- ", reasons), "\n"), "\n\n")
    result = string(
        _comment_bot_intro(),
        _new_package_section(1),
        _automerge_guidelines_failed_section_title(2),
        reasons_formatted,
        _what_next_if_fail(3; point_to_slack=point_to_slack),
        _onepointzero_suggestion(4, suggest_onepointzero, version),
        _comment_noblock(suggest_onepointzero ? 5 : 4),
        "<!-- [noblock] -->",
    )
    return result
end

function comment_text_fail(
    ::NewVersion,
    reasons::Vector{String},
    suggest_onepointzero::Bool,
    version::VersionNumber;
    point_to_slack::Bool=false,
)
    suggest_onepointzero &= version < v"1.0.0"
    reasons_formatted = string(join(string.("- ", reasons), "\n"), "\n\n")
    result = string(
        _comment_bot_intro(),
        _automerge_guidelines_failed_section_title(1),
        reasons_formatted,
        _what_next_if_fail(2; point_to_slack=point_to_slack),
        _onepointzero_suggestion(3, suggest_onepointzero, version),
        _comment_noblock(suggest_onepointzero ? 4 : 3),
        "<!-- [noblock] -->",
    )
    return result
end

is_julia_stdlib(name) = name in julia_stdlib_list()

function julia_stdlib_list()
    stdlib_list = readdir(Pkg.Types.stdlib_dir())
    # Before Julia v1.6 Artifacts.jl isn't a standard library, but
    # we want to include it because JLL packages depend on the empty
    # placeholder https://github.com/JuliaPackaging/Artifacts.jl
    # in older versions for compatibility.
    if VERSION < v"1.6.0"
        push!(stdlib_list, "Artifacts")
    end
    return stdlib_list
end

function now_utc()
    utc = TimeZones.tz"UTC"
    return Dates.now(utc)
end

function _onepointzero_suggestion(n, suggest_onepointzero::Bool, version::VersionNumber)
    if suggest_onepointzero && version < v"1.0.0"
        result = string(
            "## $n. Declare v1.0?\n\n",
            "On a separate note, I see that you are registering ",
            "a release with a version number of the form ",
            "`v0.X.Y`.\n\n",
            "Does your package have a stable public API? ",
            "If so, then it's time for you to register version ",
            "`v1.0.0` of your package. ",
            "(This is not a requirement. ",
            "It's just a recommendation.)\n\n",
            "If your package does not yet have a stable public ",
            "API, then of course you are not yet ready to ",
            "release version `v1.0.0`.\n\n",
        )
        return result
    else
        return ""
    end
end

function time_is_already_in_utc(dt::Dates.DateTime)
    utc = TimeZones.tz"UTC"
    return TimeZones.ZonedDateTime(dt, utc; from_utc=true)
end

"""
    get_all_non_jll_package_names(registry_dir::AbstractString) -> Vector{String}
    get_all_non_jll_package_names(registry::RegistryInstance) -> Vector{String}

Given either:

- a path to a directory holding an uncompressed registry

or

- a `RegistryInstance` object (from [RegistryInstances.jl](https://github.com/GunnarFarneback/RegistryInstances.jl)) associated to a registry,

returns a sorted list of the names of Julia's standard libraries
and all the non-JLL packages defined in that registry.
"""
function get_all_non_jll_package_names(registry_dir::AbstractString)
    # Mimic the structure of a RegistryInstance
    list = parse_registry_toml(registry_dir, "Registry.toml")["packages"]
    registry = (; pkgs=Dict(k => (; name=v["name"]) for (k,v) in pairs(list)))
    return get_all_non_jll_package_names(registry)
end

# Generic method intended for RegistryInstance (without taking on the dependency,
# which is only valid on Julia 1.7+)
function get_all_non_jll_package_names(registry)
    packages = [entry.name for entry in values(registry.pkgs)]
    append!(packages, (RegistryTools.get_stdlib_name(x) for x in values(RegistryTools.stdlibs())))
    sort!(packages)
    filter!(x -> !endswith(x, "_jll"), packages)
    unique!(packages)
    return packages
end


function has_label(labels, target)
    # No labels? Then no
    isnothing(labels) && return false
    for label in labels
        if label.name === target
            # found it
            @debug "Found `$(target)` label"
            return true
        end
    end
    # Did not find it
    return false
end

const PACKAGE_AUTHOR_APPROVED_LABEL = "Override AutoMerge: package author approved"

has_package_author_approved_label(labels) = has_label(labels, PACKAGE_AUTHOR_APPROVED_LABEL)

"""
    try_remove_label(api, repo, issue, label)

Uses `GitHub.remove_label` to remove the label, if it exists.
Differs from the upstream functionality by not erroring if we receive a 404
response indicating the label did not exist.

Returns whether or not the label was removed.
"""
function try_remove_label(api, repo, issue, label; options...)
    label = HTTP.escapeuri(label)
    path = "/repos/$(GitHub.name(repo))/issues/$(GitHub.name(issue))/labels/$(GitHub.name(label))"
    @debug "Removing label" path
    r = GitHub.remove_label(api, repo, issue, label; handle_error = false, options...)
    r.status == 404 && return false
    GitHub.handle_response_error(r)  # throw errors in other cases if necessary
    return true
end

function maybe_create_label(api, repo, name::String, color::String, description::String; options...)
    path = "/repos/$(GitHub.name(repo))/labels"
    result = GitHub.gh_post(api, path; params=(; name=name, color=color, description=description), handle_error=false, options...)
    @debug "Response from `maybe_create_label`" result
    return result.status == 201
end

"""
    maybe_create_blocked_label(api, repo)

Add the label `$BLOCKED_LABEL` to the repo if it doesn't already exist.

Returns whether or not it created the label.
"""
maybe_create_blocked_label(api, repo; options...) = maybe_create_label(api, repo, BLOCKED_LABEL, "ff0000", "PR blocked by one or more comments lacking the string [noblock]."; options...)
