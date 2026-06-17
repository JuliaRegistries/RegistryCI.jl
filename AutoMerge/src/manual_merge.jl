module ManualMergeAnalysis

import GitHub
import URIs
import HTTP
import TOML
import Downloads

@kwdef mutable struct PRData
    api::GitHub.GitHubAPI
    auth::GitHub.Authorization
    repo::GitHub.Repo
    pr::GitHub.PullRequest
    files::Union{Nothing, Vector{GitHub.PullRequestFile}} = nothing
end

function get_files(pr_data::PRData)
    if isnothing(pr_data.files)
        (; api, repo, pr, auth) = pr_data
        pr_data.files = GitHub.pull_request_files(api, repo, pr; auth)
    end
    return pr_data.files
end

@static if VERSION >= v"1.12"
    @main(ARGS) = _main(ARGS)
end

function _main(ARGS)
    length(ARGS) != 1 && return fatal("Usage: manualmerge <PR Number>")
    n = tryparse(Int, lstrip(only(ARGS), '#'))
    isnothing(n) && return fatal("Cannot parse PR number `$(only(ARGS))` as an integer.")

    api = GitHub.GitHubWebAPI(URIs.URI("https://api.github.com"))
    auth = GitHub.AnonymousAuth()
    repo = GitHub.Repo("JuliaRegistries/General")
    pr = GitHub.pull_request(repo, n)
    pr_data = PRData(; api, auth, repo, pr)

    analyze_general_registry_pr(pr_data)

    return 0
end

function fatal(message::AbstractString)
    printstyled(stderr, "ERROR: ", color = :red)
    println(stderr, message)
    return 1
end

function fail(message)
    printstyled("✖", color = :red)
    println(" ", message)
end

function doubt(message)
    printstyled("?", color = :yellow)
    println(" ", message)
end

function pass(message)
    printstyled("✔", color = :green)
    println(" ", message)
end

function analyze_general_registry_pr(pr_data::PRData)
    (; pr) = pr_data
    print("Analyzing PR ")
    printstyled(pr.number, color = :blue)
    println(" by $(pr.user.login)")
    println("Title: $(pr.title)")
    println()
    for analyzer in [analyze_yank,
                     analyze_repo_move,
                     analyze_subdir_change,
                     analyze_retro_compat_change,
                     analyze_new_package,
                     analyze_new_version]
        # Analyzer functions return false if the PR does not have the
        # right structure and true if it has.
        analyzer(pr_data) && return
    end
    fail("Unknown or net yet supported structure of PR, not analyzed.")
end

# A yank PR is recognized by:
# * Only changing one file called Versions.toml
# * Adding exactly one line and removing none.
# * The added line contains "yank".
#
# Performed checks:
# * Added line is exactly "yanked = true".
# * Added line comes directly after a "git-tree-sha1" line.
#
# Diagnostics:
# * Write the name of the package.
function analyze_yank(pr_data::PRData)
    files = get_files(pr_data)
    length(files) != 1 && return false
    file = only(files)
    filename = file.filename
    basename(filename) == "Versions.toml" || return false
    file.status == "modified" || return false
    file.additions == 1 || return false
    file.deletions == 0 || return false
    added_line = only(get_added_lines(file))
    contains(lowercase(added_line), "yank") || return false
    package_name = basename(dirname(filename))
    print_pr_kind("yank", package_name)

    if added_line == "yanked = true"
        pass("Yank is syntactically correct.")
    else
        fail("Yank syntax is different from the expected `yanked = true`")
    end

    whole_patch = get_patch_lines(file)
    i = findfirst(startswith("+"), whole_patch)
    if isnothing(i) || i == 1 || !startswith(whole_patch[i - 1],
                                             " git-tree-sha1")
        fail("Yank line does not immediately follow a `git-tree-sha1` line.")
    else
        pass("Yank line immediately follows a `git-tree-sha1` line.")
    end

    println()
    println("Note: This analysis does not consider whether the right version is yanked or if there is a better alternative to yanking.")

    return true
end

# A repo move PR is recognized by:
# * Only changing one file called Project.toml
# * Removing and adding exactly one line.
# * Both the removed and added lines start with `repo = "` and ends with `"`.
#
# Performed checks:
# * Old URL forwards to new URL.
# * New URL ends with ".git" for repositories from github/gitlab/codeberg.
# * New URL starts with "https://".
# * Last part of URL is unchanged. Warn if not.
# * New URL is normal and restricted to letters, digits, dots, and slashes.
# * Cloning from the new URL works.
# * Cloned repository contains all registered tree hashes.
#
# Diagnostics:
# * Write the name of the package, source repo, and target repo.
function analyze_repo_move(pr_data::PRData)
    files = get_files(pr_data)
    length(files) == 1 || return false
    file = only(files)
    filename = file.filename
    basename(filename) == "Package.toml" || return false
    file.status == "modified" || return false
    file.additions == file.deletions == 1 || return false
    removed_line = only(get_removed_lines(file))
    added_line = only(get_added_lines(file))
    startswith(removed_line, "repo = \"") || return false
    startswith(added_line, "repo = \"") || return false
    endswith(removed_line, "\"") || return false
    endswith(added_line, "\"") || return false
    package_name = basename(dirname(filename))
    print_pr_kind("move repository", package_name)

    old_url = chopprefix(chopsuffix(removed_line, "\""), "repo = \"")
    new_url = chopprefix(chopsuffix(added_line, "\""), "repo = \"")
    println("Old URL: ", old_url)
    println("New URL: ", new_url)
    println()

    # Check whether there is a HTTP redirect from the old URL to the
    # new URL.
    redirect_to = string(HTTP.head(old_url).request.url)
    redirect_to_alt = redirect_to * ".git"
    if redirect_to == old_url || redirect_to_alt == old_url
        doubt("Old URL does not have a HTTP redirect.")
    elseif redirect_to == new_url || redirect_to_alt == new_url
        pass("Old URL redirects to new URL.")
    else
        fail("Old URL redirects to `$(redirect_to)`, whích is different from the new URL.")
    end

    # Check whether new URL ends with .git.
    if endswith(new_url, ".git")
        pass("New URL ends with `.git`.")
    elseif contains(new_url, "//github") || contains(new_url, "//gitlab") || contains(new_url, "//codeberg")
        fail("New URL does not end with `.git`.")
    else
        doubt("New URL does not end with `.git` but is not from github/gitlab/codeberg, so might be ok.")
    end

    # Check whether new URL starts with https://.
    if startswith(new_url, "https://")
        pass("New URL starts with `https://`.")
    else
        fail("New URL does not start with `https://`.")
    end

    # Check whether last part is identical between the URLs.
    old_last_part = last(split(old_url, "/"))
    new_last_part = last(split(new_url, "/"))
    if old_last_part == new_last_part
        pass("Last URL part is unchanged.")
    else
        doubt("Last URL part changes from `$(old_last_part)` to `$(new_last_part)`.")
    end

    # Check whether the new URL is normal.
    if url_is_normal(new_url)
        pass("New URL looks normal.")
    else
        fail("New URL looks non-standard.")
        doubt("Clone and treehash checks skipped because we do not trust new URL.")
        return true
    end

    # Can't run the last checks without git.
    git_available("Cloning of new URL and existence of three hashes cannot be tested.") || return true

    mktempdir() do tmpdir
        # Check if new URL can be git cloned.
        try
            run(`git clone -q $(new_url) $(tmpdir)`)
            pass("New URL can be git cloned.")
        catch e
            fail("New URL cannot be git cloned.")
            doubt("Cannot perform treehash check.")
            return true
        end

        # Maybe flush out some references which are not permanent.
        run(`git -C $(tmpdir) gc --quiet --prune=now`)

        # Check if all registered tree hashes can be retrieved from cloned repo.
        versions_url = replace(file.raw_url, "Package.toml" => "Versions.toml")
        versions = TOML.parsefile(Downloads.download(versions_url))
        for version in sort(collect(keys(versions)), by = VersionNumber)
            treehash = versions[version]["git-tree-sha1"]
            if success(`git -C $(tmpdir) rev-parse -q --verify "$(treehash)^{tree}"`)
                pass("Version $(version) tree hash found in cloned repository.")
            else
                fail("Version $(version) tree hash not found in cloned repository.")
            end
        end
    end
    return true
end

# Not yet implemented.
analyze_subdir_change(pr_data::PRData) = false
analyze_retro_compat_change(pr_data::PRData) = false
analyze_new_package(pr_data::PRData) = false
analyze_new_version(pr_data::PRData) = false

function git_available(fail_message)
    try
        read(`git --version`, String)
        return true
    catch e
        doubt("Cannot run git. $(fail_message)")
    end
    return false
end

# Sanity check of URL. We are quite conservative here.
function url_is_normal(url)
    re = r"^https:/(/[\w.]+)+$"
    return !isnothing(match(re, url))
end

function print_pr_kind(kind, package)
    print("Identified as a ")
    printstyled(kind, color = :blue)
    println(" PR for $(package).")
    println()
end

# Lines in the patch, starting with " " for unchanged lines, "-" for
# removed lines, and "+" for added lines.
function get_patch_lines(file::GitHub.PullRequestFile)
    return split(file.patch, "\n")
end

# Added lines only, without leading "+".
function get_added_lines(file::GitHub.PullRequestFile)
    return chopprefix.(filter(startswith("+"), get_patch_lines(file)), "+")
end

# Removed lines only, without leading "-".
function get_removed_lines(file::GitHub.PullRequestFile)
    return chopprefix.(filter(startswith("-"), get_patch_lines(file)), "-")
end

end

# Speed up CLI by precompiling main entry point.
@static if VERSION >= v"1.12"
    precompile(Tuple{typeof(AutoMerge.ManualMergeAnalysis.main),
                     Array{String, 1}})
end
