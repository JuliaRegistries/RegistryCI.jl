module ManualMergeAnalysis

import GitHub
import URIs
import HTTP
import TOML
import Downloads
import RegistryTools
using ..AutoMerge: get_all_pull_requests, NewPackage, clone_repo, get_automerge_guidelines, GitHubAutoMergeData, Guideline, check!, guideline_version_can_be_pkg_added, guideline_version_can_be_imported, guideline_subdir_parameter_is_correct, passed, message

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
    length(ARGS) > 1 && return fatal("Usage: manualmerge <PR Number>")

    api = GitHub.GitHubWebAPI(URIs.URI("https://api.github.com"))
    auth = GitHub.AnonymousAuth()
    repo = GitHub.Repo("JuliaRegistries/General")

    if isempty(ARGS)
        pull_requests = get_all_pull_requests(api, repo, "open"; auth)
        for pr in pull_requests
            user = pr.user.login
            if user ∉ ("JuliaRegistrator", "jlbuild")
                if !contains(user, "[bot]") && user != "JuliaTagBot"
                    printstyled(pr.number, color = :green)
                else
                    print(pr.number)
                end
                println(" by ", user, ": ", pr.title)
            end
        end
        if isempty(pull_requests)
            println("No open manual pull requests.")
        else
            println()
            println("Run `manual_merge_analysis <PR Number>` to analyze a PR.")
        end
        return 0
    end

    n = tryparse(Int, lstrip(only(ARGS), '#'))
    isnothing(n) && return fatal("Cannot parse PR number `$(only(ARGS))` as an integer.")

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
                     analyze_repo_move_and_subdir_change,
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
# * Only changing one file called Package.toml
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
# * Cloned repository has a Project.toml or JuliaProject.toml.
# * (Julia)Project.toml has matching name and uuid.
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

    check_repo_and_subdir_changes(pr_data, package_name, file)
    return true
end

# A subdir change PR is recognized by:
# * Only changing one file called Package.toml.
# * Changing at most one line starting with `subdir = `.
#
# Performed checks:
# * Subdir exists in repository.
# * Subdir contains Project.toml or JuliaProject.toml.
# * (Julia)Project.toml has matching name and uuid.
#
# Diagnostics:
# * Write the name of the package, old subdir and new subdir.
function analyze_subdir_change(pr_data::PRData)
    files = get_files(pr_data)
    length(files) == 1 || return false
    file = only(files)
    filename = file.filename
    basename(filename) == "Package.toml" || return false
    file.status == "modified" || return false
    file.deletions <= 1 || return false
    file.additions <= 1 || return false
    removed_lines = get_removed_lines(file)
    added_lines = get_added_lines(file)
    for line in vcat(removed_lines, added_lines)
        startswith(line, "subdir = \"") || return false
        endswith(line, "\"") || return false
    end
    package_name = basename(dirname(filename))
    print_pr_kind("change subdir", package_name)

    check_repo_and_subdir_changes(pr_data, package_name, file)
    return true
end

# A repo move and subdir change PR is recognized by:
# * Only changing one file called Package.toml.
# * Removing or adding at most two lines.
# * All removed and added lines start with `repo = ` or `subdir =`.
#
# Performed checks:
# * If URL is changed:
#   * Old URL forwards to new URL.
#   * New URL ends with ".git" for repositories from github/gitlab/codeberg.
#   * New URL starts with "https://".
#   * Last part of URL is unchanged. Warn if not.
#   * New URL is normal and restricted to letters, digits, dots, and slashes.
# * Cloning from the new URL works.
# * Cloned repository contains all registered tree hashes.
# * If new subdir is specified:
#   * Subdir exists in repository.
# * Cloned repository has a Project.toml or JuliaProject.toml in new subdir.
# * (Julia)Project.toml has matching name and uuid.
#
# Diagnostics:
# * Write the name of the package.
# * Write source repo, and target repo.
# * Write old subdir and new subdir.
function analyze_repo_move_and_subdir_change(pr_data::PRData)
    files = get_files(pr_data)
    length(files) == 1 || return false
    file = only(files)
    filename = file.filename
    basename(filename) == "Package.toml" || return false
    file.status == "modified" || return false
    file.additions <= 2 || return false
    file.deletions <= 2 || return false
    removed_lines = get_removed_lines(file)
    added_lines = get_added_lines(file)
    for line in vcat(removed_lines, added_lines)
        startswith(line, "repo = \"") || startswith(line, "subdir = \"") || return false
        endswith(line, "\"") || return false
    end

    package_name = basename(dirname(filename))
    print_pr_kind("move repository and change subdir", package_name)

    check_repo_and_subdir_changes(pr_data, package_name, file)
    return true
end



function check_repo_and_subdir_changes(pr_data, package_name, file)
    package_url = file.raw_url
    package_toml =
        try
            TOML.parsefile(Downloads.download(package_url))
        catch e
            fail("Modified Package.toml cannot be parsed.")
            return
        end

    pr = pr_data.pr
    old_package_url = replace(package_url, pr.head.sha => pr.base.sha)
    old_package_toml = TOML.parsefile(Downloads.download(old_package_url))

    old_url = old_package_toml["repo"]
    if !haskey(package_toml, "repo")
        fail("Modified Package.toml has no repo entry.")
        return
    end
    new_url = package_toml["repo"]
    old_subdir = get(old_package_toml, "subdir", "")
    new_subdir = get(package_toml, "subdir", "")

    if old_url != new_url
        println("Old URL: ", old_url)
        println("New URL: ", new_url)
    end
    if old_subdir != new_subdir
        println("Old subdir: ", old_subdir)
        println("New subdir: ", new_subdir)
    end
    println()

    if old_url != new_url
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
    end

    # Can't run the last checks without git.
    git_available("Cloning of new URL and existence of three hashes cannot be tested.") || return true

    mktempdir() do tmpdir
        # Check if new URL can be git cloned.
        try
            run(`git clone -q $(new_url) $(tmpdir)`)
            if old_url != new_url
                pass("New URL can be git cloned.")
            end
        catch e
            if old_url != new_url
                fail("New URL cannot be git cloned.")
            else
                fail("Package URL cannot be git cloned.")
            end
            doubt("Cannot perform treehash check and other repo consistency checks.")
            return true
        end

        package_dir = joinpath(tmpdir, new_subdir)
        if !isempty(new_subdir) && !isdir(package_dir)
            fail("Subdir `$(subdir)` does not exist in default branch of repository.")
        else
            if old_subdir != new_subdir && !isempty(new_subdir)
                pass("Subdir `$(new_subdir)` exists in default branch of repository.")
            end
            project = Dict{String, String}()
            # Search for both JuliaProject.toml and Project.toml.
            project_file_name = ""
            for project_file in Base.project_names
                project_path = joinpath(package_dir, project_file)
                if isfile(project_path)
                    try
                        project = TOML.parsefile(project_path)
                        if old_subdir != new_subdir
                            pass("New subdir contains a $(project_file)")
                        end
                    catch e
                        fail("$(project_file) cannot be parsed as TOML.")
                    end
                    project_file_name = project_file
                    break
                end
            end
            if isempty(project)
                if isempty(new_subdir)
                    fail("No Project.toml found in default branch of repository.")
                else
                    fail("No Project.toml found in subdir `$(new_subdir)` of default branch of repository.")
                end
            else
                if !haskey(project, "name")
                    fail("No name found in package's $(project_file_name) in default branch of repository.")
                elseif project["name"] != package_name
                    name_in_project = project["name"]
                    doubt("Package name `$(name_in_project)` found in package's $(project_file_name) in default branch of repository is different from registered package name `$(package_name)`. Was the package also renamed?")
                elseif old_subdir != new_subdir
                    pass("Package name in $(project_file_name) of new subdir matches registered package name.")
                end
                if !haskey(project, "uuid")
                    fail("No uuid found in package's $(project_file_name) in default branch of repository.")
                elseif project["uuid"] != package_toml["uuid"]
                    uuid_in_project = project["uuid"]
                    package_uuid = package_toml["uuid"]
                    doubt("Package uuid `$(uuid_in_project)` found in package's $(project_file_name) in default branch of repository is different from registered package uuid `$(package_uuid)`. Was the package also renamed?")
                elseif old_subdir != new_subdir
                    pass("Package uuid in $(project_file_name) of new subdir matches registered package uuid.")
                end
            end
        end

        # Maybe flush out some references which are not permanent
        # before looking for tree hashes.
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

# A retro compat change PR is recognized by:
# * Only changing one or two files called Compat.toml and WeakCompat.toml.
# * If both are changed they must be in the same directory.
#
# Performed checks:
# * New files can be read by RegistryTools.Compress.load.
# * Roundtripping the new files with Compress.load and Compress.save should
#   preferably yield the same result.
#
# Diagnostics:
# * Write the name of the package and list all the effective changes
#   to compat from the PR.
function analyze_retro_compat_change(pr_data::PRData)
    files = get_files(pr_data)
    1 <= length(files) <= 2 || return false
    filenames = [file.filename for file in files]
    length(files) == 2 && !allequal(dirname.(filenames)) &&  return false
    all(in.(basename.(filenames),
            Ref(("Compat.toml", "WeakCompat.toml")))) || return false
    all(file.status == "modified" for file in files) || return false
    package_name = basename(dirname(first(filenames)))
    print_pr_kind("retro compat change", package_name)

    for file in files
        mktempdir() do tmpdir
            tmpdir = "/tmp/foo10"; mkpath(tmpdir)
            compat_url = file.raw_url
            # Note: This is also effective for WeakCompat.toml -> WeakDeps.toml.
            deps_url = replace(file.raw_url, "Compat.toml" => "Deps.toml")
            versions_url = replace(file.raw_url,
                                   basename(file.filename) => "Versions.toml")
            compat_path = joinpath(tmpdir, "Compat.toml")
            deps_path = joinpath(tmpdir, "Deps.toml")
            versions_path = joinpath(tmpdir, "Versions.toml")
            Downloads.download(compat_url, compat_path)
            Downloads.download(deps_url, deps_path)
            Downloads.download(versions_url, versions_path)
            pr = pr_data.pr
            old_compat_url = replace(compat_url, pr.head.sha => pr.base.sha)
            old_deps_url = replace(deps_url, pr.head.sha => pr.base.sha)
            old_versions_url = replace(versions_url, pr.head.sha => pr.base.sha)
            old_compat_path = joinpath(tmpdir, "old", "Compat.toml")
            old_deps_path = joinpath(tmpdir, "old", "Deps.toml")
            old_versions_path = joinpath(tmpdir, "old", "Versions.toml")
            mkpath(dirname(old_compat_path))
            Downloads.download(old_compat_url, old_compat_path)
            Downloads.download(old_deps_url, old_deps_path)
            Downloads.download(old_versions_url, old_versions_path)

            # All needed files are downloaded. Get to work with
            # RegistryTools.Compress functionality.
            old_compat = RegistryTools.Compress.load(old_compat_path)
            compat = RegistryTools.Compress.load(compat_path)
            resaved_compat_path = joinpath(tmpdir, "ResavedCompat.toml")
            RegistryTools.Compress.save(resaved_compat_path, compat)
            compat_raw = read(compat_path, String)
            resaved_compat_raw = read(resaved_compat_path, String)
            if equal_up_to_spaces(compat_raw, resaved_compat_raw)
                pass(string(basename(file.filename),
                            " roundtrips through compressed load+save (spaces ignored)."))
            else
                # The issue fixed in
                # https://github.com/JuliaRegistries/RegistryTools.jl/pull/107
                # may cause these kinds of problems for a long time yet.
                doubt(string(basename(file.filename),
                             " does not roundtrip through compressed load+save up to space differences. This is probably ok."))
            end
            differences = []
            for version in sort(collect(keys(compat)))
                old = old_compat[version]
                new = compat[version]
                for dep in sort(collect(union(keys(old), keys(new))))
                    old_c = get(old, dep, "")
                    new_c = get(new, dep, "")
                    if old_c != new_c
                        println(version, " ", dep, " ", old_c, " => ", new_c)
                    end
                end
            end
        end
    end

    return true
end

# A new package PR is recognized by:
# * Adding one line to `Registry.toml`.
# * Adding a number of new files, all in the same directory.
#
# Performed checks:
# * All checks done by regular AutoMerge, except the Pkg.add and
#   import checks.
#
# Diagnostics:
# * Write the name of the package.
# * Write the package URL.
function analyze_new_package(pr_data::PRData)
    files = get_files(pr_data)
    filenames = [file.filename for file in files]
    "Registry.toml" in filenames || return false
    non_registry_filenames = filter(!=("Registry.toml"), filenames)
    allequal(dirname.(non_registry_filenames)) || return false
    registry_file = only(filter(file -> file.filename == "Registry.toml", files))
    registry_file.status == "modified" || return false
    registry_file.additions == 1 || return false
    registry_file.deletions == 0 || return false

    package_name = basename(dirname(first(non_registry_filenames)))
    print_pr_kind("new package", package_name)

    git_available("Automerge checks cannot be run.") || return true

    # Retrieve the new package guidelines.
    guidelines = get_automerge_guidelines(
        NewPackage(),
        check_license = true,
        this_is_jll_package = false,
        this_pr_can_use_special_jll_exceptions = false,
        use_distance_check = true,
        package_author_approved = false,
        check_breaking_explanation = false
    )

    # Set up the data used by the guideline checks.
    registry_head = clone_repo(pr_data.pr.head.repo)
    run(`git -C $(registry_head) checkout $(pr_data.pr.head.ref)`)
    registry_master = clone_repo(pr_data.pr.base.repo)
    versions_file = only(filter(file -> basename(file.filename) == "Versions.toml", files))
    added_lines = get_added_lines(versions_file)
    version_raw = first(added_lines)
    version = chopsuffix(chopprefix(version_raw, "[\""), "\"]")
    tree_hash_raw = last(added_lines)
    tree_hash = chopsuffix(chopprefix(tree_hash_raw, "git-tree-sha1 = \""), "\"")

    data = GitHubAutoMergeData(
        ;
        api = pr_data.api,
        registration_type = NewPackage(),
        pr = pr_data.pr,
        pkg = package_name,
        version = VersionNumber(version),
        registry = pr_data.repo,
        auth = pr_data.auth,
        registry_head,
        registry_master,
        registry_deps = String[],
        # TODO: This should be synchronized with the information in
        # `https://github.com/JuliaRegistries/General/blob/master/.github/workflows/automerge.yml`.
        # We do have access to that file through `registry_master` but
        # as it is we have to parse YAML to retrieve the public
        # registries. Ideally those would be in a separate file.
        public_registries = String[
            "https://github.com/HolyLab/HolyLabRegistry",
            "https://github.com/cossio/CossioJuliaRegistry"],
        # The following arguments are not actually used but are
        # requried by the constructor.
        current_pr_head_commit_sha = "",
        authorization = :normal,
        suggest_onepointzero = false,
        point_to_slack = false,
        whoami = "",
        read_only = true,
        environment_variables_to_pass = String[]
    )

    checked_guidelines = Guideline[]
    for (guideline, applicable) in guidelines
        applicable || continue

        if guideline == :early_exit_if_failed
            all(passed, checked_guidelines) || break
        elseif guideline == :update_status
            # Not doing anything with those here.
        elseif guideline === guideline_version_can_be_pkg_added
            # Do not run for security reasons.
        elseif guideline === guideline_version_can_be_imported
            # Do not run for security reasons.
        elseif guideline === guideline_subdir_parameter_is_correct
            # Do not run because it checks information in the PR body,
            # which probably isn't there in a manual PR.
        else
            check!(guideline, data)
            @info(guideline.info,
                  meets_this_guideline = passed(guideline),
                  message = message(guideline))
            push!(checked_guidelines, guideline)
        end
    end

    println()
    println("------------")
    println()
    print_pr_kind("new package", package_name)

    package_file = only(filter(file -> basename(file.filename) == "Package.toml", files))
    url_raw = only(filter(startswith("repo = \""), get_added_lines(package_file)))
    url = chopsuffix(chopprefix(url_raw, "repo = \""), "\"")
    println("Package repo: $url")
    println()

    for guideline in checked_guidelines
        if passed(guideline)
            pass(guideline.info)
        else
            fail(guideline.info)
            println(stderr, message(guideline))
        end
    end

    println()
    print(
    """
    Notes:
    * This PR is not necessarily created by RegistryTools, check manually
      that things look normal.
    * For security reasons neither Pkg.add nor import has been checked.
      If you trust the package code, manually run the following code to
      verify that adding and importing works.

        using Pkg
        Pkg.activate(temp = true)
        Pkg.add(url = "$(url)",
                rev = "$(tree_hash)")
        using $(package_name)

    * To increase visibility, post this message in the Slack new-packages-feed
      channel:

    New package:  $(package_name) v$(version) (Manual PR)
    Registration: $(pr_data.pr.html_url)
    Repository:   $(url)
    """)

    return true
end

# Not yet implemented.
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

equal_up_to_spaces(a, b) = replace(a, " " => "") == replace(b, " " => "")

# Sanity check of URL. We are quite conservative here but it should be
# liberal enough to cover all currently registered repo names in
# General.
function url_is_normal(url)
    re = r"^https:/(/[\w.~-]+)+$"
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
