const new_package_title_regex = r"^New package: (\S*) v(\S*)$"

const new_version_title_regex = r"^New version: (\w*?) v(\S*?)$"

const commit_regex = r"Commit: ([0-9a-f]+)"

function is_new_package(pull_request::GitHub.PullRequest)
    return occursin(new_package_title_regex, title(pull_request))
end

function is_new_version(pull_request::GitHub.PullRequest)
    return occursin(new_version_title_regex, title(pull_request))
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

function parse_pull_request_title(::NewVersion, pull_request::GitHub.PullRequest)
    m = match(new_version_title_regex, title(pull_request))
    pkg = convert(String, m.captures[1])::String
    version = VersionNumber(m.captures[2])
    return pkg, version
end

function commit_from_pull_request_body(pull_request::GitHub.PullRequest)
    pr_body = body(pull_request)
    m = match(commit_regex, pr_body)
    commit = convert(String, m.captures[1])::String
    always_assert(length(commit) == 40)
    return commit
end

function parse_pull_request_title(::NewPackage, pull_request::GitHub.PullRequest)
    m = match(new_package_title_regex, title(pull_request))
    pkg = convert(String, m.captures[1])::String
    version = VersionNumber(m.captures[2])
    return pkg, version
end

function pull_request_build(
    api::GitHub.GitHubAPI,
    pr_number::Integer,
    current_pr_head_commit_sha::String,
    registry_repo::GitHub.Repo,
    registry_head::String;
    # Registry config args
    registry::String,
    authorized_authors::Vector{String},
    authorized_authors_special_jll_exceptions::Vector{String},
    new_package_waiting_minutes::Dates.Minute,
    new_jll_package_waiting_minutes::Dates.Minute,
    new_version_waiting_minutes::Dates.Minute,
    new_jll_version_waiting_minutes::Dates.Minute,
    master_branch::String,
    error_exit_if_automerge_not_applicable::Bool,
    read_only::Bool,
    # PR config args
    master_branch_is_default_branch::Bool,
    suggest_onepointzero::Bool,
    point_to_slack::Bool,
    registry_deps::Vector{<:AbstractString},
    check_license::Bool,
    check_breaking_explanation::Bool,
    public_registries::Vector{<:AbstractString},
    environment_variables_to_pass::Vector{<:AbstractString},
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
            error_exit_if_automerge_not_applicable,
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
            error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    pkg, version = parse_pull_request_title(registration_type, pr)
    pr_author_login = author_login(pr)
    authorization = check_authorization(
        pkg,
        pr_author_login,
        authorized_authors,
        authorized_authors_special_jll_exceptions,
        error_exit_if_automerge_not_applicable,
    )

    if authorization == :not_authorized
        return nothing
    end

    registry_master = clone_repo(registry_repo)
    if !master_branch_is_default_branch
        checkout_branch(registry_master, master_branch)
    end
    data = GitHubAutoMergeData(;
        api,
        registration_type,
        pr,
        pkg,
        version,
        current_pr_head_commit_sha,
        registry_repo,
        auth,
        authorization,
        registry_head,
        registry_master,
        suggest_onepointzero,
        point_to_slack,
        whoami,
        registry_deps,
        public_registries,
        read_only,
        environment_variables_to_pass,
    )
    pull_request_build(data; check_license, check_breaking_explanation, new_package_waiting_minutes)
    rm(registry_master; force=true, recursive=true)
    return nothing
end

function pull_request_build(data::GitHubAutoMergeData; check_license, check_breaking_explanation, new_package_waiting_minutes)::Nothing
    kind = package_or_version(data.registration_type)
    this_is_jll_package = is_jll_name(data.pkg)
    @info(
        "This is a new $kind pull request",
        pkg = data.pkg,
        version = data.version,
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

    guidelines = get_automerge_guidelines(
        data.registration_type;
        check_license=check_license,
        check_breaking_explanation=check_breaking_explanation,
        this_is_jll_package=this_is_jll_package,
        this_pr_can_use_special_jll_exceptions=this_pr_can_use_special_jll_exceptions,
        use_distance_check=perform_distance_check(data.pr.labels),
        package_author_approved=has_package_author_approved_label(data.pr.labels)
    )
    checked_guidelines = Guideline[]

    for (guideline, applicable) in guidelines
        applicable || continue
        if guideline == :early_exit_if_failed
            all(passed, checked_guidelines) || break
        elseif guideline == :update_status
            if !all(passed, checked_guidelines)
                update_status(
                    data;
                    state="failure",
                    context="automerge/decision",
                    description="New version. Failed.",
                )
            end
        else
            check!(guideline, data)
            @info(
                guideline.info,
                meets_this_guideline = passed(guideline),
                message = message(guideline)
            )
            push!(checked_guidelines, guideline)
        end
    end

    if all(passed, checked_guidelines) # success
        description = "New $kind. Approved. name=\"$(data.pkg)\". sha=\"$(data.current_pr_head_commit_sha)\""
        update_status(
            data; state="success", context="automerge/decision", description=description
        )
        this_pr_comment_pass = comment_text_pass(
            data.registration_type,
            data.suggest_onepointzero,
            data.version,
            this_pr_can_use_special_jll_exceptions;
            new_package_waiting_minutes,
            data=data
        )
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_pass))
    else # failure
        update_status(
            data;
            state="failure",
            context="automerge/decision",
            description="New $kind. Failed.",
        )
        failing_messages = message.(filter(!passed, checked_guidelines))
        this_pr_comment_fail = comment_text_fail(
            data.registration_type,
            failing_messages,
            data.suggest_onepointzero,
            data.version;
            point_to_slack=data.point_to_slack,
        )
        my_retry(() -> update_automerge_comment!(data, this_pr_comment_fail))
        throw(AutoMergeGuidelinesNotMet("The automerge guidelines were not met."))
    end
    return nothing
end

package_or_version(::NewPackage) = "package"
package_or_version(::NewVersion) = "version"
