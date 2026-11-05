const new_package_title_regex = r"^New package: (\S*) v(\S*)$"

const new_version_title_regex = r"^New version: (\w*?) v(\S*?)$"

# Titles of pull requests that register several versions of one package at once, e.g.
# `New versions: Foo_jll v1.0.0, v1.1.0` or `New package: Foo_jll v1.0.0, v1.1.0`.
const new_package_multiple_versions_title_regex = r"^New package: (\S+) (v[^\s,]+(?:, v[^\s,]+)+)$"

const new_versions_title_regex = r"^New versions: (\w+) (v[^\s,]+(?:, v[^\s,]+)+)$"

const commit_regex = r"Commit: ([0-9a-f]+)"

const version_line_regex = r"Version: v(\S+)"

function is_new_package(pull_request::GitHub.PullRequest)
    t = title(pull_request)
    return occursin(new_package_title_regex, t) ||
        occursin(new_package_multiple_versions_title_regex, t)
end

function is_new_version(pull_request::GitHub.PullRequest)
    t = title(pull_request)
    return occursin(new_version_title_regex, t) || occursin(new_versions_title_regex, t)
end

function check_authorization(
    pkg,
    pr_author_login,
    authorized_authors,
    authorized_authors_special_jll_exceptions,
    error_exit_if_automerge_not_applicable,
)
    if pr_author_login ∉ vcat(authorized_authors, authorized_authors_special_jll_exceptions)
        throw_not_automerge_applicable(
            AutoMergeAuthorNotAuthorized,
            "Author $(pr_author_login) is not authorized to automerge. Exiting...";
            error_exit_if_automerge_not_applicable=error_exit_if_automerge_not_applicable,
        )
        return :not_authorized
    end

    # A JLL-only author (e.g. `jlbuild`) is not allowed to register
    # non-JLL packages.
    this_is_jll_package = is_jll_name(pkg)
    if (!this_is_jll_package && pr_author_login ∉ authorized_authors)
        throw_not_automerge_applicable(
            AutoMergeAuthorNotAuthorized,
            "This package is not a JLL package. Author $(pr_author_login) is not authorized to register non-JLL packages. Exiting...";
            error_exit_if_automerge_not_applicable=error_exit_if_automerge_not_applicable,
        )
        return :not_authorized
    end

    if pr_author_login ∈ authorized_authors_special_jll_exceptions
        return :jll
    end

    return :normal
end

function _parse_title_version_list(list::AbstractString)
    return [VersionNumber(chopprefix(v, "v")) for v in split(list, ", ")]
end

"""
    parse_pull_request_title_versions(registration_type, pull_request) -> (pkg, versions)

Parse the package name and the list of versions (in the order they appear) from the title
of a registration pull request. Single-version titles yield a one-element list.
"""
function parse_pull_request_title_versions(::NewVersion, pull_request::GitHub.PullRequest)
    t = title(pull_request)
    m = match(new_version_title_regex, t)
    if m !== nothing
        return convert(String, m.captures[1])::String, [VersionNumber(m.captures[2])]
    end
    m = match(new_versions_title_regex, t)
    return convert(String, m.captures[1])::String, _parse_title_version_list(m.captures[2])
end

function parse_pull_request_title_versions(::NewPackage, pull_request::GitHub.PullRequest)
    t = title(pull_request)
    m = match(new_package_title_regex, t)
    if m !== nothing
        return convert(String, m.captures[1])::String, [VersionNumber(m.captures[2])]
    end
    m = match(new_package_multiple_versions_title_regex, t)
    return convert(String, m.captures[1])::String, _parse_title_version_list(m.captures[2])
end

function parse_pull_request_title(registration_type, pull_request::GitHub.PullRequest)
    pkg, versions = parse_pull_request_title_versions(registration_type, pull_request)
    return pkg, only(versions)
end

is_multiple_versions_title(t::AbstractString) =
    occursin(new_versions_title_regex, t) || occursin(new_package_multiple_versions_title_regex, t)
is_multiple_versions_title(::Nothing) = false

function commit_from_pull_request_body(pull_request::GitHub.PullRequest)
    pr_body = body(pull_request)
    m = match(commit_regex, pr_body)
    commit = convert(String, m.captures[1])::String
    always_assert(length(commit) == 40)
    return commit
end

"""
    commits_by_version_from_body(body) -> Dict{VersionNumber,String}

Map each `Version: vX.Y.Z` line of a registration pull request body to the first
`Commit: <sha>` line that follows it (before the next `Version:` line). Throws if
a version is listed more than once.
"""
function commits_by_version_from_body(pr_body::AbstractString)
    result = Dict{VersionNumber,String}()
    current = nothing
    for line in eachline(IOBuffer(pr_body))
        mv = match(version_line_regex, line)
        if mv !== nothing
            v = tryparse(VersionNumber, mv.captures[1])
            v === nothing && continue
            haskey(result, v) && error("Version v$(v) is listed more than once in the pull request body")
            current = v
            continue
        end
        mc = match(commit_regex, line)
        if mc !== nothing && current !== nothing
            result[current] = convert(String, mc.captures[1])::String
            current = nothing
        end
    end
    return result
end

"""
    commit_from_pull_request_body(pull_request, version) -> String

The commit that `version` was registered from. A pull request whose title names a single
version keeps using the first `Commit:` line of the body; one whose title names several
versions must pair every version with its commit (`Version: vX` followed by `Commit: <sha>`).
"""
function commit_from_pull_request_body(pull_request::GitHub.PullRequest, version::VersionNumber)
    if !is_multiple_versions_title(title(pull_request))
        return commit_from_pull_request_body(pull_request)
    end
    commits = commits_by_version_from_body(body(pull_request))
    haskey(commits, version) || error("The pull request body does not list a commit for version v$(version)")
    commit = commits[version]
    always_assert(length(commit) == 40)
    return commit
end

function pull_request_build(
    registry_config::RegistryConfiguration,
    pr_config::CheckPRConfiguration,
    api::GitHub.GitHubAPI,
    pr_number::Integer,
    current_pr_head_commit_sha::String,
    registry_repo::GitHub.Repo,
    registry_head::String;
    whoami::String,
    auth::GitHub.Authorization,
)::Nothing
    pr = my_retry(() -> GitHub.pull_request(api, registry_repo, pr_number; auth=auth))
    _github_api_pr_head_commit_sha = pull_request_head_sha(pr)
    if current_pr_head_commit_sha != _github_api_pr_head_commit_sha
        throw(
            AutoMergeShaMismatch(
                "Current commit sha (\"$(current_pr_head_commit_sha)\") does not match what the GitHub API tells us (\"$(_github_api_pr_head_commit_sha)\")",
            ),
        )
    end

    # 1. Check if the PR is open, if not quit.
    # 2. Determine if it is a new package or new version of an
    #    existing package, if neither quit.
    # 3. Check if the author is authorized, if not quit.
    # 4. Call the appropriate method for new package or new version.
    if !is_open(pr)
        throw_not_automerge_applicable(
            AutoMergePullRequestNotOpen,
            "The pull request is not open. Exiting...";
            registry_config.error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    if is_new_package(pr)
        registration_type = NewPackage()
    elseif is_new_version(pr)
        registration_type = NewVersion()
    else
        throw_not_automerge_applicable(
            AutoMergeNeitherNewPackageNorNewVersion,
            "Neither a new package nor a new version. Exiting...";
            registry_config.error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    pkg, title_versions = parse_pull_request_title_versions(registration_type, pr)
    pr_author_login = author_login(pr)
    authorization = check_authorization(
        pkg,
        pr_author_login,
        registry_config.authorized_authors,
        registry_config.authorized_authors_special_jll_exceptions,
        registry_config.error_exit_if_automerge_not_applicable,
    )

    if authorization == :not_authorized
        return nothing
    end

    registry_master = clone_repo(registry_repo)
    if !pr_config.master_branch_is_default_branch
        checkout_branch(registry_master, registry_config.master_branch)
    end

    # The versions that the registry diff actually adds are what gets checked. Whether
    # they agree with the title (and whether anything else changed) is checked by
    # `guideline_registry_changes_match_title`.
    versions = versions_added_by_pr(pkg; registry_master, registry_head)
    if isempty(versions)
        versions = sort(unique(title_versions))
    end
    all_data = [
        GitHubAutoMergeData(;
            api,
            registration_type,
            pr,
            pkg,
            version,
            current_pr_head_commit_sha,
            registry=registry_repo,
            auth,
            authorization,
            registry_head,
            registry_master,
            pr_config.suggest_onepointzero,
            pr_config.point_to_slack,
            whoami,
            pr_config.registry_deps,
            pr_config.public_registries,
            registry_config.read_only,
            pr_config.environment_variables_to_pass,
        ) for version in versions
    ]
    pull_request_build(all_data; pr_config.check_license, pr_config.check_breaking_explanation, registry_config.new_package_waiting_minutes)
    rm(registry_master; force=true, recursive=true)
    return nothing
end

# Guidelines that concern the pull request or the package as a whole rather than one
# version of it. When a pull request registers several versions, these are checked once.
function once_per_pull_request_guidelines()
    return Guideline[
        guideline_registry_consistency_tests_pass,
        guideline_pr_only_changes_allowed_files,
        guideline_registry_changes_match_title,
        guideline_name_identifier,
        guideline_normal_capitalization,
        guideline_name_length,
        guideline_julia_name_check,
        guideline_name_ascii,
        guideline_repo_url_requirement,
        guideline_dependency_confusion,
        guideline_name_match_check,
        guideline_distance_check,
    ]
end

# The `Guideline` constants store the result of their last check, so each version
# gets its own copy.
_fresh_guideline(g::Guideline) = Guideline(; info=g.info, docs=g.docs, check=g.check)

"""
    run_guidelines(all_data, guidelines_for; once, on_failure_so_far) -> Vector{Tuple{Union{Nothing,VersionNumber},Guideline}}

Check the guidelines `guidelines_for(data, i)` for each `data = all_data[i]` (one per version,
ascending). Guidelines in `once` are checked only for the first version. Returns every checked
guideline with the version it was checked for (`nothing` for the ones in `once`).

`:early_exit_if_failed` stops all checking if anything has failed so far, and
`:update_status` calls `on_failure_so_far()` if anything has failed so far.
"""
function run_guidelines(all_data, guidelines_for; once=Guideline[], on_failure_so_far=() -> nothing)
    checked = Tuple{Union{Nothing,VersionNumber},Guideline}[]
    all_passed() = all(passed(g) for (_, g) in checked)
    for (i, version_data) in enumerate(all_data)
        for (guideline, applicable) in guidelines_for(version_data, i)
            applicable || continue
            if guideline == :early_exit_if_failed
                all_passed() || return checked
            elseif guideline == :update_status
                all_passed() || on_failure_so_far()
            else
                is_once = guideline in once
                (is_once && i > 1) && continue
                g = _fresh_guideline(guideline)
                g.passed, g.message = g.check(version_data)
                @info(
                    g.info,
                    version = version_data.version,
                    meets_this_guideline = passed(g),
                    message = message(g)
                )
                push!(checked, (is_once ? nothing : version_data.version, g))
            end
        end
    end
    return checked
end

# The messages of the failed guidelines. When several versions were checked, each
# per-version message names its version.
function failing_guideline_messages(checked; multiple_versions::Bool)
    messages = [
        (multiple_versions && v !== nothing) ? "`v$(v)`: $(message(g))" : message(g)
        for (v, g) in checked if !passed(g)
    ]
    return multiple_versions ? unique(messages) : messages
end

function pull_request_build(data::GitHubAutoMergeData; kwargs...)::Nothing
    return pull_request_build([data]; kwargs...)
end

"""
    pull_request_build(all_data::Vector{GitHubAutoMergeData}; ...)

Check a registration pull request. `all_data` holds one entry per version that the pull
request adds (all for the same package, sorted ascending). Every version goes through the
full list of guidelines, except those in `once_per_pull_request_guidelines()`, which
are checked only for the first version. The pull request passes only if every check passes.
"""
function pull_request_build(all_data::Vector{GitHubAutoMergeData}; check_license, check_breaking_explanation, new_package_waiting_minutes)::Nothing
    always_assert(!isempty(all_data))
    always_assert(allequal(d -> d.pkg, all_data))
    always_assert(issorted(all_data; by=d -> d.version))
    data = first(all_data)
    latest_data = last(all_data)
    multiple_versions = length(all_data) > 1
    kind = package_or_version(data.registration_type)
    this_is_jll_package = is_jll_name(data.pkg)
    @info(
        "This is a new $kind pull request",
        pkg = data.pkg,
        versions = [d.version for d in all_data],
        this_is_jll_package
    )

    update_status(
        data;
        state="pending",
        context="automerge/decision",
        description="New $kind. Pending.",
    )

    this_pr_can_use_special_jll_exceptions =
        this_is_jll_package && data.authorization == :jll
    # We have one exception grandfathered in
    allow_build_metadata = data.pkg == "TZJData"

    checked_guidelines = run_guidelines(
        all_data,
        (version_data, i) -> get_automerge_guidelines(
            version_data.registration_type;
            check_license=check_license,
            check_breaking_explanation=check_breaking_explanation,
            this_is_jll_package=this_is_jll_package,
            this_pr_can_use_special_jll_exceptions=this_pr_can_use_special_jll_exceptions,
            allow_build_metadata=allow_build_metadata,
            use_distance_check=perform_distance_check(version_data.pr.labels),
            package_author_approved=has_package_author_approved_label(version_data.pr.labels),
            later_version_in_pr=i > 1,
        );
        once=once_per_pull_request_guidelines(),
        on_failure_so_far=() -> update_status(
            data;
            state="failure",
            context="automerge/decision",
            description="New version. Failed.",
        ),
    )
    all_passed() = all(passed(g) for (_, g) in checked_guidelines)

    if all_passed() # success
        description = "New $kind. Approved. name=\"$(data.pkg)\". sha=\"$(data.current_pr_head_commit_sha)\""
        update_status(
            data; state="success", context="automerge/decision", description=description
        )
        this_pr_comment_pass = comment_text_pass(
            data.registration_type,
            data.suggest_onepointzero,
            latest_data.version,
            this_pr_can_use_special_jll_exceptions;
            new_package_waiting_minutes,
            data=latest_data
        )
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_pass))
    else # failure
        update_status(
            data;
            state="failure",
            context="automerge/decision",
            description="New $kind. Failed.",
        )
        failing_messages = failing_guideline_messages(checked_guidelines; multiple_versions)
        this_pr_comment_fail = comment_text_fail(
            data.registration_type,
            failing_messages,
            data.suggest_onepointzero,
            latest_data.version;
            point_to_slack=data.point_to_slack,
        )
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_fail))
        throw(AutoMergeGuidelinesNotMet("The automerge guidelines were not met."))
    end
    return nothing
end

package_or_version(::NewPackage) = "package"
package_or_version(::NewVersion) = "version"
