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
    load_files_from_url_and_tree_hash(f, destination::String, url::String, tree_hash::String) -> Bool

Attempts to clone a git repo from `url` into a temporary directory, runs `f(dir)` on that directory,
then extract the files and folders from a given `tree_hash`, placing them in `destination`.

Returns a boolean indicating if the cloning succeeded.
"""
function load_files_from_url_and_tree_hash(
    f, destination::String, url::String, tree_hash::String
)
    pkg_clone_dir = mktempdir()
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
    parse_registry_pkg_info(
        registry_path::AbstractString,
        pkg::AbstractString,
        version=nothing
      ) :: @NamedTuple{
        uuid::String,
        repo::String,
        subdir::String,
        tree_hash::Union{Nothing, String},
        commit_hash::Union{Nothing, String},
        tag_name::Union{Nothing, String}
      }

Searches the registry located at `registry_path` for a package with name `pkg`. Upon finding it,
it parses the associated `Package.toml` file and returns the UUID and repository URI, and `subdir`.

If `version` is supplied, then the associated `tree_hash` will be returned. Otherwise, `tree_hash` will be `nothing`.
"""
function parse_registry_pkg_info(registry_path, pkg, version=nothing)
    # We know the name of this package but not its uuid. Look it up in
    # the registry that includes the current PR.
    packages = TOML.parsefile(joinpath(registry_path, "Registry.toml"))["packages"]
    filter!(packages) do (key, value)
        value["name"] == pkg
    end
    # For Julia >= 1.4 this can be simplified with the `only` function.
    always_assert(length(packages) == 1)
    uuid = convert(String, first(keys(packages)))
    # Also need to find out the package repository.
    package = TOML.parsefile(
        joinpath(registry_path, packages[uuid]["path"], "Package.toml")
    )
    repo = convert(String, package["repo"])
    subdir = convert(String, get(package, "subdir", ""))
    if version === nothing
        tree_hash = nothing
        commit_hash = nothing
        tag_name = nothing
    else
        versions = TOML.parsefile(
            joinpath(registry_path, packages[uuid]["path"], "Versions.toml")
        )
        version_info = versions[string(version)]
        tree_hash = convert(String, version_info["git-tree-sha1"])
        commit_hash = get(version_info, "git-commit-sha1", nothing)
        tag_name = get(version_info, "git-tag-name", nothing)
        if !isnothing(commit_hash)
            # use version-specific subdir if commit_hash is defined.
            subdir = get(version_info, "subdir", "")
        end
    end
    return (; uuid=uuid, repo=repo, subdir=subdir, tree_hash=tree_hash, commit_hash=commit_hash, tag_name=tag_name)
end

function _comment_disclaimer(; point_to_slack::Bool=false)
    result = string(
        "\n\n",
        "Note that the guidelines are only required for the pull request ",
        "to be merged automatically. However, it is **strongly recommended** ",
        "to follow them, since otherwise the pull request needs to be ",
        "manually reviewed and merged by a human.",
        "\n\n",
        "After you have fixed the AutoMerge issues, simply retrigger Registrator, ",
        "which will automatically update this pull request. ",
        "You do not need to change the version number in your `Project.toml` file ",
        "(unless of course the AutoMerge issue is that you skipped a version number, ",
        "in which case you should change the version number).",
        "\n\n",
        "If you do not want to fix the AutoMerge issues, please post a comment ",
        "explaining why you would like this pull request to be manually merged.",
    )
    if point_to_slack
        result *= string(
            " ",
            "Then, send a message to the `#pkg-registration` channel in the ",
            "[Julia Slack](https://julialang.org/slack/) to ask for help. ",
            "Include a link to this pull request.",
        )
    end
    return result
end

function _comment_noblock()
    result = string(
        "\n\n---\n",
        "If you want to prevent this pull request from ",
        "being auto-merged, simply leave a comment. ",
        "If you want to post a comment without blocking ",
        "auto-merging, you must include the text ",
        "`[noblock]` in your comment. ",
        "You can edit blocking comments, adding `[noblock]` ",
        "to them in order to unblock auto-merging.",
    )
    return result
end

function comment_text_pass(
    ::NewVersion, suggest_onepointzero::Bool, version::VersionNumber, is_jll::Bool
)
    result = string(
        "Your `new version` pull request met all of the ",
        "guidelines for auto-merging and is scheduled to ",
        "be merged in the next round.",
        _comment_noblock(),
        _onepointzero_suggestion(suggest_onepointzero, version),
        "\n<!-- [noblock] -->",
    )
    return result
end

function comment_text_pass(
    ::NewPackage, suggest_onepointzero::Bool, version::VersionNumber, is_jll::Bool
)
    if is_jll
        result = string(
            "Your `new _jll package` pull request met all of the ",
            "guidelines for auto-merging and is scheduled to ",
            "be merged in the next round.",
            "\n\n",
            _comment_noblock(),
            _onepointzero_suggestion(suggest_onepointzero, version),
            "\n<!-- [noblock] -->",
        )
    else
        result = string(
            "Your `new package` pull request met all of the ",
            "guidelines for auto-merging and is scheduled to ",
            "be merged when the mandatory waiting period (3 days) has elapsed.",
            "\n\n",
            "Since you are registering a new package, ",
            "please make sure that you have read the ",
            "package naming guidelines: ",
            "https://julialang.github.io/Pkg.jl/dev/creating-packages/#Package-naming-guidelines-1",
            "\n\n",
            _comment_noblock(),
            _onepointzero_suggestion(suggest_onepointzero, version),
            "\n<!-- [noblock] -->",
        )
    end
    return result
end

const _please_read_these_documents = string(
    "Please make sure that you have read the ",
    "[General registry README](https://github.com/JuliaRegistries/General/blob/master/README.md) ",
    "and the ",
    "[AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/). ",
)

function comment_text_fail(
    ::NewPackage,
    reasons::Vector{String},
    suggest_onepointzero::Bool,
    version::VersionNumber;
    point_to_slack::Bool=false,
)
    reasons_formatted = join(string.("- ", reasons), "\n")
    result = string(
        "Your `new package` pull request does not meet ",
        "the guidelines for auto-merging. ",
        _please_read_these_documents,
        "The following guidelines were not met:\n\n",
        reasons_formatted,
        _comment_disclaimer(; point_to_slack=point_to_slack),
        "\n\n",
        "Since you are registering a new package, ",
        "please make sure that you have also read the ",
        "package naming guidelines: ",
        "https://julialang.github.io/Pkg.jl/dev/creating-packages/#Package-naming-guidelines-1",
        "\n\n",
        _comment_noblock(),
        _onepointzero_suggestion(suggest_onepointzero, version),
        "\n<!-- [noblock] -->",
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
    reasons_formatted = join(string.("- ", reasons), "\n")
    result = string(
        "Your `new version` pull request does not meet ",
        "the guidelines for auto-merging. ",
        _please_read_these_documents,
        "The following guidelines were not met:\n\n",
        reasons_formatted,
        _comment_disclaimer(; point_to_slack=point_to_slack),
        _comment_noblock(),
        _onepointzero_suggestion(suggest_onepointzero, version),
        "\n<!-- [noblock] -->",
    )
    return result
end

function comment_text_merge_now()
    result = string(
        "The mandatory waiting period has elapsed.\n\n",
        "Your pull request is ready to merge.\n\n",
        "I will now merge this pull request.",
        "\n<!-- [noblock] -->",
    )
    return result
end

function now_utc()
    utc = TimeZones.tz"UTC"
    return Dates.now(utc)
end

function _onepointzero_suggestion(suggest_onepointzero::Bool, version::VersionNumber)
    if suggest_onepointzero && version < v"1.0.0"
        result = string(
            "\n\n---\n",
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
            "release version `v1.0.0`.",
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

Given a path to the directory holding a registry, returns the names of all the non-JLL packages
defined in that registry, along with the names of Julia's standard libraries.
"""
function get_all_non_jll_package_names(registry_dir::AbstractString)
    packages = [
        x["name"] for
        x in values(TOML.parsefile(joinpath(registry_dir, "Registry.toml"))["packages"])
    ]
    sort!(packages)
    append!(packages, (RegistryTools.get_stdlib_name(x) for x in values(RegistryTools.stdlibs())))
    filter!(x -> !endswith(x, "_jll"), packages)
    unique!(packages)
    return packages
end
